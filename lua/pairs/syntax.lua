-- Tree-sitter describes insertion boundaries; the lexer still decides pairing.
local M = {}

local function before(row, col, other_row, other_col)
  return row < other_row or (row == other_row and col < other_col)
end

local function string_node(kind)
  return kind == "string"
    or kind:find("string_literal", 1, true) ~= nil
    or kind == "template_string"
    or kind == "char_literal"
    or kind == "character_literal"
end

local function line(buf, row)
  return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
end

local function missing_end(node)
  local count = node:child_count()
  local last = count > 0 and node:child(count - 1) or nil
  return last ~= nil and last:missing()
end

local function comment_closed(buf, node)
  local sr, sc, er, ec = node:range()
  local header = line(buf, sr):sub(sc + 1, sc + 12)
  if header:sub(1, 2) == "/*" then
    return line(buf, er):sub(ec - 1, ec) == "*/"
  end
  local equals = header:match("^%-%-%[(=*)%[")
  if equals then
    local closing = "]" .. equals .. "]"
    return line(buf, er):sub(ec - #closing + 1, ec) == closing
  end
  return false -- Line comments include the insertion at end of line.
end

local function string_context(buf, node)
  local sr, sc, er, ec = node:range()
  local header = line(buf, sr):sub(sc + 1, sc + 8)
  local prefix, quote = header:match("^([%a]*)(['\"])")
  local triple = quote and header:sub(#prefix + 1, #prefix + 3) == string.rep(quote, 3)
  local literal = sr ~= er
    or not quote
    or triple
    or node:type():find("raw", 1, true) ~= nil
    or node:type() == "template_string"
    or prefix:lower():find("f", 1, true) ~= nil
  return {
    syntax = "string",
    literal_string = literal,
    string_quote = not literal and quote or nil,
    string_close = not literal and line(buf, er):sub(ec, ec) == quote and ec - 1 or nil,
    string_empty = quote ~= nil and not triple and sr == er and ec == sc + #prefix + 2,
    empty_quote = not triple and quote or nil,
    string_prefix = prefix,
    string_start = sc,
    literal_delimiter = triple and string.rep(quote, 3) or nil,
    literal_start_row = sr,
    literal_open_col = quote and sc + #prefix or nil,
    literal_close_row = er,
    literal_close_col = triple
        and not missing_end(node)
        and line(buf, er):sub(ec - 2, ec) == string.rep(quote, 3)
        and ec - 3
      or nil,
  }
end

-- Only mask completed strings/comments in the current line prefix. Binary
-- search avoids visiting every preceding statement in a large buffer.
local function code_prefix(root, text, row, col, start)
  local spans, visited, has_error, failure = {}, 0, false, "syntax_limit"
  local function visit(node)
    visited = visited + 1
    if visited > 256 then
      return false
    end
    local sr, sc, er, ec = node:range()
    if not before(sr, sc, row, col) or not before(row, start, er, ec) then
      return true
    end
    local kind = node:type()
    if kind == "ERROR" then
      has_error = true
    end
    if (string_node(kind) or kind:find("comment", 1, true)) and not before(row, col, er, ec) then
      if string_node(kind) and missing_end(node) then
        failure = "syntax_incomplete"
        return false
      end
      spans[#spans + 1] = { sr == row and math.max(sc, start) or start, er == row and ec or col }
      return true
    end
    local low, high = 0, node:named_child_count()
    while low < high do
      local mid = math.floor((low + high) / 2)
      local child = node:named_child(mid)
      local _, _, cr, cc = child:range()
      if before(row, start, cr, cc) then
        high = mid
      else
        low = mid + 1
      end
    end
    for i = low, node:named_child_count() - 1 do
      local child = node:named_child(i)
      local cr, cc = child:range()
      if not before(cr, cc, row, col) then
        break
      end
      if not visit(child) then
        return false
      end
    end
    return true
  end
  if not visit(root) then
    return nil, failure
  end
  local masked = string.rep(" ", start) .. text:sub(start + 1)
  for _, span in ipairs(spans) do
    masked = masked:sub(1, span[1]) .. string.rep(" ", span[2] - span[1]) .. masked:sub(span[2] + 1)
  end
  local prefix = masked:sub(1, col)
  if
    has_error
    and (
      prefix:find("/*", 1, true)
      or prefix:find("`", 1, true)
      or prefix:find('"""', 1, true)
      or prefix:find("'''", 1, true)
      or prefix:find("%[=*%[")
      or prefix:find('r#+"')
    )
  then
    return nil, "syntax_incomplete" -- The literal may have lost its syntax node.
  end
  return masked
end

function M.capture(buf, row, col, text)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return {}
  end
  local left = math.max(col - 1, 0)
  local range = { row, left, row, left }
  -- A callback selects Neovim's time-sliced parsing API (0.11+). Never opt into
  -- a forced synchronous parse, even if the user's debug flag requests one.
  if not parser:is_valid(false, range) then
    if vim.g._ts_force_sync_parsing then
      return { syntax = "unknown" }
    end
    parser:parse(range, function() end)
  end
  if not parser:is_valid(false, range) then
    return { syntax = "unknown" }
  end
  local language = parser:language_for_range(range)
  local tree = language:tree_for_range(range)
  if not tree then
    return { syntax = "unknown" }
  end
  local root = tree:root()
  local node = root:named_descendant_for_range(row, left, row, left)
  local start = 0
  local previous_string
  while node do
    local kind = node:type()
    local sr, sc, er, ec = node:range()
    local at_end = row == er and col == ec
    if at_end and string_node(kind) and not missing_end(node) then
      local previous = string_context(buf, node)
      if previous.string_empty then
        previous_string = previous
      end
    end
    local inside = not before(row, col, sr, sc)
      and (
        before(row, col, er, ec)
        or (at_end and kind:find("comment", 1, true) and not comment_closed(buf, node))
        or (at_end and string_node(kind) and missing_end(node))
      )
    if inside then
      if kind:find("comment", 1, true) then
        return { syntax = "comment" }
      elseif string_node(kind) then
        return string_context(buf, node)
      elseif
        kind == "template_substitution"
        or kind == "interpolation"
        or kind == "format_expression"
      then
        local opener = node:child(0)
        local br, bc = opener:end_()
        start = br == row and bc or 0
        -- Python's conversion/format suffix is string text. Nested format
        -- expressions are visited first and remain code.
        for _, field in ipairs({ "format_specifier", "type_conversion" }) do
          local suffix = node:field(field)[1]
          if suffix then
            local fr, fc = suffix:range()
            if before(fr, fc, row, col) then
              return { syntax = "string", literal_string = true }
            end
          end
        end
        break
      elseif kind == "format_specifier" or kind == "type_conversion" then
        return { syntax = "string", literal_string = true }
      end
    end
    node = node:parent()
  end
  local masked, reason = code_prefix(root, text, row, col, start)
  return masked and { syntax = "code", lex_line = masked, previous_string = previous_string }
    or { syntax = "unknown", syntax_reason = reason }
end

return M

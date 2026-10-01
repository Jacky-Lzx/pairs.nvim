-- Tree-sitter describes insertion boundaries; the lexer still decides pairing.
local M = {}
local template_languages = { javascript = true, typescript = true, tsx = true }

local function before(row, col, other_row, other_col)
  return row < other_row or (row == other_row and col < other_col)
end

local function string_node(kind)
  return kind == "string"
    or kind:find("string_literal", 1, true) ~= nil
    or kind == "template_string"
    or kind == "char_literal"
    or kind == "character_literal"
    or kind == "regex"
    or kind == "jsx_text"
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
  local last = node:child(node:child_count() - 1)
  local template = node:type() == "template_string"
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
    template = template,
    template_start_row = template and sr or nil,
    template_open_col = template and sc or nil,
    template_close_row = template and er or nil,
    template_close_col = template and last and last:type() == "`" and not last:missing() and ec - 1
      or nil,
  }
end

-- Markdown measures indentation using fixed four-column tab stops.
local function markdown_columns(text)
  local col = 0
  for char in text:gmatch(".") do
    col = col + (char == "\t" and 4 - col % 4 or 1)
  end
  return col
end

-- Container markers come from the outer grammar. Replace opening list markers
-- with continuation spaces; keep quote markers and any existing indentation.
local function fence_prefix(node, row, prefix)
  local parent, containers, quotes = node:parent(), false, 0
  while parent do
    if parent:type() == "list_item" then
      containers = true
      local marker = parent:named_child(0)
      if not marker or not marker:type():find("list_marker_", 1, true) then
        return nil
      end
      local sr, sc, er, ec = marker:range()
      if sr == row then
        if er ~= row or ec > #prefix then
          return nil
        end
        prefix = prefix:sub(1, sc)
          .. prefix:sub(sc + 1, ec):gsub("[^ \t]", " ")
          .. prefix:sub(ec + 1)
      end
    elseif parent:type() == "block_quote" then
      containers, quotes = true, quotes + 1
    end
    parent = parent:parent()
  end
  local _, count = prefix:gsub(">", "")
  if prefix:find("[^ >\t]") or count ~= quotes then
    return nil
  end
  -- Markdown defines tab stops every four columns, independently of tabstop.
  local col = 0
  prefix = prefix:gsub(".", function(char)
    local width = char == "\t" and 4 - col % 4 or 1
    col = col + width
    return char == "\t" and string.rep(" ", width) or char
  end)
  return prefix, containers
end

local function markdown_fence(buf, parser, range)
  local tree = parser:tree_for_range(range)
  if not tree then
    return nil
  end
  local node = tree:root():named_descendant_for_range(unpack(range))
  while node do
    if node:type() == "fenced_code_block" then
      local opening = node:named_child(0)
      local last
      if not opening or opening:type() ~= "fenced_code_block_delimiter" then
        return nil
      end
      local row, col = opening:range()
      local text = line(buf, row)
      local suffix = text:sub(col + 1)
      local indent, delimiter = suffix:match("^([ \t]*)(`+)[^`]*$")
      if not indent then
        indent, delimiter = suffix:match("^([ \t]*)(~+).*$")
      end
      local prefix, containers
      if
        indent
        and markdown_columns(text:sub(1, col + #indent)) - markdown_columns(text:sub(1, col)) <= 3
      then
        prefix, containers = fence_prefix(node, row, text:sub(1, col + #indent))
      end
      local result = {
        open_row = row,
        supported = prefix ~= nil and #delimiter >= 3,
        delimiter = delimiter,
        prefix = containers and prefix or nil,
        has_content = false,
      }
      -- The block has at most a few direct children. Content descendants are
      -- not traversed, so large code blocks do not add scanning work.
      for child in node:iter_children() do
        if child:type() == "code_fence_content" then
          result.has_content = true
        elseif child:type() == "fenced_code_block_delimiter" and child:range() > row then
          last = child
        end
      end
      if last and not last:missing() then
        local cr, cc = last:range()
        local closing = line(buf, cr)
        -- The grammar sometimes excludes excessive closing indentation from
        -- the delimiter node. Count from the container continuation instead.
        local base = 0
        local continuation = tree:root():named_descendant_for_range(cr, 0, cr, 0)
        if continuation:type() == "block_continuation" then
          local sr, _, er, ec = continuation:range()
          if sr == cr and er == cr then
            base = ec
          end
        end
        local char = delimiter and delimiter:sub(1, 1)
        local pattern = char == "~" and "^([ \t]*)(~+)[ \t]*$" or "^([ \t]*)(`+)[ \t]*$"
        local spaces, run = closing:sub(base + 1):match(pattern)
        if
          spaces
          and delimiter
          and #run >= #delimiter
          and base + #spaces >= cc
          and markdown_columns(closing:sub(1, base + #spaces))
              - markdown_columns(closing:sub(1, base))
            <= 3
        then
          result.close_row = cr
          result.close_col, result.close_end = base + #spaces, base + #spaces + #run
        end
      end
      return result
    end
    node = node:parent()
  end
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

function M.capture(buf, row, col, text, environments)
  -- These filetypes are not registered as aliases in a bare Neovim runtime.
  -- Respect an explicit language registration before using standard aliases.
  local ft = vim.bo[buf].filetype
  local lang = vim.treesitter.language.get_lang(ft)
  if lang == ft then
    lang = ({
      javascriptreact = "javascript",
      typescriptreact = "tsx",
      tex = "latex",
      plaintex = "latex",
    })[ft] or lang
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
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
  local fence = parser:lang() == "markdown" and markdown_fence(buf, parser, range) or nil
  local tex
  if parser:lang() == "latex" then
    local outer = parser:tree_for_range(range)
    if outer then
      tex = require("pairs.tex_syntax").capture(outer:root(), row, col, text, buf, environments)
    end
  end
  local function with_context(context)
    context.fence = fence
    context.tex = tex
    if tex and tex.lex_line then
      context.lex_line = tex.lex_line
      if tex.raw_comment and context.syntax == "comment" then
        context.syntax = "code"
      end
    end
    if tex and tex.literal then
      context.syntax, context.literal_string = "string", true
    elseif tex and tex.uncertain then
      context.syntax = "unknown"
    end
    return context
  end
  -- Tagged templates can inject HTML/SQL/etc. Those trees do not contain the
  -- template's delimiters or substitutions; the outer JS/TS grammar owns them.
  local language = template_languages[parser:lang()] and parser or parser:language_for_range(range)
  local tree = language:tree_for_range(range)
  if not tree then
    return with_context({ syntax = "unknown" })
  end
  local root = tree:root()
  local node = root:named_descendant_for_range(row, left, row, left)
  local start = 0
  local previous_string
  local substitution
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
        return with_context({ syntax = "comment" })
      elseif string_node(kind) then
        return with_context(string_context(buf, node))
      elseif
        kind == "template_substitution"
        or kind == "interpolation"
        or kind == "format_expression"
      then
        local opener = node:child(0)
        local br, bc = opener:end_()
        start = br == row and bc or 0
        if kind == "template_substitution" then
          local closer = node:child(node:child_count() - 1)
          substitution = {
            body_row = br,
            body_col = bc,
            close_row = er,
            close_col = closer and closer:type() == "}" and not closer:missing() and ec - 1 or nil,
          }
        end
        -- Python's conversion/format suffix is string text. Nested format
        -- expressions are visited first and remain code.
        for _, field in ipairs({ "format_specifier", "type_conversion" }) do
          local suffix = node:field(field)[1]
          if suffix then
            local fr, fc = suffix:range()
            if before(fr, fc, row, col) then
              return with_context({ syntax = "string", literal_string = true })
            end
          end
        end
        break
      elseif kind == "format_specifier" or kind == "type_conversion" then
        return with_context({ syntax = "string", literal_string = true })
      end
    end
    node = node:parent()
  end
  local masked, reason = code_prefix(root, text, row, col, start)
  return with_context(masked and {
    syntax = "code",
    lex_line = masked,
    previous_string = previous_string,
    substitution = substitution,
  } or { syntax = "unknown", syntax_reason = reason })
end

return M

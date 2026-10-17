-- Tree-sitter contributes protected spans; the bounded text scanner retains
-- search/count semantics and trims against original, unmasked content.
local M = {}
local quotes = { ['"'] = true, ["'"] = true, ["`"] = true }

function M.candidates(context, spec)
  local range =
    { context.first_row, 0, context.first_row + #context.lines - 1, #context.lines[#context.lines] }
  local ft = vim.bo[context.buf].filetype
  local lang = vim.treesitter.language.get_lang(ft)
  if lang == ft then
    lang = ({
      javascriptreact = "javascript",
      typescriptreact = "tsx",
      tex = "latex",
      plaintex = "latex",
    })[ft] or lang
  end
  local ok, parser = pcall(vim.treesitter.get_parser, context.buf, lang)
  if not ok or not parser then
    return nil, "missing_parser"
  end
  if not parser:is_valid(false, range) then
    if vim.g._ts_force_sync_parsing then
      return nil, "pending"
    end
    -- Native time slicing: never wait for a stale tree or queue an edit.
    parser:parse(range, function() end)
  end
  if not parser:is_valid(false, range) then
    return nil, "pending"
  end
  local tree = parser:tree_for_range(range)
  if not tree then
    return nil, "pending"
  end
  local protected, string_regions, visited, unsafe = {}, {}, 0, false
  local function offset(row, col)
    if row < context.first_row then
      return 0
    end
    local index = row - context.first_row + 1
    if not context.starts[index] then
      return #context.text
    end
    return math.min(#context.text, context.starts[index] + col)
  end
  local function span(node)
    local sr, sc, er, ec = node:range()
    return offset(sr, sc), offset(er, ec), sr, er
  end
  local function mask(first, last)
    if first < last then
      protected[#protected + 1] = { first, last }
    end
  end
  local walk
  walk = function(node, depth)
    depth = depth or 0
    if depth > 256 then
      unsafe = true
      return
    end
    local first, last, sr, er = span(node)
    if first >= last then
      return
    end
    visited = visited + 1
    if visited > 10000 or node:missing() or node:type() == "ERROR" then
      unsafe = true
      return
    end
    local kind = node:type()
    if kind:find("comment", 1, true) then
      mask(first, last)
      return
    end
    local string = kind == "string"
      or kind == "template_string"
      or kind == "char_literal"
      or kind == "character_literal"
      or kind:find("string_literal", 1, true)
      or kind == "regex"
      or kind == "jsx_text"
    if string then
      if node:has_error() then
        unsafe = true
        return
      end
      -- Only complete strings wholly inside the search window are targets.
      if sr >= context.first_row and er < context.first_row + #context.lines then
        local text = context.text:sub(first + 1, last)
        local prefix, quote = text:match("^([rRuUbBfF]*)(['\"])")
        if text:sub(1, 1) == "`" then
          prefix, quote = "", "`"
        end
        if quote then
          local width = text:sub(#prefix + 1, #prefix + 3) == quote:rep(3) and 3 or 1
          if text:sub(-width) == quote:rep(width) and #text >= #prefix + 2 * width then
            string_regions[#string_regions + 1] = {
              first = first + #prefix,
              inner_first = first + #prefix + width,
              inner_last = last - width,
              last = last,
              quote = quote,
            }
          end
        end
      end
      -- Preserve code inside substitutions, while masking literal segments.
      local cursor = first
      for child in node:iter_children() do
        local type_ = child:type()
        if
          type_:find("interpolation", 1, true)
          or type_ == "template_substitution"
          or type_ == "formatted_value"
        then
          local a, b = span(child)
          mask(cursor, a)
          walk(child, depth + 1)
          cursor = b
        end
      end
      mask(cursor, last)
      return
    end
    -- Binary search direct children so unrelated earlier lines cannot consume
    -- the node budget in a large source file.
    local count, lo, hi = node:child_count(), 0, node:child_count()
    while lo < hi do
      local mid = math.floor((lo + hi) / 2)
      local child = node:child(mid)
      local _, ending = span(child)
      if ending <= 0 then
        lo = mid + 1
      else
        hi = mid
      end
    end
    for i = lo, count - 1 do
      local child = node:child(i)
      local a = span(child)
      if a >= #context.text then
        break
      end
      walk(child, depth + 1)
      if unsafe then
        return
      end
    end
  end
  walk(tree:root())
  if unsafe then
    return nil, "unsafe_tree"
  end
  if spec.kind == "quote" or (spec.left == spec.right and quotes[spec.left]) then
    local result = {}
    for _, item in ipairs(string_regions) do
      if spec.kind == "quote" or item.quote == spec.left then
        result[#result + 1] = item
      end
    end
    return result
  end
  -- Tag attributes have their own quotes, which the tag tokenizer already
  -- handles. Text-level tags remain useful outside HTML/XML grammars too.
  if spec.kind == "tag" then
    return require("pairs.surround_scan").candidates(context.text, spec)
  end
  table.sort(protected, function(a, b)
    return a[1] < b[1]
  end)
  local chunks, cursor = {}, 0
  for _, item in ipairs(protected) do
    if item[2] > cursor then
      chunks[#chunks + 1] = context.text:sub(cursor + 1, math.max(cursor, item[1]))
      chunks[#chunks + 1] =
        context.text:sub(math.max(cursor, item[1]) + 1, item[2]):gsub("[^\n]", " ")
      cursor = item[2]
    end
  end
  chunks[#chunks + 1] = context.text:sub(cursor + 1)
  return require("pairs.surround_scan").candidates(context.text, spec, table.concat(chunks))
end

return M

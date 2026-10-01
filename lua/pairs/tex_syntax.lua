-- Extract dollar boundaries from the current outer LaTeX tree.
local lex = require("pairs.lex")
local M = {}
local literal = {
  verbatim_environment = true,
  listing_environment = true,
  minted_environment = true,
  asy_environment = true,
  asydef_environment = true,
  pycode_environment = true,
  luacode_environment = true,
  sagesilent_environment = true,
  sageblock_environment = true,
  source_code = true,
  text_mode = true,
}
local math_nodes = {
  inline_formula = true,
  displayed_equation = true,
  math_environment = true,
  math_delimiter = true,
}
-- A lone dollar can make the grammar recover a whole environment as ERROR.
-- Only recover ordinary environments whose content mode is known. Custom and
-- math environments stay literal until the grammar proves a valid boundary.
local text_environments = {
  document = true,
  center = true,
  flushleft = true,
  flushright = true,
  quote = true,
  quotation = true,
  itemize = true,
  enumerate = true,
  description = true,
  figure = true,
  ["figure*"] = true,
  table = true,
  ["table*"] = true,
  minipage = true,
}

local function short_text(node, buf)
  if not node then
    return nil
  end
  local sr, sc, er, ec = node:range()
  if sr ~= er or ec - sc > 64 then
    return nil
  end
  return vim.treesitter.get_node_text(node, buf)
end

local function ordinary_prefix(parent, leaf, buf)
  -- Inspect only direct recovery children, never descend through document
  -- bodies. Bound work even when an incomplete document has many siblings.
  for i = 0, math.min(parent:child_count(), 256) - 1 do
    local child = parent:child(i)
    if child:id() == leaf:id() then
      return true
    end
    if not child:named() or child:has_error() then
      return false -- Includes an earlier unresolved math delimiter.
    end
    if child:type() == "begin" then
      local name = short_text(child:field("name")[1], buf)
      if not name or not text_environments[name:match("^%{(.*)%}$")] then
        return false
      end
    elseif child:type() == "generic_command" then
      local command = short_text(child:field("command")[1], buf)
      if not command or command == "\\begin" or command == "\\end" then
        return false
      end
    end
  end
  return false
end

local function inline_literal(text, col)
  -- The grammar parses \verb as a generic command. Mask its delimiter span,
  -- including an unfinished span, rather than trusting dollar nodes inside it.
  local from = 1
  while from <= #text do
    local first, last = text:find("\\verb%*?", from)
    if not first then
      break
    end
    local delimiter = text:sub(last + 1, last + 1)
    if not lex.escaped(text, first - 1) and delimiter ~= "" and not delimiter:match("[%a%s]") then
      local finish = text:find(delimiter, last + 2, true)
      if col >= last + 1 and (not finish or col < finish) then
        return true
      end
    end
    from = last + 1
  end
  -- Other inline code commands have package-specific option/delimiter syntax.
  -- Conservatively preserve input on their remaining line.
  for _, command in ipairs({ "\\lstinline", "\\mintinline" }) do
    local start = text:find(command, 1, true)
    if start and not lex.escaped(text, start - 1) and col >= start + #command then
      return true
    end
  end
  return false
end

function M.capture(root, row, col, text, buf)
  local result = { upgrade = false }
  if inline_literal(text, col) then
    return { blocked = true }
  end
  local left = math.max(col - 1, 0)
  local leaf = root:descendant_for_range(row, left, row, left)
  local parent = leaf:parent()
  local sr, sc, er, ec = leaf:range()
  local candidate = leaf:type() == "$"
    and not leaf:missing()
    and sr == row
    and er == row
    and sc == col - 1
    and ec == col
  if candidate and parent then
    if parent:type() == "ERROR" then
      result.upgrade = ordinary_prefix(parent, leaf, buf)
    elseif parent:type() == "inline_formula" then
      result.upgrade = parent:child(0):id() == leaf:id()
        and parent:child(parent:child_count() - 1):missing()
    end
  end
  local node, display = leaf, nil
  while node do
    local kind = node:type()
    local _, _, nr, nc = node:range()
    local inside = row < nr
      or (row == nr and col < nc)
      or (kind == "line_comment" and row == nr and col == nc)
    if inside and (literal[kind] or kind:find("comment", 1, true)) then
      return { blocked = true }
    end
    if kind == "ERROR" and (not parent or node:id() ~= parent:id()) then
      result.upgrade = false
    end
    if math_nodes[kind] then
      if not parent or node:id() ~= parent:id() then
        result.upgrade = false
      end
      if kind == "displayed_equation" and not display then
        display = node
        local open, close = node:child(0), node:child(node:child_count() - 1)
        if open:type() == "$$" and close:type() == "$$" and not close:missing() then
          local br, bc = open:range()
          local cr, cc = close:range()
          result.pair = { open_row = br, open_col = bc, close_row = cr, close_col = cc }
        end
      elseif display then
        return { blocked = true } -- No nested display inside another math zone.
      end
    end
    node = node:parent()
  end
  return result
end

return M

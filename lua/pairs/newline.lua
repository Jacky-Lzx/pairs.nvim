local M = {}

local function code(keys)
  return vim.api.nvim_replace_termcodes(keys, true, true, true)
end

local function whitespace(columns)
  if vim.bo.expandtab then
    return string.rep(" ", columns)
  end
  local stops = {}
  for stop in vim.bo.vartabstop:gmatch("%d+") do
    stops[#stops + 1] = tonumber(stop)
  end
  if #stops == 0 then
    stops = { vim.bo.tabstop }
  end
  local tabs, width = 0, 0
  while width + stops[math.min(tabs + 1, #stops)] <= columns do
    width = width + stops[math.min(tabs + 1, #stops)]
    tabs = tabs + 1
  end
  -- Literal tabs must not be expanded again by smarttab/softtabstop.
  return string.rep(code("<C-v><Tab>"), tabs) .. string.rep(" ", columns - width)
end

function M.reset(columns, inner)
  -- Ctrl-T establishes native indentation state even when indentexpr returned
  -- -1. Native 0/Ctrl-D can then clear indentation on insertion and dot replay.
  return (inner and code("<BS>") or "")
    .. code("<C-t>0<C-d>")
    .. whitespace(columns)
    .. (inner and "x" or "")
end

-- Called by the expression register after native Enter has created the line.
-- Return typed indentation commands without editing buffer text.
function M.indent(inner)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local view = vim.fn.winsaveview()
  local old_lnum = vim.v.lnum
  vim.v.lnum = row
  local ok, width
  if vim.bo.indentexpr ~= "" then
    ok, width = pcall(vim.api.nvim_eval, vim.bo.indentexpr)
  else
    ok, width = pcall(vim.fn.cindent, row)
  end
  vim.v.lnum = old_lnum
  -- Some indent functions search backwards and rely on Neovim's native caller
  -- to restore the cursor. Expression-register evaluation needs the same guard.
  vim.fn.winrestview(view)
  vim.api.nvim_win_set_cursor(0, cursor)
  if not ok or type(width) ~= "number" or width < 0 then
    width = vim.fn.indent(row)
  end
  return M.reset(math.floor(width), inner)
end

function M.prefix(prefix, inner)
  -- Clear native indentation and comment/list continuation before restoring
  -- the grammar-confirmed prefix. All commands remain in native redo history.
  return (inner and "" or "x") .. code("<C-u><C-t>0<C-d>") .. prefix .. (inner and "x" or "")
end

local function prefix_keys(prefix, inner)
  return (inner and "x" or "")
    .. code(
      string.format(
        "<C-r>=luaeval(\"require('pairs.newline').prefix(_A, %s)\", %q)<CR>",
        tostring(inner),
        prefix
      )
    )
end

function M.continue(prefix)
  return code("<CR>") .. prefix_keys(prefix, false)
end

function M.keys(indent_offset, insert_close, prefix)
  local first, last
  if prefix ~= nil then
    first, last = prefix_keys(prefix, true), prefix_keys(prefix, false)
  elseif indent_offset == nil and (vim.bo.indentexpr ~= "" or vim.bo.cindent) then
    -- Evaluate indentation after creating each line. The returned typed
    -- whitespace is recorded for dot replay, unlike a later API edit or Ctrl-F.
    first = "x" .. code("<C-r>=luaeval(\"require('pairs.newline').indent(true)\")<CR>")
    last = code("<C-r>=luaeval(\"require('pairs.newline').indent(false)\")<CR>")
  else
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local indent = vim.api.nvim_get_current_line():match("^%s*") or ""
    local base = vim.fn.virtcol({ row, #indent + 1 }) - 1
    first = "x"
      .. code(
        string.format(
          "<C-r>=luaeval(\"require('pairs.newline').reset(%d, true)\")<CR>",
          base + (indent_offset or vim.fn.shiftwidth(base))
        )
      )
    last =
      code(string.format("<C-r>=luaeval(\"require('pairs.newline').reset(%d, false)\")<CR>", base))
  end
  -- A temporary, isolated word lets native Ctrl-Left return across the newline
  -- without ending the insertion. Native Delete removes it before returning.
  -- Every text/motion command is recorded by Neovim for undo and dot replay.
  local closing = insert_close or ""
  return code("<CR>")
    .. first
    .. code("<CR>")
    .. last
    .. closing
    .. string.rep(code("<C-g>U<Left>"), #closing + (prefix and #prefix or 0))
    .. code("<C-g>U<C-Left><Del>")
end

return M

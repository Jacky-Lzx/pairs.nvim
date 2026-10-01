local M = {}

local comments = {
  lua = { "--" },
  python = { "#" },
  sh = { "#" },
  bash = { "#" },
  zsh = { "#" },
  ruby = { "#" },
  yaml = { "#" },
  toml = { "#" },
  tex = { "%" },
  plaintex = { "%" },
  c = { "//" },
  cpp = { "//" },
  rust = { "//" },
  swift = { "//" },
  go = { "//" },
  java = { "//" },
  javascript = { "//" },
  javascriptreact = { "//" },
  typescript = { "//" },
  typescriptreact = { "//" },
  cs = { "//" },
}

local function syntax_at(buf, row, col)
  local parser_ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not parser_ok or not parser then
    return nil
  end
  -- Do not force an unbounded synchronous parse on the input path, or trust an
  -- old tree after an edit. An active highlighter normally refreshes this tree.
  local range = { row, math.max(col - 1, 0), row, math.max(col - 1, 0) }
  local language = parser:language_for_range(range)
  if not parser:is_valid(true) or not language:is_valid(true) then
    return "unknown"
  end
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { row, math.max(col - 1, 0) },
    ignore_injections = false,
  })
  if not ok or not node then
    return nil
  end
  local string_context
  while node do
    local kind = node:type()
    local start_row, start_col, end_row, end_col = node:range()
    -- An insertion immediately after a completed node is outside that node.
    local inside = row < end_row or (row == end_row and col < end_col)
    if inside and kind:find("comment") then
      return "comment"
    end
    if
      inside and (kind:find("string") or kind == "char_literal" or kind == "character_literal")
    then
      string_context = "string"
      -- Quotes in a raw/multiline literal are literal text, even when a
      -- line-local scan happens to see an apparently balanced quoted string.
      if kind == "string" or kind:find("literal") or kind == "template_string" then
        local start_line = vim.api.nvim_buf_get_lines(buf, start_row, start_row + 1, false)[1] or ""
        local opening = start_line:sub(start_col + 1, start_col + 1)
        local literal = start_row ~= row
          or end_row ~= row
          or opening == "["
          or kind:find("raw") ~= nil
          or kind == "template_string"
        return "string", literal
      end
    end
    node = node:parent()
  end
  return string_context
end

function M.capture(config, global_enabled, assume_insert)
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ft = vim.bo[buf].filetype
  local rules = require("pairs.config").resolve(config, ft, vim.b[buf].pairs_rules)
  local enabled = global_enabled and vim.b[buf].pairs_enabled ~= false
  local reason
  if not enabled then
    reason = "disabled"
  elseif not assume_insert and vim.fn.mode():sub(1, 1) ~= "i" then
    enabled, reason = false, "mode"
  elseif vim.o.paste or vim.fn.reg_recording() ~= "" or vim.fn.reg_executing() ~= "" then
    enabled, reason = false, "paste_or_macro"
  elseif not vim.bo[buf].modifiable or vim.bo[buf].buftype ~= "" then
    enabled, reason = false, "buffer_type"
  elseif
    vim.tbl_contains(config.disabled_filetypes, ft)
    or (config.filetypes[ft] or {}).enabled == false
  then
    enabled, reason = false, "filetype"
  elseif type(config.enabled) == "function" then
    enabled = not not config.enabled(buf)
    reason = not enabled and "enabled_predicate" or nil
  elseif not config.enabled then
    enabled, reason = false, "disabled"
  end
  local openers, closers, quotes = {}, {}, { ['"'] = true, ["'"] = true }
  for open, rule in pairs(rules) do
    if rule ~= false and open ~= rule.close then
      openers[open], closers[rule.close] = rule.close, open
    elseif rule ~= false then
      quotes[open] = true
    end
  end
  if
    ft == "javascript"
    or ft == "typescript"
    or ft == "go"
    or ft == "javascriptreact"
    or ft == "typescriptreact"
  then
    quotes["`"] = true
  end
  local ctx = {
    buf = buf,
    filetype = ft,
    line = vim.api.nvim_get_current_line(),
    col = cursor[2],
    enabled = enabled,
    disabled_reason = reason,
    rules = rules,
    lex = {
      max_scan_bytes = config.max_scan_bytes,
      line_comments = comments[ft] or {},
      openers = openers,
      closers = closers,
      quotes = quotes,
      rust = ft == "rust",
    },
  }
  if enabled and config.treesitter and #ctx.line <= config.max_scan_bytes then
    ctx.syntax, ctx.literal_string = syntax_at(buf, cursor[1] - 1, cursor[2])
  end
  return ctx
end

return M

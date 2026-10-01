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

function M.capture(config, global_enabled, assume_insert)
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local ft = vim.bo[buf].filetype
  local resolved = require("pairs.config").capture(config, ft, vim.b[buf].pairs_rules)
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
  local quotes = resolved.quotes
  if
    ft == "javascript"
    or ft == "typescript"
    or ft == "go"
    or ft == "javascriptreact"
    or ft == "typescriptreact"
  then
    quotes = resolved.tick_quotes
  end
  -- Predicates can update multi rules. Keep their original evaluation order.
  local multi_buffer = vim.b[buf].pairs_multi_rules
  local multi_rules = multi_buffer
      and require("pairs.config").resolve_multi(config, ft, multi_buffer)
    or resolved.multi_rules
  local ctx = {
    buf = buf,
    filetype = ft,
    line = vim.api.nvim_get_current_line(),
    col = cursor[2],
    enabled = enabled,
    disabled_reason = reason,
    rules = resolved.rules,
    multi_rules = multi_rules,
    row = cursor[1] - 1,
    lex = {
      max_scan_bytes = config.max_scan_bytes,
      line_comments = comments[ft] or {},
      openers = resolved.openers,
      closers = resolved.closers,
      quotes = quotes,
      rust = ft == "rust",
    },
  }
  if enabled and config.treesitter and #ctx.line <= config.max_scan_bytes then
    local environments
    if ft == "tex" or ft == "plaintex" then
      environments =
        require("pairs.config").resolve_tex(config, ft, vim.b[buf].pairs_tex_environments)
    end
    local syntax =
      require("pairs.syntax").capture(buf, cursor[1] - 1, cursor[2], ctx.line, environments)
    for key, value in pairs(syntax) do
      ctx[key] = value
    end
  elseif enabled and config.treesitter and (ft == "tex" or ft == "plaintex") then
    -- A long future suffix must not bypass raw argument/environment protection.
    ctx.syntax = "unknown"
  end
  return ctx
end

return M

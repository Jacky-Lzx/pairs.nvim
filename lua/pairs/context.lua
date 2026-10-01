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
    multi_rules = require("pairs.config").resolve_multi(config, ft, vim.b[buf].pairs_multi_rules),
    row = cursor[1] - 1,
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
  end
  return ctx
end

return M

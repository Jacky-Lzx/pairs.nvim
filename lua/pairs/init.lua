local M = {}
local config
local enabled = true
local pending_close
local trace = require("pairs.trace")

function M.setup(opts)
  assert(opts == nil or type(opts) == "table", "pairs.nvim: setup expects a table")
  opts = vim.deepcopy(opts or {})
  -- Validate first so an invalid setup does not destroy a working configuration.
  local candidate = require("pairs.config").build(opts)
  local mapping = require("pairs.mapping")
  mapping.detach()
  require("pairs.surround").teardown()
  config, enabled = candidate, true
  pending_close = nil
  mapping.attach(config, M.handle, M.fast_wrap)
  require("pairs.rainbow").setup(config)
  require("pairs.surround").setup(config, function()
    return enabled
  end)
end

local function decide(key, opts)
  if not config then
    return { action = "pass", reason = "not_initialized" }
  end
  local ok, ctx =
    pcall(require("pairs.context").capture, config, enabled, opts and opts.assume_insert, key)
  if not ok then
    return { action = "pass", reason = "context_error", error = tostring(ctx) }
  end
  local pending = opts and opts.pending_close
  local result
  if
    pending
    and ctx.enabled
    and ctx.buf == pending.buf
    and ctx.filetype == pending.filetype
    and ctx.row == pending.row
    and ctx.col == pending.col
    and ctx.line == pending.line
    and vim.api.nvim_buf_get_changedtick(ctx.buf) == pending.tick + 1
    and key == pending.close:sub(-1)
  then
    -- The sole change since a proven math boundary is the literal prefix.
    -- Remove that prefix and move over the original two-byte closer.
    result = { action = "skip", reason = "math_closer", close = pending.close, delete_before = 1 }
  else
    result = require("pairs.engine").decide(ctx, key)
  end
  result.filetype, result.syntax = ctx.filetype, ctx.syntax
  return result, ctx
end

function M.explain(key, opts)
  return (decide(key, opts))
end

-- Composable expression API: nil means this plugin did not handle the key.
function M.expr(key)
  local pending = pending_close
  pending_close = nil
  local result, ctx = decide(key, { pending_close = pending })
  if ctx and result.defer_close then
    pending_close = {
      buf = ctx.buf,
      filetype = ctx.filetype,
      row = ctx.row,
      col = ctx.col + 1,
      line = ctx.line:sub(1, ctx.col) .. "\\" .. ctx.line:sub(ctx.col + 1),
      tick = vim.api.nvim_buf_get_changedtick(ctx.buf),
      close = result.defer_close,
    }
  end
  if trace.active then
    local ok, err = pcall(trace.record, key, result, ctx, config)
    if not ok then
      trace.fail(err)
    end
  end
  return require("pairs.mapping").render(result, ctx)
end

-- Mapping API: returns Neovim keycodes, including the original key on fallback.
function M.handle(key)
  return M.expr(key) or (key == "<FastWrap>" and "" or require("pairs.mapping").keycode(key))
end

-- Expression API: explicit invocation, with nil for the caller's fallback.
function M.fast_wrap()
  return M.expr("<FastWrap>")
end

function M.enable(buf)
  if buf then
    vim.b[buf].pairs_enabled = true
  else
    enabled = true
  end
end

function M.disable(buf)
  if buf then
    vim.b[buf].pairs_enabled = false
  else
    enabled = false
  end
end

function M.toggle(buf)
  if buf then
    vim.b[buf].pairs_enabled = vim.b[buf].pairs_enabled == false
  else
    enabled = not enabled
  end
end

function M.teardown()
  pending_close = nil
  trace.stop()
  require("pairs.rainbow").teardown()
  require("pairs.surround").teardown()
  require("pairs.mapping").detach()
  config = nil
end

function M.dispose()
  M.teardown()
  enabled = true
end

function M.status()
  local mapping = require("pairs.mapping")
  return {
    initialized = config ~= nil,
    enabled = enabled,
    mappings = #mapping.owned,
    conflicts = vim.deepcopy(mapping.conflicts),
    surround = require("pairs.surround").status(),
  }
end

return M

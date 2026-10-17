local M = {}
local config
local enabled = true
local trace = require("pairs.trace")

function M.setup(opts)
  -- Validate first so an invalid setup does not destroy a working configuration.
  local candidate = require("pairs.config").build(opts)
  local mapping = require("pairs.mapping")
  mapping.detach()
  require("pairs.surround").teardown()
  config, enabled = candidate, true
  mapping.attach(config, M.handle, M.fast_wrap)
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
  local result = require("pairs.engine").decide(ctx, key)
  result.filetype, result.syntax = ctx.filetype, ctx.syntax
  return result, ctx
end

function M.explain(key, opts)
  return (decide(key, opts))
end

-- Composable expression API: nil means this plugin did not handle the key.
function M.expr(key)
  local result, ctx = decide(key)
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
  trace.stop()
  require("pairs.surround").teardown()
  require("pairs.mapping").detach()
  config = nil
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

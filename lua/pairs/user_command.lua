-- This module owns only this plugin's commands, without a runtime dependency.
local M, owned = {}, {}
local api = vim.api
local function current(name, buffer)
  local commands = buffer and api.nvim_buf_get_commands(buffer, {}) or api.nvim_get_commands({})
  return commands[name]
end

function M.create(name, callback, opts, buffer)
  if buffer == 0 then
    buffer = api.nvim_get_current_buf()
  end
  local scope = buffer or 0
  owned[scope] = owned[scope] or {}
  local previous, existing = owned[scope][name], current(name, buffer)
  assert(
    not existing or previous and vim.deep_equal(existing, previous),
    "Command already exists: " .. name
  )
  opts = vim.tbl_extend("force", {}, opts or {}, { force = existing ~= nil })
  local action = callback
  if type(callback) == "function" then
    action = function(args)
      return callback(args)
    end
  end
  if buffer then
    api.nvim_buf_create_user_command(buffer, name, action, opts)
  else
    api.nvim_create_user_command(name, action, opts)
  end
  local installed = current(name, buffer)
  owned[scope][name] = installed
  return function()
    if buffer and not api.nvim_buf_is_valid(buffer) then
      return
    end
    if
      owned[scope]
      and owned[scope][name] == installed
      and vim.deep_equal(current(name, buffer), installed)
    then
      M.delete(name, buffer)
    end
  end
end

function M.delete(name, buffer)
  if buffer == 0 then
    buffer = api.nvim_get_current_buf()
  end
  local scope = buffer or 0
  local installed = owned[scope] and owned[scope][name]
  if
    installed
    and (not buffer or api.nvim_buf_is_valid(buffer))
    and vim.deep_equal(current(name, buffer), installed)
  then
    if buffer then
      api.nvim_buf_del_user_command(buffer, name)
    else
      api.nvim_del_user_command(name)
    end
  end
  if owned[scope] then
    owned[scope][name] = nil
  end
end

api.nvim_create_autocmd("BufWipeout", {
  callback = function(event)
    owned[event.buf] = nil
  end,
})
return M

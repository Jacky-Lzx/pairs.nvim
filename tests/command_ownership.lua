vim.opt.rtp:prepend(vim.fn.getcwd())
local registry = require("pairs.user_command")
local function exercise(buffer)
  local function command()
    return (buffer and vim.api.nvim_buf_get_commands(buffer, {}) or vim.api.nvim_get_commands({})).OwnedCommandFixture
  end
  local calls = 0
  local stale = registry.create("OwnedCommandFixture", function(args)
    assert(args.bang and args.args == "two words")
    calls = calls + 1
  end, { nargs = "?", bang = true, desc = "same description" }, buffer)
  vim.cmd("OwnedCommandFixture! two words")
  assert(calls == 1)
  local cleanup = registry.create("OwnedCommandFixture", function()
    calls = calls + 10
  end, { desc = "same description" }, buffer)
  stale()
  vim.cmd("OwnedCommandFixture")
  assert(calls == 11)
  local create = vim.api.nvim_create_user_command
  if buffer then
    create = function(...)
      vim.api.nvim_buf_create_user_command(buffer, ...)
    end
  end
  create("OwnedCommandFixture", function() end, { desc = "same description" })
  local user = command()
  local ok, err = pcall(
    registry.create,
    "OwnedCommandFixture",
    function() end,
    { force = true },
    buffer
  )
  assert(not ok and tostring(err):find("Command already exists", 1, true))
  cleanup()
  registry.delete("OwnedCommandFixture", buffer)
  assert(vim.deep_equal(user, command()))
  if buffer then
    vim.api.nvim_buf_del_user_command(buffer, "OwnedCommandFixture")
  else
    vim.api.nvim_del_user_command("OwnedCommandFixture")
  end
end
exercise(nil)
exercise(vim.api.nvim_get_current_buf())
print("Command ownership: global/local scope, arguments, reload, conflict and stale cleanup passed")

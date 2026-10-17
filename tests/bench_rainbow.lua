local plugin, rainbow = require("pairs"), require("pairs.rainbow")
local uv = vim.uv
local lines = math.min(100000, math.max(1000, tonumber(vim.env.PAIRS_BENCH_LINES) or 50000))
local samples = math.max(20, tonumber(vim.env.PAIRS_BENCH_SAMPLES) or 100)
local function settle()
  assert(
    vim.wait(10000, function()
      return not rainbow.status().pending
    end, 1),
    "background scan timed out"
  )
  local status = rainbow.status()
  assert(not status.reason, status.reason)
  assert(status.valid_lines == vim.api.nvim_buf_line_count(0))
  return status
end
local function stats(values)
  table.sort(values)
  return {
    median = values[math.ceil(#values * 0.5)],
    p95 = values[math.ceil(#values * 0.95)],
    max = values[#values],
  }
end
vim.bo.filetype = "lua"
vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn["repeat"]({ "f(value)" }, lines))
collectgarbage("collect")
local heap = collectgarbage("count")
local started = uv.hrtime()
plugin.setup({
  mappings = { enabled = false },
  rainbow = { debounce_ms = 0, max_brackets = lines * 2 + samples * 2 + 100 },
})
local initial = settle()
local result = {
  neovim = tostring(vim.version()),
  lines = lines,
  samples = samples,
  initial = {
    wall_ms = (uv.hrtime() - started) / 1e6,
    work_ms = initial.work_ms,
    max_slice_ms = initial.max_slice_ms,
    slices = initial.slices,
  },
}
collectgarbage("collect")
result.initial.retained_lua_mb = (collectgarbage("count") - heap) / 1024
local function measure(name, edit, expected)
  local callbacks, updates, work = {}, {}, {}
  for i = 1, samples do
    local before = rainbow.status()
    started = uv.hrtime()
    edit(i)
    callbacks[i] = (uv.hrtime() - started) / 1000
    local after = settle()
    updates[i] = (uv.hrtime() - started) / 1e6
    work[i] = (after.work_ms - before.work_ms) * 1000
    assert(
      after.scanned_lines - before.scanned_lines == expected,
      name .. " scanned an unexpected suffix"
    )
  end
  result[name] = {
    edit_us = stats(callbacks),
    update_wall_ms = stats(updates),
    background_work_us = stats(work),
    scanned_lines = expected,
  }
end
local middle = math.floor(lines / 2)
measure("replace", function(i)
  vim.api.nvim_buf_set_lines(0, middle, middle + 1, false, { "g" .. i .. "(value)" })
end, 1)
measure("insert", function()
  vim.api.nvim_buf_set_lines(0, middle, middle, false, { "g(value)" })
end, 2)
measure("delete", function()
  vim.api.nvim_buf_set_lines(0, middle, middle + 1, false, {})
end, 1)
local before = rainbow.status()
started = uv.hrtime()
for i = 1, 100 do
  vim.api.nvim_buf_set_lines(0, middle, middle + 1, false, { "burst" .. i .. "(value)" })
end
local burst = settle()
assert(burst.scanned_lines - before.scanned_lines == 1)
result.burst = { edits = 100, scanned_lines = 1, wall_ms = (uv.hrtime() - started) / 1e6 }
result.max_slice_ms = burst.max_slice_ms
local json = vim.json.encode(result)
if vim.env.PAIRS_BENCH_OUTPUT then
  vim.fn.writefile({ json }, vim.env.PAIRS_BENCH_OUTPUT)
end
print(json)
plugin.teardown()
vim.cmd("qa!")

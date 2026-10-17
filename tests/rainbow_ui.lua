-- Real UI protocol check: validates rendered cells rather than cached marks.
local uv = vim.uv
local stdin, stdout, stderr = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
local replies, cells, attributes, errors = {}, {}, {}, {}
local next_id, exited = 0, false
local child = assert(uv.spawn(vim.v.progpath, {
  args = { "--embed", "--headless", "-u", "NONE", "-i", "NONE" },
  stdio = { stdin, stdout, stderr },
}, function()
  exited = true
end))
local unpacker = vim.mpack.Unpacker()
stdout:read_start(function(err, data)
  assert(not err, err)
  if not data then
    return
  end
  local pos = 1
  while pos <= #data do
    local message
    message, pos = unpacker(data, pos)
    if message then
      if message[1] == 1 then
        replies[message[2]] = message
      elseif message[1] == 2 and message[2] == "redraw" then
        for _, event in ipairs(message[3]) do
          for i = 2, #event do
            local args = event[i]
            if event[1] == "hl_attr_define" then
              attributes[args[1]] = args[2]
            elseif event[1] == "grid_clear" then
              cells[args[1]] = {}
            elseif event[1] == "grid_line" then
              local grid, row, col, last_hl = args[1], args[2], args[3], 0
              cells[grid] = cells[grid] or {}
              cells[grid][row] = cells[grid][row] or {}
              for _, cell in ipairs(args[4]) do
                last_hl = cell[2] or last_hl
                for _ = 1, cell[3] or 1 do
                  cells[grid][row][col] = { text = cell[1], hl = last_hl }
                  col = col + 1
                end
              end
            end
          end
        end
      end
    end
  end
end)
stderr:read_start(function(_, data)
  if data then
    errors[#errors + 1] = data
  end
end)
local function request(method, args)
  next_id = next_id + 1
  local id = next_id
  stdin:write(vim.mpack.encode({ 0, id, method, args }))
  assert(
    vim.wait(5000, function()
      return replies[id] ~= nil or exited
    end, 1),
    "UI RPC timed out: " .. method
  )
  local reply = assert(replies[id], table.concat(errors))
  assert(reply[3] == vim.NIL, vim.inspect(reply[3]))
  return reply[4]
end
local function lua(code, args)
  return request("nvim_exec_lua", { code, args or {} })
end
local function ready()
  assert(vim.wait(5000, function()
    return not lua("return require('pairs.rainbow').status().pending")
  end, 1))
  request("nvim_command", { "redraw" })
end
local function fg(row, col)
  local cell = assert(cells[1] and cells[1][row] and cells[1][row][col], "missing cell")
  return (attributes[cell.hl] or {}).foreground
end
local function expect(row, col, color)
  assert(
    fg(row, col) == color,
    string.format(
      "cell %d:%d: expected %s, got %s",
      row,
      col,
      tostring(color),
      tostring(fg(row, col))
    )
  )
end
local ok, err = xpcall(function()
  request("nvim_ui_attach", { 80, 24, { rgb = true, ext_linegrid = true } })
  lua(
    [[
    local root = ...
    vim.opt.runtimepath:prepend(root)
    vim.o.swapfile, vim.o.showmode, vim.o.ruler = false, false, false
    vim.o.laststatus, vim.o.showtabline = 0, 0
    vim.bo.filetype = 'lua'
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'({[]})', '{', '  ()', '}', '-- []', '"[]"'})
    require('pairs').setup({rainbow = {debounce_ms = 0}})
  ]],
    { vim.fn.getcwd() }
  )
  ready()
  for col, color in ipairs({ 0xe06c75, 0xe5c07b, 0x61afef, 0x61afef, 0xe5c07b, 0xe06c75 }) do
    expect(0, col - 1, color)
  end
  expect(2, 2, 0xe5c07b)
  assert(fg(4, 3) ~= 0xe06c75 and fg(5, 1) ~= 0xe06c75, "literal brackets were colored")
  lua("vim.api.nvim_buf_set_lines(0, 1, 2, false, {''})")
  ready()
  expect(2, 2, 0xe06c75)
  -- One buffer in two windows, scrolling to cached offscreen lines.
  lua([[
    vim.api.nvim_buf_set_lines(0, -1, -1, false, vim.fn['repeat']({'([])'}, 100))
    vim.cmd('vsplit')
    vim.cmd('normal! Gzt')
  ]])
  ready()
  expect(0, 0, 0xe06c75)
  expect(0, 1, 0xe5c07b)
  lua("require('pairs.rainbow').toggle()")
  request("nvim_command", { "redraw" })
  assert(fg(0, 0) ~= 0xe06c75, "toggle left stale colors")
  lua("require('pairs.rainbow').toggle()")
  ready()
  expect(0, 0, 0xe06c75)
  lua("require('pairs').teardown()")
  request("nvim_command", { "redraw" })
  assert(fg(0, 0) ~= 0xe06c75, "teardown left stale colors")
end, debug.traceback)
child:kill("sigterm")
vim.wait(1000, function()
  return exited
end, 1)
for _, handle in ipairs({ stdin, stdout, stderr, child }) do
  if not handle:is_closing() then
    handle:close()
  end
end
if not ok then
  io.stderr:write(err .. "\n" .. table.concat(errors))
  vim.cmd("cquit 1")
end
print("PASS: rainbow UI colors, edits, split windows, scroll, toggle and teardown")
vim.cmd("qa!")

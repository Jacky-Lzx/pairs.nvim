-- Observe UI updates after a single Space, without sending another key or redraw.
local uv = vim.uv
local stdin, stdout, stderr = uv.new_pipe(false), uv.new_pipe(false), uv.new_pipe(false)
local replies, errors, cells, cursor = {}, {}, {}, {}
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
            if event[1] == "grid_cursor_goto" and args[1] == 1 then
              cursor = { args[2], args[3] }
            elseif event[1] == "grid_clear" and args[1] == 1 then
              cells = {}
            elseif event[1] == "grid_line" and args[1] == 1 and args[2] == 0 then
              local col = args[3]
              for _, cell in ipairs(args[4]) do
                for _ = 1, cell[3] or 1 do
                  cells[col] = cell[1]
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
local function screen_matches(text, col)
  if cursor[1] ~= 0 or cursor[2] ~= col then
    return false
  end
  for i = 1, #text do
    if cells[i - 1] ~= text:sub(i, i) then
      return false
    end
  end
  return true
end
local ok, err = xpcall(function()
  request("nvim_ui_attach", { 80, 24, { rgb = true, ext_linegrid = true } })
  request("nvim_exec_lua", {
    [[
      vim.opt.runtimepath:prepend(...)
      vim.o.swapfile, vim.o.showmode, vim.o.ruler = false, false, false
      vim.o.laststatus, vim.o.showtabline = 0, 0
      -- A prefix ambiguity would wait indefinitely, rather than timing out.
      vim.o.timeout = false
    ]],
    { vim.fn.getcwd() },
  })
  for _, case in ipairs({
    { "ordinary Space", "abcX", 3, "abc X", 4 },
    { "Space at end of line", "abc", 3, "abc ", 4 },
    { "paired padding", "()", 1, "(  )", 2 },
    { "ordinary Space with longer mapping", "abcX", 3, "abc X", 4, true },
    { "paired padding with longer mapping", "()", 1, "(  )", 2, true },
  }) do
    request("nvim_exec_lua", {
      [[
        local case = ...
        local p = require('pairs')
        p.teardown()
        pcall(vim.keymap.del, 'i', '<Space>x')
        if case[6] then vim.keymap.set('i', '<Space>x', 'LONGER') end
        vim.cmd('enew!')
        vim.bo.filetype = 'lua'
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {case[2]})
        vim.api.nvim_win_set_cursor(0, {1, case[3] == #case[2] and case[3] - 1 or case[3]})
        p.setup({pairs = {['('] = {space = true}}})
      ]],
      { case },
    })
    request("nvim_input", { case[3] == #case[2] and "a" or "i" })
    assert(
      vim.wait(1000, function()
        return screen_matches(case[2], case[3])
      end, 1),
      case[1] .. ": initial UI did not settle"
    )
    request("nvim_input", { " " })
    assert(
      vim.wait(1000, function()
        return screen_matches(case[4], case[5])
      end, 1),
      case[1] .. ": Space did not render without another input"
    )
    assert(request("nvim_get_current_line", {}) == case[4], case[1] .. ": wrong buffer text")
    request("nvim_input", { "<Esc>" })
    request("nvim_exec_lua", { "return vim.fn.mode()", {} })
  end
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
print("PASS: Space renders immediately, including padding and longer mapping prefixes")
vim.cmd("qa!")

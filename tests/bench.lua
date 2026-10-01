-- Headless decision timing and real mapped input are deliberately separate.
local plugin = require("pairs")
local uv = vim.uv
local function number(name, default, minimum)
  local value = tonumber(vim.env[name] or default)
  assert(
    value and value % 1 == 0 and value >= minimum,
    name .. " must be an integer >= " .. minimum
  )
  return value
end
local samples = number("PAIRS_BENCH_SAMPLES", 1000, 100)
local large_lines = number("PAIRS_BENCH_LINES", 50000, 1000)
local mapped_samples = number("PAIRS_BENCH_MAPPED_SAMPLES", 20, 5)
local source_paths = vim.fn.glob("lua/**/*.lua", false, true)
table.sort(source_paths)
local source = {}
for _, path in ipairs(source_paths) do
  source[#source + 1] = path .. "\0" .. table.concat(vim.fn.readfile(path, "b"), "\n")
end
local revision = vim.env.PAIRS_BENCH_REVISION
  or vim.trim(vim.fn.system({ "git", "rev-parse", "HEAD" }))
local status = vim.fn.system({ "git", "status", "--porcelain" })
local dirty = vim.NIL
if vim.v.shell_error == 0 then
  dirty = vim.trim(status) ~= ""
end
local report = {
  schema = 1,
  version = vim.version(),
  platform = { os = jit.os, arch = jit.arch, cpu = uv.cpu_info()[1].model },
  samples = samples,
  large_lines = large_lines,
  parser_fixtures = vim.env.PAIRS_TEST_PARSER_ROOT or false,
  revision = revision,
  uncommitted_changes = dirty,
  -- Encode NUL separators: Neovim 0.11 treats a Lua NUL string as a Vim Blob.
  source_sha256 = vim.fn.sha256(vim.json.encode(source)),
  benchmark_sha256 = vim.fn.sha256(table.concat(vim.fn.readfile("tests/bench.lua", "b"), "\n")),
  decisions = {},
  mapped = {},
}
vim.o.virtualedit = "onemore" -- Preserve insertion-at-EOL positions in assume_insert snapshots.
local function stats(times)
  table.sort(times)
  local total = 0
  for _, time in ipairs(times) do
    total = total + time
  end
  return {
    samples = #times,
    median_us = times[math.ceil(#times * 0.5)],
    p95_us = times[math.ceil(#times * 0.95)],
    max_us = times[#times],
    mean_us = total / #times,
  }
end
local function reset(lines, row, col, ft, opts)
  plugin.teardown()
  vim.cmd("enew!")
  vim.bo.filetype = ft
  vim.bo.autoindent = true
  vim.bo.indentexpr = ""
  vim.bo.cindent, vim.bo.smartindent = false, false
  vim.bo.shiftwidth, vim.bo.expandtab = 2, true
  vim.b.pairs_rules, vim.b.pairs_multi_rules, vim.b.pairs_enabled = nil, nil, nil
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { row, col })
  assert(vim.api.nvim_win_get_cursor(0)[2] == col, "benchmark insertion cursor was clamped")
  plugin.setup(opts)
end
local function profile(key, expected)
  local modules = {
    config = { "resolve", "resolve_multi", "capture" },
    context = { "capture" },
    lex = { "scan" },
    syntax = { "capture" },
  }
  local originals, stages = {}, {}
  for module, names in pairs(modules) do
    local target = require("pairs." .. module)
    for _, name in ipairs(names) do
      if target[name] then
        local original = target[name]
        local id = module .. "." .. name
        stages[id] = { calls = 0, inclusive_us = 0 }
        originals[#originals + 1] = { target, name, original }
        target[name] = function(...)
          local start = uv.hrtime()
          local result = original(...)
          local stage = stages[id]
          stage.calls = stage.calls + 1
          stage.inclusive_us = stage.inclusive_us + (uv.hrtime() - start) / 1000
          return result
        end
      end
    end
  end
  local ok, err = pcall(function()
    for _ = 1, 100 do
      assert(plugin.explain(key, { assume_insert = true }).action == expected)
    end
  end)
  for _, original in ipairs(originals) do
    original[1][original[2]] = original[3]
  end
  assert(ok, err)
  for _, stage in pairs(stages) do
    stage.mean_us_per_decision = stage.inclusive_us / 100
  end
  return stages
end
local function decision(case)
  local lines = case.lines or { case.line or "" }
  reset(lines, case.row or 1, case.col or 0, case.ft or "lua", case.opts or {})
  if case.buffer then
    vim.b.pairs_rules = case.buffer
  end
  local cleanup = case.prepare and case.prepare()
  local function check(result)
    if result.reason == "context_error" then
      error(case.name .. ": " .. tostring(result.error))
    end
    if case.actions then
      if
        not case.actions[result.action]
        or (result.action == "pass" and result.reason ~= "syntax_pending")
      then
        error(case.name .. ": unexpected " .. vim.inspect(result))
      end
    else
      if result.action ~= case.action then
        error(case.name .. ": unexpected " .. vim.inspect(result))
      end
    end
  end
  if not case.before then
    for _ = 1, 100 do
      check(plugin.explain(case.key, { assume_insert = true }))
    end
  end
  collectgarbage("collect")
  local times, actions, reasons = {}, {}, {}
  for i = 1, case.samples or samples do
    if case.before then
      case.before(i)
    end
    local start = uv.hrtime()
    local result = plugin.explain(case.key, { assume_insert = true })
    times[i] = (uv.hrtime() - start) / 1000
    check(result)
    actions[result.action] = (actions[result.action] or 0) + 1
    reasons[result.reason] = (reasons[result.reason] or 0) + 1
    if case.after then
      case.after()
    end
  end
  local result = stats(times)
  result.name, result.key = case.name, case.key
  result.actions, result.reasons = actions, reasons
  result.buffer_lines, result.line_bytes = #lines, #vim.api.nvim_get_current_line()
  if not case.before then
    -- A separate run estimates Lua heap growth, not retained memory or C allocations.
    collectgarbage("collect")
    collectgarbage("stop")
    local start = collectgarbage("count")
    local last
    local ok, err = pcall(function()
      for _ = 1, 100 do
        last = plugin.explain(case.key, { assume_insert = true })
      end
    end)
    result.lua_heap_bytes_per_decision = (collectgarbage("count") - start) * 1024 / 100
    collectgarbage("restart")
    assert(ok, err)
    check(last)
    if vim.env.PAIRS_BENCH_PROFILE == "1" then
      result.profile = profile(case.key, case.action)
    end
  end
  if cleanup then
    cleanup()
  end
  report.decisions[#report.decisions + 1] = result
end
local cases = {
  { name = "quote-open", key = '"', action = "pair" },
  { name = "bracket-open", key = "(", action = "pair" },
  { name = "closer-skip", line = "()", col = 1, key = ")", action = "skip" },
  { name = "empty-backspace", line = "()", col = 1, key = "<BS>", action = "delete" },
  { name = "empty-enter", line = "{}", col = 1, key = "<CR>", action = "newline" },
  { name = "buffer-override", key = '"', action = "pass", buffer = { ['"'] = { open = false } } },
  {
    name = "long-prefix-2k",
    line = string.rep("x ", 1000),
    col = 2000,
    key = "(",
    action = "pair",
  },
  {
    name = "long-empty-backspace",
    line = string.rep("x ", 1000) .. "()",
    col = 2001,
    key = "<BS>",
    action = "delete",
  },
  {
    name = "over-scan-limit-8k",
    line = string.rep("x", 8192),
    col = 8192,
    key = "(",
    action = "pass",
  },
}
local large = {}
for i = 1, large_lines do
  large[i] = "value = 1"
end
local middle = math.floor(large_lines / 2)
large[middle] = ""
cases[#cases + 1] =
  { name = "large-lexer", lines = large, row = middle, key = '"', action = "pair" }
if vim.env.PAIRS_TEST_PARSER_ROOT then
  local function ready(ft)
    return function()
      local parser = vim.treesitter.get_parser(0, ft)
      parser:parse(true) -- Fixture preparation is outside every timer.
    end
  end
  cases[#cases + 1] = {
    name = "python-ready",
    line = "value = ",
    col = 8,
    ft = "python",
    opts = { treesitter = true },
    prepare = ready("python"),
    key = '"',
    action = "pair",
  }
  cases[#cases + 1] = {
    name = "python-multiline-string",
    lines = { 'value = """', "body", '"""' },
    row = 2,
    ft = "python",
    opts = { treesitter = true },
    prepare = ready("python"),
    key = "(",
    action = "pass",
  }
  cases[#cases + 1] = {
    name = "rust-block-comment",
    lines = { "/*", "body", "*/" },
    row = 2,
    ft = "rust",
    opts = { treesitter = true },
    prepare = ready("rust"),
    key = '"',
    action = "pass",
  }
  cases[#cases + 1] = {
    name = "javascript-template-text",
    line = "`body`",
    col = 2,
    ft = "javascript",
    opts = { treesitter = true },
    prepare = ready("javascript"),
    key = "(",
    action = "pass",
  }
  cases[#cases + 1] = {
    name = "javascript-interpolation",
    line = "`${ }`",
    col = 3,
    ft = "javascript",
    opts = { treesitter = true },
    prepare = ready("javascript"),
    key = "(",
    action = "pair",
  }
  cases[#cases + 1] = {
    name = "large-python-ready",
    lines = large,
    row = middle,
    ft = "python",
    opts = { treesitter = true },
    prepare = ready("python"),
    key = '"',
    action = "pair",
  }
  local string_lines = vim.deepcopy(large)
  string_lines[1], string_lines[#string_lines] = 'value = """', '"""'
  cases[#cases + 1] = {
    name = "large-python-string",
    lines = string_lines,
    row = middle,
    ft = "python",
    opts = { treesitter = true },
    prepare = ready("python"),
    key = "(",
    action = "pass",
  }
  cases[#cases + 1] = {
    name = "python-pending-dispatch-stub",
    line = "value = ",
    col = 8,
    ft = "python",
    opts = { treesitter = true },
    key = '"',
    action = "pass",
    prepare = function()
      local parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "value = " })
      local original = parser.parse
      parser.parse = function(_, range, callback)
        assert(type(range) == "table" and type(callback) == "function", "forced synchronous parse")
        return nil
      end
      return function()
        parser.parse = original
      end
    end,
  }
  local parser
  cases[#cases + 1] = {
    name = "large-python-after-edit",
    lines = large,
    row = middle,
    ft = "python",
    opts = { treesitter = true },
    key = '"',
    actions = { pair = true, pass = true },
    samples = math.min(samples, 50),
    prepare = function()
      parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
    end,
    before = function(i)
      local line = i % 2 == 0 and "value = " or "value  = "
      vim.api.nvim_buf_set_lines(0, middle - 1, middle, false, { line })
      vim.api.nvim_win_set_cursor(0, { middle, #line })
    end,
    after = function()
      assert(
        vim.wait(2000, function()
          return parser:is_valid(false)
        end, 1),
        "asynchronous parser did not settle"
      )
    end,
  }
end
for _, case in ipairs(cases) do
  decision(case)
end
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "xt", false)
end
local function mapped(name, keys, expected, native, owned_keys)
  reset({ "" }, 1, 0, "lua", {})
  if native then
    plugin.teardown()
  end
  for _ = 1, 3 do
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    feed("i" .. keys .. "<Esc>")
    assert(
      vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected),
      name .. ": wrong warmup text"
    )
  end
  collectgarbage("collect")
  local times = {}
  for i = 1, mapped_samples do
    vim.bo.undolevels = -1
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.bo.undolevels = 1000
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local start = uv.hrtime()
    feed("i" .. keys .. "<Esc>")
    times[i] = (uv.hrtime() - start) / 1000
    assert(
      vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected),
      name .. ": wrong mapped text"
    )
    if i == 1 then
      feed("u")
      assert(
        vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" }),
        name .. ": fragmented undo"
      )
      feed("<C-r>")
      assert(
        vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected),
        name .. ": broken redo"
      )
      feed("u.")
      assert(
        vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected),
        name .. ": broken dot repeat"
      )
    end
  end
  local result = stats(times)
  result.name, result.owned_keys_per_batch = name, owned_keys
  report.mapped[#report.mapped + 1] = result
end
local stream = string.rep('("x")[y]', 50)
mapped("native-balanced-batch", stream, { stream }, true, 0)
mapped("mapped-balanced-batch", stream, { stream }, false, 300)
mapped("mapped-backspace-batch", string.rep('(<BS>[<BS>{<BS>"<BS>', 50) .. "z", { "z" }, false, 400)
mapped("mapped-enter", "{<CR>x", { "{", "  x", "}" }, false, 2)
plugin.teardown()
print(
  "pairs.nvim benchmark: " .. tostring(vim.version()) .. ", " .. large_lines .. " large-file lines"
)
print("Decision latency (microseconds; normal GC, prepared buffer, assume_insert API):")
print(string.format("%-32s %9s %9s %9s %12s", "scenario", "median", "p95", "max", "Lua B/call"))
for _, row in ipairs(report.decisions) do
  print(
    string.format(
      "%-32s %9.2f %9.2f %9.2f %12s",
      row.name,
      row.median_us,
      row.p95_us,
      row.max_us,
      row.lua_heap_bytes_per_decision and string.format("%.0f", row.lua_heap_bytes_per_decision)
        or "-"
    )
  )
end
print("Mapped batch latency (microseconds; feedkeys, edits, no UI rendering):")
for _, row in ipairs(report.mapped) do
  print(string.format("%-32s %9.2f %9.2f %9.2f", row.name, row.median_us, row.p95_us, row.max_us))
end
if vim.env.PAIRS_BENCH_OUTPUT then
  assert(
    vim.fn.writefile({ vim.json.encode(report) }, vim.env.PAIRS_BENCH_OUTPUT) == 0,
    "cannot write benchmark JSON"
  )
end
print("PASS: benchmark actions, mapped text, undo/redo/dot")
vim.cmd("qa!")

return function(h)
  local test, eq, seed, plugin = h.test, h.eq, h.seed, h.plugin
  local rainbow = require("pairs.rainbow")
  local scanner = require("pairs.rainbow_scan")
  local limits = { max_depth = 256 }
  local function lex(lines, ft)
    local state, result = scanner.initial(), {}
    for _, text in ipairs(lines) do
      local entry = assert(scanner.line(text, state, ft or "lua", limits))
      result[#result + 1], state = entry.marks, entry.after
    end
    return result, state
  end

  test("rainbow: mixed nesting, matched colors, UTF-8 byte columns", function()
    eq(lex({ "你({[]})" }), { { 3, 1, 4, 2, 5, 3, 6, 3, 7, 2, 8, 1 } })
  end)
  test("rainbow: cross-line depth and mismatched closers", function()
    eq(lex({ "{", "([)]", ")}" }), { { 0, 1 }, { 0, 2, 1, 3, 3, 3 }, { 0, 2, 1, 1 } })
  end)
  test("rainbow: quotes and escaped delimiters", function()
    eq(lex({ [[("\"[not brackets]") -- {ignored}]], [[\(real)]] }), {
      { 0, 1, 19, 1 },
      {},
    })
  end)
  test("rainbow: Lua multiline comments and long strings", function()
    eq(lex({ "{ --[=[ (", "[ ignored ]", "]=] [=[ ignored {", "]=] ()", "}" }), {
      { 0, 1 },
      {},
      {},
      { 4, 2, 5, 2 },
      { 0, 1 },
    })
  end)
  test("rainbow: Python triple strings and comments", function()
    eq(lex({ 'f("""[', '{""", []) # ignored (', ")" }, "python"), {
      { 1, 1 },
      { 6, 2, 7, 2, 8, 1 },
      {},
    })
  end)
  test("rainbow: C block comments close mid-line", function()
    eq(lex({ "{ /* [", "*/ () // ]", "}" }, "c"), {
      { 0, 1 },
      { 3, 2, 4, 2 },
      { 0, 1 },
    })
  end)
  test("rainbow: Rust lifetimes, characters, raw strings and nested comments", function()
    eq(
      lex(
        { [[fn a<'a>() {]], [[let x = '('; let y = r#"[\"]"#;]], "/* /* } */", " */ []", "}" },
        "rust"
      ),
      {
        { 8, 1, 9, 1, 11, 1 },
        {},
        {},
        { 4, 2, 5, 2 },
        { 0, 1 },
      }
    )
  end)
  test("rainbow: JavaScript nested template interpolation", function()
    eq(lex({ "`text [ ${fn({x: `nest ${[]}`})} ]`" }, "javascript"), {
      { 9, 1, 12, 2, 13, 3, 24, 4, 25, 5, 26, 5, 27, 4, 29, 3, 30, 2, 31, 1 },
    })
  end)
  test("rainbow: Go multiline raw strings", function()
    eq(lex({ "f(`(", "[ ]`, [])" }, "go"), { { 1, 1 }, { 6, 2, 7, 2, 8, 1 } })
  end)
  test("rainbow: TeX comments, escaped braces and prose apostrophes", function()
    eq(lex({ [[don't {a \{ b} % (ignored)]], "([])" }, "tex"), {
      { 6, 1, 13, 1 },
      { 0, 1, 1, 2, 2, 2, 3, 1 },
    })
  end)
  test("rainbow: unfinished ordinary quotes recover, explicit continuation persists", function()
    eq(lex({ '"unterminated [', "()" }, "python"), { {}, { 0, 1, 1, 1 } })
    eq(lex({ '"continued \\', '[not brackets]" ()' }, "python"), { {}, { 16, 1, 17, 1 } })
  end)

  local provider
  local original_provider = vim.api.nvim_set_decoration_provider
  local function setup(lines, ft, opts)
    seed("│", ft)
    vim.b.pairs_rainbow = nil
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_set_decoration_provider = function(ns, callbacks)
      if callbacks.on_line then
        provider = callbacks
      end
      original_provider(ns, callbacks)
    end
    local ok, err = pcall(plugin.setup, opts or { rainbow = { debounce_ms = 0 } })
    vim.api.nvim_set_decoration_provider = original_provider
    assert(ok, err)
  end
  local function settle(reason)
    assert(
      vim.wait(5000, function()
        return not rainbow.status().pending
      end, 1),
      "rainbow did not settle"
    )
    local status = rainbow.status()
    eq(status.reason, reason)
    if not reason and status.enabled then
      eq(status.valid_lines, vim.api.nvim_buf_line_count(0))
    end
    return status
  end
  local function paint(row)
    local result = {}
    provider.on_win(nil, 0, vim.api.nvim_get_current_buf())
    local original_mark = vim.api.nvim_buf_set_extmark
    vim.api.nvim_buf_set_extmark = function(_, _, line, col, opts)
      assert(opts.ephemeral and opts.end_col == col + 1)
      result[#result + 1] = { line, col, opts.hl_group }
    end
    local ok, err = pcall(provider.on_line, nil, 0, vim.api.nvim_get_current_buf(), row)
    vim.api.nvim_buf_set_extmark = original_mark
    assert(ok, err)
    return result
  end

  test("rainbow: visible provider cycles groups and creates no persistent marks", function()
    setup(
      { "({[]})" },
      "lua",
      { rainbow = { debounce_ms = 0, highlights = { "Error", "String" } } }
    )
    settle()
    eq(paint(0), {
      { 0, 0, "Error" },
      { 0, 1, "String" },
      { 0, 2, "Error" },
      { 0, 3, "Error" },
      { 0, 4, "String" },
      { 0, 5, "Error" },
    })
    eq(
      vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_get_namespaces()["pairs.rainbow"], 0, -1, {}),
      {}
    )
  end)
  test("rainbow: dense redraws respect the per-window decoration cap", function()
    setup({ "()[]{}" }, "lua", { rainbow = { debounce_ms = 0, max_visible_brackets = 3 } })
    settle()
    eq(#paint(0), 3)
  end)
  test("rainbow: unfinished deeply nested comments use one forward scan", function()
    local text = string.rep("/*", 4000)
    local entry = assert(scanner.line(text, scanner.initial(), "rust", limits))
    eq(entry.after.nesting, 4000)
    eq(entry.marks, {})
  end)
  test("rainbow: same-line edit converges after one line in a 50000-line buffer", function()
    setup(vim.fn["repeat"]({ "f()" }, 50000), "lua")
    local before = settle()
    eq(before.scanned_lines, 50000)
    assert(before.slices > 1)
    vim.api.nvim_buf_set_lines(0, 25000, 25001, false, { "g()" })
    eq(rainbow.status().scanned_lines, before.scanned_lines) -- no scan in on_lines
    eq(paint(25000), {}) -- invalid suffix is never painted
    eq(settle().scanned_lines - before.scanned_lines, 1)
    eq(#paint(25000), 2)
    vim.api.nvim_buf_set_lines(0, 1, 2, false, { "h()" })
    local second = settle()
    eq(second.scanned_lines - before.scanned_lines, 2) -- old dirty_end must reset
    vim.api.nvim_buf_set_lines(0, 25000, 25000, false, { "" })
    local inserted = settle()
    eq(inserted.scanned_lines - second.scanned_lines, 2)
    vim.api.nvim_buf_set_lines(0, 25000, 25001, false, {})
    eq(settle().scanned_lines - inserted.scanned_lines, 1)
  end)
  test("rainbow: randomized batched line edits agree with a fresh full scan", function()
    setup(vim.fn["repeat"]({ "()" }, 30), "lua")
    settle()
    local rand = 42
    local function random(n)
      rand = (rand * 48271) % 2147483647
      return rand % n
    end
    local choices = { "{", "}", "([])", "--[=[", "]=]", "[=[", "'[]'", "", "[", "]" }
    for _ = 1, 100 do
      for _ = 1, random(5) + 1 do
        local count = vim.api.nvim_buf_line_count(0)
        local first = random(count + 1)
        local last = math.min(count, first + random(3))
        local replacement = {}
        for _ = 1, random(3) do
          replacement[#replacement + 1] = choices[random(#choices) + 1]
        end
        vim.api.nvim_buf_set_lines(0, first, last, false, replacement)
      end
      local status = settle()
      local all = lex(vim.api.nvim_buf_get_lines(0, 0, -1, false))
      local total = 0
      for row, marks in ipairs(all) do
        local expected = {}
        for i = 1, #marks, 2 do
          local groups = require("pairs.config").defaults.rainbow.highlights
          expected[#expected + 1] = { row - 1, marks[i], groups[(marks[i + 1] - 1) % #groups + 1] }
        end
        total = total + #marks / 2
        eq(paint(row - 1), expected)
      end
      eq(status.brackets, total)
    end
  end)
  test("rainbow: edit bursts and large replacements discard obsolete caches", function()
    setup(vim.fn["repeat"]({ "()" }, 1000), "lua")
    settle()
    for _ = 1, 20 do
      vim.api.nvim_buf_set_lines(0, 0, 0, false, { "[]" })
    end
    eq(settle().brackets, 2040)
    vim.api.nvim_buf_set_lines(0, 1, 800, false, { "{}" })
    eq(settle().brackets, 444)
  end)
  test("rainbow: edits propagate depth then converge", function()
    setup({ "{", "[", "]", "}", "()" }, "lua")
    local before = settle()
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "" })
    eq(settle().scanned_lines - before.scanned_lines, 4)
    eq(paint(1), { { 1, 0, "PairsRainbowRed" } })
    eq(paint(3), {})
  end)
  test("rainbow: batched edits must pass the last changed line", function()
    setup({ "()", "[]", "{}", "()" }, "lua")
    local before = settle()
    vim.api.nvim_buf_set_lines(0, 2, 3, false, { "[{}]" })
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "[()]" })
    eq(settle().scanned_lines - before.scanned_lines, 3)
    eq(#paint(2), 4)
  end)
  test("rainbow: insert/delete lines and purge old suffix", function()
    setup(vim.fn["repeat"]({ "()" }, 500), "lua")
    settle()
    vim.api.nvim_buf_set_lines(0, 0, 0, false, { "{" })
    settle()
    eq(paint(1), { { 1, 0, "PairsRainbowYellow" }, { 1, 1, "PairsRainbowYellow" } })
    vim.api.nvim_buf_set_lines(0, 0, 401, false, {})
    local status = settle()
    eq(status.brackets, 200)
    eq(paint(0), { { 0, 0, "PairsRainbowRed" }, { 0, 1, "PairsRainbowRed" } })
    -- Appending after tail cleanup must use the retained final state.
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "[]" })
    eq(settle().brackets, 202)
  end)
  test("rainbow: comment edits invalidate downstream lexical state", function()
    setup({ "/*", "[]", "*/", "()" }, "c")
    settle()
    eq(paint(1), {})
    vim.api.nvim_buf_set_lines(0, 0, 1, false, { "" })
    settle()
    eq(#paint(1), 2)
  end)
  test("rainbow: rapid edits coalesce before background scanning", function()
    setup({ "()", "[]" }, "lua", { rainbow = { debounce_ms = 20 } })
    local before = settle()
    for i = 1, 100 do
      vim.api.nvim_buf_set_lines(0, 0, 1, false, { "f" .. i .. "()" })
    end
    eq(rainbow.status().scanned_lines, before.scanned_lines)
    eq(settle().scanned_lines - before.scanned_lines, 1)
    eq(paint(0)[1][2], 4)
  end)
  test("rainbow: filetype changes reset lexical policy", function()
    setup({ "# ()" }, "python")
    settle()
    eq(paint(0), {})
    vim.bo.filetype = "lua"
    settle()
    eq(#paint(0), 2)
  end)
  test("rainbow: buffer toggle, re-setup and disabled filetypes", function()
    setup({ "([])" }, "lua")
    settle()
    eq(rainbow.toggle(), false)
    eq(rainbow.status().enabled, false)
    eq(provider.on_win(nil, 0, vim.api.nvim_get_current_buf()), false)
    eq(rainbow.toggle(), true)
    settle()
    plugin.setup({ rainbow = { enabled = false } })
    eq(rainbow.status().enabled, false)
    plugin.setup({ disabled_filetypes = { "lua" } })
    eq(rainbow.status().enabled, false)
    plugin.setup({ filetypes = { lua = { enabled = false } } })
    eq(rainbow.status().enabled, false)
    plugin.setup({ rainbow = { debounce_ms = 0 } })
    eq(settle().brackets, 4)
  end)
  test("rainbow: hidden buffers pause and resume", function()
    setup({ "()" }, "lua")
    settle()
    local buf = vim.api.nvim_get_current_buf()
    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "[]" })
    vim.wait(50)
    eq(rainbow.status(buf).pending, false)
    vim.api.nvim_set_current_buf(buf)
    eq(settle().brackets, 2)
  end)
  test("rainbow: teardown cancels pending work and colorscheme preserves overrides", function()
    setup({ "()" }, "lua", { rainbow = { debounce_ms = 20 } })
    vim.api.nvim_set_hl(0, "PairsRainbowRed", { fg = "#123456" })
    vim.api.nvim_exec_autocmds("ColorScheme", {})
    eq(vim.api.nvim_get_hl(0, { name = "PairsRainbowRed" }).fg, 0x123456)
    vim.api.nvim_set_hl(0, "PairsRainbowRed", {})
    plugin.teardown()
    vim.wait(30)
    eq(rainbow.status().enabled, false)
    eq(rainbow.status().valid_lines, 0)
  end)
  for _, case in ipairs({
    { "max_lines", 1, { "()", "[]" }, "line_count_limit" },
    { "max_bytes", 2, { "()" }, "byte_limit" },
    { "max_line_bytes", 3, { "(())" }, "line_length_limit" },
    { "max_depth", 1, { "(())" }, "depth_limit" },
    { "max_brackets", 3, { "()()" }, "bracket_limit" },
  }) do
    test("rainbow: " .. case[1] .. " disables safely and recovers after shrinking", function()
      setup(case[3], "lua", { rainbow = { debounce_ms = 0, [case[1]] = case[2] } })
      eq(settle(case[4]).brackets, 0)
      eq(paint(0), {})
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
      eq(settle().brackets, 0)
    end)
  end
  test("rainbow: invalid setup preserves the working provider", function()
    setup({ "()" }, "lua")
    settle()
    for _, opts in ipairs({
      { rainbow = false },
      { rainbow = { enabled = "yes" } },
      { rainbow = { max_lines = 0 } },
      { rainbow = { budget_ms = math.huge } },
      { rainbow = { highlights = {} } },
      { rainbow = { highlights = { false } } },
      { rainbow = { priority = 65536 } },
    }) do
      eq(pcall(plugin.setup, opts), false)
      eq(#paint(0), 2)
    end
  end)
end

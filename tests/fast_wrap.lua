return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = { mappings = { fast_wrap = "<F8>" } }
  for _, bracket in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
    local open, close = unpack(bracket)
    test("fast wrap: " .. open .. close .. " wraps a same-line identifier", function()
      input(open .. "│" .. close .. "value", "<F8>", open .. "value" .. close .. "│", opts)
      input(
        "中文" .. open .. "│" .. close .. "item_2 tail",
        "<F8>x",
        "中文" .. open .. "item_2" .. close .. "x│ tail",
        opts
      )
    end)
  end
  for _, case in ipairs({
    { "underscore identifier", "(│)_item42", "(_item42)│" },
    { "comma boundary", "fn((│)value, next)", "fn((value)│, next)" },
    { "closing bracket boundary", "[(│)item]", "[(item)│]" },
    { "semicolon boundary", "(│)value;", "(value)│;" },
    { "tab boundary", "(│)value\ttail", "(value)│\ttail" },
    { "line boundary", "(│)value\ntail", "(value)│\ntail" },
    { "repeated invocation is inert", "(│)value", "(value)│" },
  }) do
    test("fast wrap: " .. case[1], function()
      input(case[2], "<F8><F8>", case[3], opts)
    end)
  end
  for _, case in ipairs({
    { "nonempty pair", "(x│)value" },
    { "padding", "( │ )value" },
    { "space before target", "(│) value" },
    { "no target", "(│)" },
    { "numeric target", "(│)42" },
    { "Unicode target", "(│)中文" },
    { "Unicode identifier suffix", "(│)café" },
    { "incomplete member access", "(│)obj." },
    { "function call", "(│)fn()" },
    { "indexing", "(│)items[0]" },
    { "operator without a boundary", "(│)value+other" },
    { "quoted target", '(│)"value"' },
    { "mismatched delimiters", "(│]value" },
    { "malformed prefix", ") (│)value" },
    { "escaped opener", "\\(│)value" },
    { "quoted context", '"(│)value"' },
    { "comment context", "-- (│)value" },
    { "quote pair", '"│"value' },
  }) do
    test("fast wrap: " .. case[1] .. " is unchanged", function()
      input(case[2], "<F8>", case[2], opts)
    end)
  end
  test("fast wrap: opt-in shortcut is absent by default", function()
    seed("(│)value")
    plugin.setup()
    eq(vim.fn.maparg("<F8>", "i"), "")
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "wrap")
    eq(vim.fn.mode(), "n")
    eq(plugin.fast_wrap(), nil)
    eq(plugin.handle("<FastWrap>"), "")
    eq(vim.api.nvim_get_current_line(), "()value")
  end)
  test("fast wrap: Meta shortcut flushes preceding typed text", function()
    input("│value", "()<C-g>U<Left><M-e>", "(value)│", { mappings = { fast_wrap = "<M-e>" } })
  end)
  test("fast wrap: wrapping an existing pair retains undo, redo and dot", function()
    input("(│)value", "<F8>x", "(value)x│", opts)
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "()value" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "(value)x" })
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "(value)x" })
  end)
  test("fast wrap: newly typed nested pair and wrap share one undo block", function()
    input("│value", "[()<C-g>U<Left><F8>]x", "[(value)]x│", opts)
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "value" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "[(value)]x" })
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "[(value)]x" })
  end)
  test("fast wrap: rule policy is independent of open, skip and delete", function()
    input(
      "(│)value",
      "<F8>",
      "(value)│",
      vim.tbl_deep_extend(
        "force",
        opts,
        { pairs = { ["("] = { open = false, skip = false, delete = false } } }
      )
    )
    input(
      "(│)value",
      "<F8>",
      "(│)value",
      vim.tbl_deep_extend("force", opts, { pairs = { ["("] = { wrap = false } } })
    )
    input(
      "(│)value",
      "<F8>",
      "(│)value",
      vim.tbl_deep_extend("force", opts, { pairs = { ["("] = false } })
    )
    input(
      "<│>value",
      "<F8>",
      "<│>value",
      vim.tbl_deep_extend("force", opts, { pairs = { ["<"] = { close = ">" } } })
    )
  end)
  test("fast wrap: disabled engine, filetype and buffer remain inert", function()
    input(
      "(│)value",
      "<F8>",
      "(│)value",
      vim.tbl_deep_extend("force", opts, { enabled = false })
    )
    input("(│)value", "<F8>", "(│)value", opts, "TelescopePrompt")
    local entry = seed("(│)value")
    plugin.setup(opts)
    vim.b.pairs_enabled = false
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(│)value")
  end)
  test("fast wrap: legacy custom closer overrides disable inherited wrapping", function()
    local ft = vim.tbl_deep_extend(
      "force",
      opts,
      { filetypes = { python = { pairs = { ["("] = { close = ">" } } } } }
    )
    input("(│>value", "<F8>", "(│>value", ft, "python")
    local entry = seed("(│>value")
    plugin.setup(opts)
    vim.b.pairs_rules = { ["("] = { close = ">" } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).reason, "wrap_disabled")
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(│>value")
    local config = require("pairs.config")
    local candidate = config.build(ft)
    eq(config.resolve(candidate, "python")["("].wrap, false)
    eq(config.capture(candidate, "lua", { ["("] = { close = ">" } }).rules["("].wrap, false)
  end)
  test("fast wrap: filetype and buffer policy remain live", function()
    local ft = vim.tbl_deep_extend(
      "force",
      opts,
      { filetypes = { python = { pairs = { ["("] = { wrap = false } } } } }
    )
    input("(│)value", "<F8>", "(│)value", ft, "python")
    local entry = seed("(│)value", "python")
    plugin.setup(ft)
    vim.b.pairs_rules = { ["("] = { wrap = true } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "wrap")
    vim.b.pairs_rules = { ["("] = { wrap = false } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).reason, "wrap_disabled")
    vim.b.pairs_rules = { ["("] = { wrap = true } }
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(value)│")
  end)
  test("fast wrap: forward identifier and prefix share the scan budget", function()
    input(
      "(│)value",
      "<F8>",
      "(│)value",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 6 })
    )
    input(
      "(│)value",
      "<F8>",
      "(value)│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 7 })
    )
    input(
      "xx (│)value",
      "<F8>",
      "xx (│)value",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 9 })
    )
    input(
      "(│)value;" .. string.rep("x", 10000),
      "<F8>",
      "(value)│;" .. string.rep("x", 10000),
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 7 })
    )
  end)
  test("fast wrap: prefix is scanned once with no retained state", function()
    seed("(│)value")
    plugin.setup(opts)
    local lex = require("pairs.lex")
    local original, calls = lex.scan, 0
    lex.scan = function(...)
      calls = calls + 1
      return original(...)
    end
    local ok, err = pcall(function()
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).move, 5)
      eq(calls, 1)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "()item" })
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).move, 4)
      eq(calls, 2)
    end)
    lex.scan = original
    assert(ok, err)
  end)
  test("fast wrap: invalid shortcut and policy preserve prior setup", function()
    seed("(│)value")
    plugin.setup(opts)
    for _, invalid in ipairs({
      { mappings = { fast_wrap = true } },
      { mappings = { fast_wrap = "" } },
      { mappings = { fast_wrap = "x" } },
      { mappings = { fast_wrap = "<F8><F9>" } },
      { mappings = { fast_wrap = "<UnknownKey>" } },
      { mappings = { fast_wrap = "<Tab>" } },
      { mappings = { fast_wrap = "<C-i>" } },
      { mappings = { fast_wrap = "<C-m>" } },
      { mappings = { fast_wrap = "<C-h>" } },
      { mappings = { fast_wrap = "<Esc>" } },
      { mappings = { fast_wrap = "<Ignore>" } },
      { mappings = { fast_wrap = "<Char-40>" } },
      { mappings = { fast_wrap = "<S-e>" } },
      { mappings = { fast_wrap = "<Cmd>" } },
      { pairs = { ["("] = { wrap = 1 } } },
      { pairs = { ['"'] = { wrap = true } } },
      { pairs = { ["<"] = { close = ">", wrap = true } } },
    }) do
      eq(pcall(plugin.setup, invalid), false)
      eq(vim.fn.maparg("<F8>", "i", false, true).desc, "pairs.nvim <F8>")
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "wrap")
    end
    vim.b.pairs_rules = { ["("] = { wrap = "yes" } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).reason, "context_error")
    vim.b.pairs_rules = nil
  end)
  test("fast wrap: existing global shortcut owner is preserved", function()
    local entry = seed("(│)value")
    vim.keymap.set("i", "<F8>", "_")
    plugin.setup(opts)
    local ok, err = pcall(function()
      eq(plugin.status().conflicts, { "<F8>" })
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "(_│)value")
      plugin.teardown()
      eq(vim.fn.maparg("<F8>", "i", false, true).rhs, "_")
    end)
    vim.keymap.del("i", "<F8>")
    assert(ok, err)
  end)
  test("fast wrap: buffer shortcut owner wins", function()
    local entry = seed("(│)value")
    vim.keymap.set("i", "<F8>", "_", { buffer = true })
    plugin.setup(opts)
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(_│)value")
  end)
  test("fast wrap: disabling owned mappings leaves composable API available", function()
    local entry = seed("(│)value")
    plugin.setup(vim.tbl_deep_extend("force", opts, { mappings = { enabled = false } }))
    eq(vim.fn.maparg("<F8>", "i"), "")
    vim.keymap.set("i", "<F9>", "<Ignore><Plug>(pairs-test-wrap)")
    vim.keymap.set("i", "<Plug>(pairs-test-wrap)", function()
      return plugin.fast_wrap() or "_"
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      feed(entry .. "<F9><F9><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "(value)_│")
    end)
    vim.keymap.del("i", "<F9>")
    vim.keymap.del("i", "<Plug>(pairs-test-wrap)")
    assert(ok, err)
  end)
  test("fast wrap: re-setup and teardown clean up only owned shortcuts", function()
    seed("│")
    plugin.setup(opts)
    local owned
    for _, mapping in ipairs(require("pairs.mapping").owned) do
      if mapping.lhs == "<F8>" then
        owned = mapping
      end
    end
    assert(owned)
    plugin.setup({ mappings = { fast_wrap = "<F9>" } })
    eq(vim.fn.maparg("<F8>", "i"), "")
    eq(vim.fn.maparg(owned.plug, "i"), "")
    vim.keymap.set("i", "<F9>", "_")
    plugin.teardown()
    eq(vim.fn.maparg("<F9>", "i", false, true).rhs, "_")
    vim.keymap.del("i", "<F9>")
  end)
  test("fast wrap: trace exports the identifier decision and reproduces locally", function()
    local entry = seed("(│)value")
    plugin.setup(opts)
    local trace = require("pairs.trace")
    trace.clear()
    trace.start()
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    trace.stop()
    eq(_G.pairs_test_result, "(value)│")
    local records = trace.entries()
    eq(#records, 1)
    eq(records[1].key, "<FastWrap>")
    eq(records[1].decision.action, "wrap")
    eq(records[1].decision.move, 5)
    eq(records[1].options.filetypes.lua.pairs["("].wrap, true)
    local path = vim.fn.tempname()
    trace.export(path)
    local record = vim.json.decode(table.concat(vim.fn.readfile(path), "\n")).records[1]
    vim.fn.delete(path)
    local at = record.cursor.col - record.input.start_col
    entry =
      seed(record.input.line:sub(1, at) .. "│" .. record.input.line:sub(at + 1), record.filetype)
    plugin.setup(record.options)
    vim.keymap.set("i", "<F9>", function()
      return plugin.fast_wrap() or ""
    end, { expr = true, replace_keycodes = false })
    feed(entry .. "<F9><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(value)│")
    vim.keymap.del("i", "<F9>")
    trace.clear()
  end)
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    for _, case in ipairs({
      {
        "Python multiline string",
        's = """\n(│)value\n"""',
        's = """\n(│)value\n"""',
        "python",
      },
      { "Rust block comment", "/*\n(│)value\n*/", "/*\n(│)value\n*/", "rust" },
      { "JS template text", "`(│)value`", "`(│)value`", "javascript" },
      { "JS interpolation brackets", "`${(│)value}`", "`${(value)│}`", "javascript" },
      { "Python interpolation brackets", 'f"{(│)value}"', 'f"{(value)│}"', "python" },
      { "JS structural interpolation", "`${│}value`", "`${│}value`", "javascript" },
      { "Python structural interpolation", 'f"{│}value"', 'f"{│}value"', "python" },
    }) do
      test("fast wrap: parser protects " .. case[1], function()
        input(
          case[2],
          "<F8>",
          case[3],
          vim.tbl_deep_extend("force", opts, { treesitter = true }),
          case[4]
        )
      end)
    end
    test("fast wrap: pending syntax is inert with one async request", function()
      local entry = seed("(│)value", "python")
      plugin.setup(vim.tbl_deep_extend("force", opts, { treesitter = true }))
      local parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "()value" })
      local original, calls = parser.parse, 0
      parser.parse = function(_, range, callback)
        calls = calls + 1
        eq(type(range), "table")
        eq(type(callback), "function")
        return nil
      end
      local ok, err = pcall(function()
        feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "(│)value")
        eq(calls, 1)
      end)
      parser.parse = original
      assert(ok, err)
    end)
  end
end

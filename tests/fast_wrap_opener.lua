return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = { mappings = { fast_wrap = "<F8>" } }
  for _, bracket in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
    local open, close = unpack(bracket)
    test(
      "opener wrap: " .. open .. close .. " inserts missing and reuses existing closers",
      function()
        input(open .. "│value", "<F8>", open .. "value" .. close .. "│", opts)
        input(open .. "│value" .. close, "<F8>", open .. "value" .. close .. "│", opts)
        input(
          "中文" .. open .. "│item_2" .. close .. " tail",
          "<F8>x",
          "中文" .. open .. "item_2" .. close .. "x│ tail",
          opts
        )
      end
    )
    test("opener wrap: typing " .. open .. " before an identifier joins undo/redo/dot", function()
      for _, suffix in ipairs({ "", close }) do
        input("│value" .. suffix, open .. "<F8>x", open .. "value" .. close .. "x│", opts)
        feed("u")
        eq(vim.api.nvim_get_current_line(), "value" .. suffix)
        feed("<C-r>")
        eq(vim.api.nvim_get_current_line(), open .. "value" .. close .. "x")
        feed("u.")
        eq(vim.api.nvim_get_current_line(), open .. "value" .. close .. "x")
      end
    end)
  end
  for _, case in ipairs({
    { "nested missing closer", "fn([│value)", "fn([value]│)" },
    { "nested existing closer", "fn((│value))", "fn((value)│)" },
    { "comma boundary", "(│value, tail", "(value)│, tail" },
    { "semicolon boundary", "[│item;", "[item]│;" },
    { "whitespace boundary", "(│value tail", "(value)│ tail" },
    { "newline boundary", "(│value\ntail", "(value)│\ntail" },
    { "distant closer is untouched", "(│value )", "(value)│ )" },
    { "one existing closer is reused", "(│value))", "(value)│)" },
  }) do
    test("opener wrap: " .. case[1], function()
      input(case[2], "<F8><F8>", case[3], opts)
    end)
  end
  for _, before in ipairs({
    "(│value.name",
    "(│fn()",
    "(│items[0]",
    "(│value+tail",
    "(│café)",
    "(│中文)",
    "(│42)",
    "(│ value)",
    "(x│value)",
    "\\(│value)",
    ") (│value",
    '"(│value)"',
    "-- (│value)",
  }) do
    test("opener wrap: unsafe target remains unchanged " .. before, function()
      input(before, "<F8>", before, opts)
    end)
  end
  test("opener wrap: insertion and reuse retain independent wrap policy", function()
    local independent = vim.tbl_deep_extend(
      "force",
      opts,
      { pairs = { ["("] = { open = false, skip = false, delete = false } } }
    )
    local disabled = vim.tbl_deep_extend("force", opts, { pairs = { ["("] = { wrap = false } } })
    for _, suffix in ipairs({ "", ")" }) do
      input("(│value" .. suffix, "<F8>", "(value)│", independent)
      input("(│value" .. suffix, "<F8>", "(│value" .. suffix, disabled)
      input(
        "(│value" .. suffix,
        "<F8>",
        "(│value" .. suffix,
        vim.tbl_deep_extend("force", opts, { enabled = false })
      )
    end
  end)
  test("opener wrap: filetype and live buffer policies apply to reuse", function()
    local ft = vim.tbl_deep_extend(
      "force",
      opts,
      { filetypes = { python = { pairs = { ["("] = { wrap = false } } } } }
    )
    input("(│value)", "<F8>", "(│value)", ft, "python")
    local entry = seed("(│value)", "python")
    plugin.setup(ft)
    vim.b.pairs_rules = { ["("] = { wrap = true } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).insert_close, false)
    vim.b.pairs_rules = { ["("] = { wrap = false } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "pass")
    vim.b.pairs_rules = { ["("] = { wrap = true } }
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(value)│")
  end)
  test("opener wrap: seed text retains undo/redo/dot in both modes", function()
    for _, suffix in ipairs({ "", ")" }) do
      input("(│value" .. suffix, "<F8>x", "(value)x│", opts)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "(value" .. suffix)
      feed("<C-r>")
      eq(vim.api.nvim_get_current_line(), "(value)x")
      feed("u.")
      eq(vim.api.nvim_get_current_line(), "(value)x")
    end
  end)
  test("opener wrap: pure reuse changes neither text tick nor undo history", function()
    local entry = seed("(│value)")
    plugin.setup(opts)
    local tick, sequence = vim.b.changedtick, vim.fn.undotree().seq_cur
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(value)│")
    eq(vim.b.changedtick, tick)
    eq(vim.fn.undotree().seq_cur, sequence)
  end)
  test("opener wrap: nested continuous input retains undo/redo/dot", function()
    input("│value]", "[(<F8>]x", "[(value)]x│", opts)
    feed("u")
    eq(vim.api.nvim_get_current_line(), "value]")
    feed("<C-r>")
    eq(vim.api.nvim_get_current_line(), "[(value)]x")
    feed("u.")
    eq(vim.api.nvim_get_current_line(), "[(value)]x")
  end)
  test("opener wrap: budget includes prefix and identifier, with one boundary byte", function()
    for _, suffix in ipairs({ "", ")" }) do
      input(
        "(│value" .. suffix,
        "<F8>",
        "(│value" .. suffix,
        vim.tbl_deep_extend("force", opts, { max_scan_bytes = 5 })
      )
      input(
        "(│value" .. suffix,
        "<F8>",
        "(value)│",
        vim.tbl_deep_extend("force", opts, { max_scan_bytes = 6 })
      )
    end
    input(
      "xx (│value",
      "<F8>",
      "xx (│value",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 8 })
    )
    input(
      "(│value);" .. string.rep("x", 10000),
      "<F8>",
      "(value)│;" .. string.rep("x", 10000),
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 6 })
    )
  end)
  test("opener wrap: one prefix scan and no stale insertion flags", function()
    seed("(│value")
    plugin.setup(opts)
    local lex = require("pairs.lex")
    local original, calls = lex.scan, 0
    lex.scan = function(...)
      calls = calls + 1
      return original(...)
    end
    local ok, err = pcall(function()
      local result = plugin.explain("<FastWrap>", { assume_insert = true })
      eq(result.remove_close, false)
      eq(result.insert_close, true)
      eq(calls, 1)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(item)" })
      result = plugin.explain("<FastWrap>", { assume_insert = true })
      eq(result.move, 4)
      eq(result.insert_close, false)
      eq(calls, 2)
    end)
    lex.scan = original
    assert(ok, err)
  end)
  test("opener wrap: composed API needs no owned shortcut", function()
    plugin.setup({ mappings = { enabled = false } })
    vim.keymap.set("i", "<F9>", function()
      return plugin.fast_wrap() or "_"
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      for _, suffix in ipairs({ "", ")" }) do
        input("(│value" .. suffix, "<F9><F9>", "(value)_│", { mappings = { enabled = false } })
      end
    end)
    vim.keymap.del("i", "<F9>")
    assert(ok, err)
  end)
  test("opener wrap: trace flags export and replay all three wrapping modes", function()
    local trace = require("pairs.trace")
    trace.clear()
    for _, before in ipairs({ "(│)value", "(│value", "(│value)" }) do
      local entry = seed(before)
      plugin.setup(opts)
      trace.start()
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      trace.stop()
      eq(_G.pairs_test_result, "(value)│")
    end
    local records = trace.entries()
    eq(#records, 3)
    eq(records[1].decision.remove_close, true)
    eq(records[1].decision.insert_close, true)
    eq(records[2].decision.remove_close, false)
    eq(records[2].decision.insert_close, true)
    eq(records[2].decision.reason, "identifier_wrap_missing_closer")
    eq(records[3].decision.remove_close, false)
    eq(records[3].decision.insert_close, false)
    eq(records[3].decision.reason, "identifier_wrap_existing_closer")
    local path = vim.fn.tempname()
    trace.export(path)
    local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    vim.fn.delete(path)
    eq(data.records, records)
    vim.keymap.set("i", "<F9>", function()
      return plugin.fast_wrap() or ""
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      for _, record in ipairs(data.records) do
        local at = record.cursor.col - record.input.start_col
        local entry = seed(
          record.input.line:sub(1, at) .. "│" .. record.input.line:sub(at + 1),
          record.filetype
        )
        plugin.setup(record.options)
        feed(entry .. "<F9><Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "(value)│")
      end
    end)
    vim.keymap.del("i", "<F9>")
    trace.clear()
    assert(ok, err)
  end)
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    for _, case in ipairs({
      { 's = """\n(│value)\n"""', 's = """\n(│value)\n"""', "python" },
      { "/*\n(│value\n*/", "/*\n(│value\n*/", "rust" },
      { "`(│value)`", "`(│value)`", "javascript" },
      { "`${(│value)}`", "`${(value)│}`", "javascript" },
      { 'f"{[│value}"', 'f"{[│value}"', "python" },
      { 'f"{(│value)}"', 'f"{(value)│}"', "python" },
      { "`${│value}`", "`${│value}`", "javascript" },
      { 'f"{│value}"', 'f"{│value}"', "python" },
    }) do
      test("opener wrap: parser protects " .. case[1], function()
        input(
          case[1],
          "<F8>",
          case[2],
          vim.tbl_deep_extend("force", opts, { treesitter = true }),
          case[3]
        )
      end)
    end
    for _, suffix in ipairs({ "", ")" }) do
      test("opener wrap: pending parser remains inert " .. suffix, function()
        local entry = seed("(│value" .. suffix, "python")
        plugin.setup(vim.tbl_deep_extend("force", opts, { treesitter = true }))
        local parser = vim.treesitter.get_parser(0, "python")
        parser:parse(true)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(value" .. suffix })
        local original, calls = parser.parse, 0
        parser.parse = function(_, range, callback)
          calls = calls + 1
          eq(type(range), "table")
          eq(type(callback), "function")
          return nil
        end
        local ok, err = pcall(function()
          feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
          eq(_G.pairs_test_result, "(│value" .. suffix)
          eq(calls, 1)
        end)
        parser.parse = original
        assert(ok, err)
      end)
    end
  end
end

return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = { mappings = { fast_wrap = "<F8>" } }
  for _, bracket in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
    local open, close = unpack(bracket)
    for _, mode in ipairs({ "adjacent", "missing", "reuse" }) do
      test("member wrap: " .. open .. close .. " " .. mode, function()
        for _, target in ipairs({ "obj.value", "config.options.enabled", "_self._item42.value_2" }) do
          local before = open
            .. "│"
            .. (mode == "adjacent" and close or "")
            .. target
            .. (mode == "reuse" and close or "")
          input(before, "<F8><F8>", open .. target .. close .. "│", opts)
        end
      end)
    end
    test("member wrap: typed " .. open .. " keeps undo/redo/dot", function()
      for _, suffix in ipairs({ "", close }) do
        input(
          "│obj.value" .. suffix,
          open .. "<F8>x",
          open .. "obj.value" .. close .. "x│",
          opts
        )
        feed("u")
        eq(vim.api.nvim_get_current_line(), "obj.value" .. suffix)
        feed("<C-r>")
        eq(vim.api.nvim_get_current_line(), open .. "obj.value" .. close .. "x")
        feed("u.")
        eq(vim.api.nvim_get_current_line(), open .. "obj.value" .. close .. "x")
      end
    end)
  end
  for _, case in ipairs({
    { "fn([│obj.value)", "fn([obj.value]│)" },
    { "fn((│obj.value))", "fn((obj.value)│)" },
    { "中文(│)obj.value tail", "中文(obj.value)│ tail" },
    { "(│obj.value, tail", "(obj.value)│, tail" },
    { "(│obj.value;", "(obj.value)│;" },
    { "(│obj.value\ttail", "(obj.value)│\ttail" },
    { "(│obj.value\ntail", "(obj.value)│\ntail" },
    { "(│obj.value )", "(obj.value)│ )" },
  }) do
    test("member wrap: suffix preserved " .. case[1], function()
      input(case[1], "<F8>", case[2], opts)
    end)
  end
  for _, target in ipairs({
    "obj.",
    "obj..value",
    "obj...value",
    "obj.42",
    "obj. value",
    "obj.\tvalue",
    "obj.\nvalue",
    "obj.value.",
    "obj.value..tail",
    "obj.value()",
    "obj.value[0]",
    "obj.value+tail",
    "obj.value:tail",
    "obj->value",
    "obj::value",
    "obj?.value",
    "obj.中文",
    "obj.café",
    "café.value",
    "obj.valueé",
    "obj.$value",
    "obj.\\value",
  }) do
    test("member wrap: rejects whole unsupported chain " .. target, function()
      for _, mode in ipairs({ "adjacent", "missing", "reuse" }) do
        local before = "(│"
          .. (mode == "adjacent" and ")" or "")
          .. target
          .. (mode == "reuse" and ")" or "")
        input(before, "<F8>", before, opts)
      end
    end)
  end
  test("member wrap: native closer movement retains undo/redo/dot", function()
    input("(│)obj.value", "<F8>x", "(obj.value)x│", opts)
    feed("u")
    eq(vim.api.nvim_get_current_line(), "()obj.value")
    feed("<C-r>")
    eq(vim.api.nvim_get_current_line(), "(obj.value)x")
    feed("u.")
    eq(vim.api.nvim_get_current_line(), "(obj.value)x")
  end)
  test("member wrap: reuse leaves text tick and undo sequence untouched", function()
    local entry = seed("(│config.options.enabled)")
    plugin.setup(opts)
    local tick, sequence = vim.b.changedtick, vim.fn.undotree().seq_cur
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(config.options.enabled)│")
    eq(vim.b.changedtick, tick)
    eq(vim.fn.undotree().seq_cur, sequence)
  end)
  test("member wrap: complete prefix and every segment share the byte budget", function()
    for _, before in ipairs({ "(│)obj.value", "(│obj.value", "(│obj.value)" }) do
      local entry = seed(before)
      local last = before:find("value", 1, true) + #"value" - 1 - #"│"
      plugin.setup(vim.tbl_deep_extend("force", opts, { max_scan_bytes = last - 1 }))
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "pass")
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, before)
      input(
        before,
        "<F8>",
        "(obj.value)│",
        vim.tbl_deep_extend("force", opts, { max_scan_bytes = last })
      )
    end
    -- No budget cut at a dot or inside a member may wrap just the first segment.
    for budget = 2, 9 do
      input(
        "(│obj.value)",
        "<F8>",
        "(│obj.value)",
        vim.tbl_deep_extend("force", opts, { max_scan_bytes = budget })
      )
    end
    input(
      "中文(│obj.value)",
      "<F8>",
      "中文(│obj.value)",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 15 })
    )
    input(
      "中文(│obj.value)",
      "<F8>",
      "中文(obj.value)│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 16 })
    )
    input(
      "(│obj.value);" .. string.rep("x", 10000),
      "<F8>",
      "(obj.value)│;" .. string.rep("x", 10000),
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 10 })
    )
    input(
      "(│obj.valueé",
      "<F8>",
      "(│obj.valueé",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 10 })
    )
    local target = string.rep("a.", 1000) .. "z"
    input(
      "(│" .. target,
      "<F8>",
      "(" .. target .. ")│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = #target + 1 })
    )
  end)
  test("member wrap: wrap policy stays live and independent", function()
    input(
      "(│obj.value)",
      "<F8>",
      "(obj.value)│",
      vim.tbl_deep_extend(
        "force",
        opts,
        { pairs = { ["("] = { open = false, skip = false, delete = false } } }
      )
    )
    local entry = seed("(│obj.value)")
    plugin.setup(opts)
    vim.b.pairs_rules = { ["("] = { wrap = false } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "pass")
    vim.b.pairs_rules = { ["("] = { wrap = true } }
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(obj.value)│")
  end)
  test("member wrap: one scan and fresh chain length after edits", function()
    seed("(│obj.value)")
    plugin.setup(opts)
    local lex = require("pairs.lex")
    local original, calls = lex.scan, 0
    lex.scan = function(...)
      calls = calls + 1
      return original(...)
    end
    local ok, err = pcall(function()
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).move, 9)
      eq(calls, 1)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(config.options.enabled)" })
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).move, 22)
      eq(calls, 2)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(config.options.)" })
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "pass")
      eq(calls, 3)
    end)
    lex.scan = original
    assert(ok, err)
  end)
  test("member wrap: trace export replays full length in all modes", function()
    local trace = require("pairs.trace")
    trace.clear()
    for _, before in ipairs({ "(│)obj.value", "(│obj.value", "(│obj.value)" }) do
      local entry = seed(before)
      plugin.setup(opts)
      trace.start()
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      trace.stop()
      eq(_G.pairs_test_result, "(obj.value)│")
    end
    local path = vim.fn.tempname()
    trace.export(path)
    local records = vim.json.decode(table.concat(vim.fn.readfile(path), "\n")).records
    vim.fn.delete(path)
    eq(#records, 3)
    for i, record in ipairs(records) do
      eq(record.decision.move, 9)
      eq(record.decision.remove_close, i == 1)
      eq(record.decision.insert_close, i ~= 3)
      local at = record.cursor.col - record.input.start_col
      input(
        record.input.line:sub(1, at) .. "│" .. record.input.line:sub(at + 1),
        "<F8>",
        "(obj.value)│",
        opts,
        record.filetype
      )
    end
    trace.clear()
  end)
  for _, before in ipairs({
    '"(│obj.value)"',
    "-- (│obj.value)",
    "\\(│obj.value)",
    ") (│obj.value)",
  }) do
    test("member wrap: lexer guards " .. before, function()
      input(before, "<F8>", before, opts)
    end)
  end
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    for _, case in ipairs({
      { 's = """\n(│obj.value)\n"""', 's = """\n(│obj.value)\n"""', "python" },
      { "/*\n(│obj.value)\n*/", "/*\n(│obj.value)\n*/", "rust" },
      { "`(│obj.value)`", "`(│obj.value)`", "javascript" },
      { "`${(│obj.value)}`", "`${(obj.value)│}`", "javascript" },
      { 'f"{(│obj.value)}"', 'f"{(obj.value)│}"', "python" },
      { "`${│obj.value}`", "`${│obj.value}`", "javascript" },
      { 'f"{│obj.value}"', 'f"{│obj.value}"', "python" },
    }) do
      test("member wrap: parser protects " .. case[1], function()
        input(
          case[1],
          "<F8>",
          case[2],
          vim.tbl_deep_extend("force", opts, { treesitter = true }),
          case[3]
        )
      end)
    end
    test("member wrap: pending parser requests once and makes no partial edit", function()
      local entry = seed("(│obj.value)", "python")
      plugin.setup(vim.tbl_deep_extend("force", opts, { treesitter = true }))
      local parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(obj.value)" })
      local original, calls = parser.parse, 0
      parser.parse = function(_, range, callback)
        calls = calls + 1
        eq(type(range), "table")
        eq(type(callback), "function")
        return nil
      end
      local ok, err = pcall(function()
        feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "(│obj.value)")
        eq(calls, 1)
      end)
      parser.parse = original
      assert(ok, err)
    end)
  end
end

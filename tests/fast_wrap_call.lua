return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = { mappings = { fast_wrap = "<F8>" } }
  local function shape(open, close, target, mode)
    return open
      .. "│"
      .. (mode == "adjacent" and close or "")
      .. target
      .. (mode == "reuse" and close or "")
  end
  for _, bracket in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
    local open, close = unpack(bracket)
    for _, mode in ipairs({ "adjacent", "missing", "reuse" }) do
      test("call wrap: " .. open .. close .. " " .. mode, function()
        for _, target in ipairs({
          "fn()",
          "fn(a, b)",
          "obj.get_value()",
          "config.options.get(x)",
          'fn(g(x), [1, 2], {a = ")"})',
          "fn(\"(])\", '{)}')",
          'fn("a\\" )", x)',
          'fn("a\\\\", x)',
          'fn("中文", café, "🙂", "é", "👩‍💻")',
          "fn(\tx, y\t)",
        }) do
          input(
            shape(open, close, target, mode),
            "<F8><F8>",
            open .. target .. close .. "│",
            opts
          )
        end
      end)
    end
    test("call wrap: typed " .. open .. " retains undo/redo/dot", function()
      for _, suffix in ipairs({ "", close }) do
        local target = 'obj.get("中文", nested(x))'
        input("│" .. target .. suffix, open .. "<F8>z", open .. target .. close .. "z│", opts)
        feed("u")
        eq(vim.api.nvim_get_current_line(), target .. suffix)
        feed("<C-r>")
        eq(vim.api.nvim_get_current_line(), open .. target .. close .. "z")
        feed("u.")
        eq(vim.api.nvim_get_current_line(), open .. target .. close .. "z")
      end
    end)
  end
  for _, case in ipairs({
    { "outer([│fn(x))", "outer([fn(x)]│)" },
    { "outer((│fn(x)))", "outer((fn(x))│)" },
    { "中文(│)fn(x) tail", "中文(fn(x))│ tail" },
    { "(│fn(x), next", "(fn(x))│, next" },
    { "(│fn(x);", "(fn(x))│;" },
    { "(│fn(x)\ntail", "(fn(x))│\ntail" },
    { "(│fn(x) )", "(fn(x))│ )" },
    { "(│fn(x))tail", "(fn(x))│tail" },
  }) do
    test("call wrap: suffix preserved " .. case[1], function()
      input(case[1], "<F8>", case[2], opts)
    end)
  end
  for _, target in ipairs({
    "fn(",
    "fn(x",
    "fn(g(x)",
    "fn([x))",
    "fn({x])",
    "fn(x\ny)",
    'fn("x)',
    "fn('x)",
    'fn("a\\" )',
    "fn()()",
    "fn().value",
    "fn()[0]",
    "fn(x)+tail",
    "fn(x):tail",
    "fn(x)é",
    'fn(x)"tail"',
    "obj..fn(x)",
    "fn([[)]], x)",
    "fn([=[)]=], x)",
    'fn("""x)""", y)',
    "fn('''x)''', y)",
    "fn(`x)`, y)",
    "fn(x /* ) */ , y)",
    "fn(x -- ) )",
    "fn(x \\) )",
  }) do
    test("call wrap: no partial wrap " .. target, function()
      -- Appending a reuse closer completes these three call texts; current
      -- nesting then proves a valid call rather than an incomplete target.
      local modes = (target == "fn(" or target == "fn(x" or target == "fn(g(x)")
          and { "adjacent", "missing" }
        or { "adjacent", "missing", "reuse" }
      for _, mode in ipairs(modes) do
        local before = shape("(", ")", target, mode)
        input(before, "<F8>", before, opts)
      end
    end)
  end
  for _, case in ipairs({
    { 'fn(f"{g(")")}")', "python" },
    { 'fn(fr"{x}")', "python" },
    { 'fn(r"x)")', "python" },
    { "fn(x # ) )", "python" },
    { 'fn(r"x\\", y)', "rust" },
    { 'fn(r##"x)"##, y)', "rust" },
    { 'fn(R"(x))", y)', "cpp" },
    { 'fn(#"x)"#, y)', "swift" },
    { "fn(/) tail/)", "swift" },
    { 'fn("\\(g(")"))")', "swift" },
    { "fn(/) tail/)", "javascript" },
    { "fn(x / y)", "typescript" },
    { "fn(x // ) )", "c" },
    { 'fn("${g(")")}")', "bash" },
    { 'fn("#{g(")")}")', "ruby" },
    { "fn(%q{x)}, y)", "ruby" },
    { "fn(/) tail/)", "ruby" },
    { 'fn(@"x)""y")', "cs" },
  }) do
    test("call wrap: unsupported literal/comment " .. case[2] .. " " .. case[1], function()
      local before = "(│" .. case[1]
      input(before, "<F8>", before, opts, case[2])
    end)
  end
  test("call wrap: ordinary strings, escapes and division remain supported", function()
    for _, ft in ipairs({ "lua", "python", "rust", "cpp", "javascript", "typescript", "swift" }) do
      input("(│fn(\"x)\", 'a', y)", "<F8>", "(fn(\"x)\", 'a', y))│", opts, ft)
    end
    input("(│fn(x / y)", "<F8>", "(fn(x / y))│", opts, "python")
    input("(│fn('x\\', y)", "<F8>", "(fn('x\\', y))│", opts, "bash")
    input('(│fn("${literal}", "#{literal}")', "<F8>", '(fn("${literal}", "#{literal}"))│', opts)
  end)
  test("call wrap: disabled delimiter policies do not change structural proof", function()
    input(
      '(│fn([x], ")")',
      "<F8>",
      '(fn([x], ")"))│',
      vim.tbl_deep_extend("force", opts, {
        pairs = {
          ["["] = false,
          ['"'] = false,
          ["("] = { open = false, skip = false, delete = false },
        },
      })
    )
    input(
      "(│fn(x)",
      "<F8>",
      "(│fn(x)",
      vim.tbl_deep_extend("force", opts, { pairs = { ["("] = { wrap = false } } })
    )
  end)
  test("call wrap: virtual tab movement respects prefix and buffer tab widths", function()
    local previous = vim.o.virtualedit
    local ok, err = pcall(function()
      for _, virtual in ipairs({ "", "all", "insert", "onemore", "block" }) do
        vim.o.virtualedit = virtual
        for _, mode in ipairs({ "adjacent", "missing", "reuse" }) do
          local target = 'fn(\tx, "中文",\ty)'
          input(
            "中文 " .. shape("(", ")", target, mode) .. " tail",
            "<F8>",
            "中文 (" .. target .. ")│ tail",
            opts,
            "lua",
            { tabstop = 8, vartabstop = "4,6" }
          )
        end
      end
    end)
    vim.o.virtualedit = previous
    assert(ok, err)
  end)
  test("call wrap: live rule and engine policies apply", function()
    local entry = seed("(│fn(x))")
    plugin.setup(opts)
    vim.b.pairs_rules = { ["("] = { wrap = false } }
    eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "pass")
    vim.b.pairs_rules = { ["("] = { wrap = true } }
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(fn(x))│")
    input(
      "(│fn(x))",
      "<F8>",
      "(│fn(x))",
      vim.tbl_deep_extend("force", opts, { enabled = false })
    )
  end)
  test("call wrap: reuse retains text tick and undo sequence", function()
    local entry = seed('(│fn("é中文", x))')
    plugin.setup(opts)
    local tick, sequence = vim.b.changedtick, vim.fn.undotree().seq_cur
    feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, '(fn("é中文", x))│')
    eq(vim.b.changedtick, tick)
    eq(vim.fn.undotree().seq_cur, sequence)
  end)
  test("call wrap: full byte budget includes args, strings and call closer", function()
    local target = 'fn(g(x), "中文)")'
    for _, mode in ipairs({ "adjacent", "missing", "reuse" }) do
      local before = shape("(", ")", target, mode)
      local last = 1 + (mode == "adjacent" and 1 or 0) + #target
      for budget = 2, last - 1 do
        input(
          before,
          "<F8>",
          before,
          vim.tbl_deep_extend("force", opts, { max_scan_bytes = budget })
        )
      end
      input(
        before,
        "<F8>",
        "(" .. target .. ")│",
        vim.tbl_deep_extend("force", opts, { max_scan_bytes = last })
      )
    end
    input(
      "(│fn(x)()",
      "<F8>",
      "(│fn(x)()",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 6 })
    )
    input(
      "(│fn(x));" .. string.rep("x", 10000),
      "<F8>",
      "(fn(x))│;" .. string.rep("x", 10000),
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 6 })
    )
    local target = "fn(" .. string.rep("(", 100) .. "x" .. string.rep(")", 101)
    input(
      "(│" .. target,
      "<F8>",
      "(" .. target .. ")│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = #target + 1 })
    )
  end)
  test("call wrap: one prefix scan and fresh call boundary after edit", function()
    seed("(│fn(x))")
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
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '(obj.get("中文"))' })
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).move, #'obj.get("中文")')
      eq(calls, 2)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { '(obj.get("中文))' })
      eq(plugin.explain("<FastWrap>", { assume_insert = true }).action, "pass")
      eq(calls, 3)
    end)
    lex.scan = original
    assert(ok, err)
  end)
  test("call wrap: adjacent movement retains undo/redo/dot with Unicode args", function()
    input('(│)fn("中文")', "<F8>x", '(fn("中文"))x│', opts)
    feed("u")
    eq(vim.api.nvim_get_current_line(), '()fn("中文")')
    feed("<C-r>")
    eq(vim.api.nvim_get_current_line(), '(fn("中文"))x')
    feed("u.")
    eq(vim.api.nvim_get_current_line(), '(fn("中文"))x')
  end)
  test("call wrap: trace byte lengths export and replay all three modes", function()
    local trace = require("pairs.trace")
    local target = 'obj.get("中文", x)'
    trace.clear()
    for _, mode in ipairs({ "adjacent", "missing", "reuse" }) do
      local entry = seed(shape("(", ")", target, mode))
      plugin.setup(opts)
      trace.start()
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      trace.stop()
      eq(_G.pairs_test_result, "(" .. target .. ")│")
    end
    local path = vim.fn.tempname()
    trace.export(path)
    local records = vim.json.decode(table.concat(vim.fn.readfile(path), "\n")).records
    vim.fn.delete(path)
    eq(#records, 3)
    vim.keymap.set("i", "<F9>", function()
      return plugin.fast_wrap() or ""
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      for i, record in ipairs(records) do
        eq(record.decision.move, #target)
        eq(record.decision.remove_close, i == 1)
        eq(record.decision.insert_close, i ~= 3)
        eq(record.decision.target, nil)
        local at = record.cursor.col - record.input.start_col
        input(
          record.input.line:sub(1, at) .. "│" .. record.input.line:sub(at + 1),
          "<F9>",
          "(" .. target .. ")│",
          record.options,
          record.filetype
        )
      end
    end)
    vim.keymap.del("i", "<F9>")
    trace.clear()
    assert(ok, err)
  end)
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    for _, case in ipairs({
      { 's = """\n(│fn(x))\n"""', 's = """\n(│fn(x))\n"""', "python" },
      { "/*\n(│fn(x))\n*/", "/*\n(│fn(x))\n*/", "rust" },
      { "`(│fn(x))`", "`(│fn(x))`", "javascript" },
      { "`${(│fn(x))}`", "`${(fn(x))│}`", "javascript" },
      { 'f"{(│fn(x))}"', 'f"{(fn(x))│}"', "python" },
      { "`${│fn(x)}`", "`${│fn(x)}`", "javascript" },
      { 'f"{│fn(x)}"', 'f"{│fn(x)}"', "python" },
      { '(│obj.get("x)", [1, 2]))', '(obj.get("x)", [1, 2]))│', "python" },
      { '(│obj.get("x)", [1, 2]))', '(obj.get("x)", [1, 2]))│', "javascript" },
    }) do
      test("call wrap: parser protection " .. case[3] .. " " .. case[1], function()
        input(
          case[1],
          "<F8>",
          case[2],
          vim.tbl_deep_extend("force", opts, { treesitter = true }),
          case[3]
        )
      end)
    end
    test("call wrap: pending syntax stays inert with one async request", function()
      local entry = seed("(│fn(x))", "python")
      plugin.setup(vim.tbl_deep_extend("force", opts, { treesitter = true }))
      local parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(fn(x))" })
      local original, calls = parser.parse, 0
      parser.parse = function(_, range, callback)
        calls = calls + 1
        eq(type(range), "table")
        eq(type(callback), "function")
        return nil
      end
      local ok, err = pcall(function()
        feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "(│fn(x))")
        eq(calls, 1)
      end)
      parser.parse = original
      assert(ok, err)
    end)
  end
end

return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = {
    pairs = {
      ["("] = { skip_space = true },
      ["["] = { skip_space = true },
      ["{"] = { skip_space = true },
    },
  }
  for _, bracket in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
    local open, close = unpack(bracket)
    test("space skip: " .. open .. close .. " exits after one right space", function()
      input(open .. " value│ " .. close, close, open .. " value " .. close .. "│", opts)
      input(open .. " │ " .. close .. "tail", close, open .. "  " .. close .. "│tail", opts)
    end)
  end
  for _, case in ipairs({
    { "nested matched brackets", "([ item│ ])", "])", "([ item ])│" },
    { "nested padded closers", "({[ value│ ] } )", "]})", "({[ value ] } )│" },
    { "Unicode body and suffix", "fn( 中文│ )中文", ")", "fn( 中文 )│中文" },
    { "manual padding without left space", "(value│ )", ")", "(value )│" },
    { "adjacent closer unchanged", "(value│)", ")", "(value)│" },
    { "multiple right spaces stay native", "(value│  )", ")", "(value)│  )" },
    { "tab stays native", "(value│\t)", ")", "(value)│\t)" },
    { "non-ASCII space stays native", "(value│　)", ")", "(value)│　)" },
    { "newline stays native", "(value│\n)", ")", "(value)│\n)" },
    { "intervening text stays native", "(value│ x)", ")", "(value)│ x)" },
    { "mismatched closer", "(value│ ]", "]", "(value]│ ]" },
    { "wrong nesting", "([value│ )]", ")", "([value)│ )]" },
    { "unmatched prefix", ") (value│ )", ")", ") (value)│ )" },
    { "no opener", "value│ )", ")", "value)│ )" },
    { "escaped opener", "\\(value│ )", ")", "\\(value)│ )" },
    { "escaped cursor", "(value\\│ )", ")", "(value\\)│ )" },
    { "quoted text", '"(value│ )"', ")", '"(value)│ )"' },
    { "comment", "-- (value│ )", ")", "-- (value)│ )" },
  }) do
    test("space skip: " .. case[1], function()
      input(case[2], case[3], case[4], opts)
    end)
  end
  test("space skip: opt-in is separate from padding and owns no Space", function()
    input("(value│ )", ")", "(value)│ )")
    input("(value│ )", ")", "(value)│ )", { pairs = { ["("] = { space = true } } })
    input("(value│ )", ")", "(value )│", opts)
    eq(vim.fn.maparg("<Space>", "i"), "")
  end)
  test("space skip: skip and open policies remain independent", function()
    input(
      "(value│ )",
      ")",
      "(value)│ )",
      { pairs = { ["("] = { skip_space = true, skip = false } } }
    )
    input(
      "(value│ )",
      ")",
      "(value )│",
      { pairs = { ["("] = { skip_space = true, open = false } } }
    )
    input("(value│ )", ")", "(value)│ )", { pairs = { ["("] = false } })
  end)
  test("space skip: disabled engine and mappings retain native input", function()
    input(
      "(value│ )",
      ")",
      "(value)│ )",
      vim.tbl_deep_extend("force", opts, { enabled = false })
    )
    input(
      "(value│ )",
      ")",
      "(value)│ )",
      vim.tbl_deep_extend("force", opts, { mappings = { enabled = false } })
    )
  end)
  test("space skip: continuous padding input retains undo, redo and dot", function()
    local padded = vim.tbl_deep_extend("force", opts, {
      pairs = {
        ["("] = { space = true },
        ["["] = { space = true },
        ["{"] = { space = true },
      },
    })
    input("│", "( { [ value]})tail", "( { [ value ] } )tail│", padded)
    local expected = { "( { [ value ] } )tail" }
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected)
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected)
  end)
  test("space skip: filetype and live buffer precedence", function()
    local ft = { filetypes = { python = { pairs = { ["("] = { skip_space = true } } } } }
    input("(value│ )", ")", "(value )│", ft, "python")
    input("(value│ )", ")", "(value)│ )", ft)
    input(
      "(value│ )",
      ")",
      "(value)│ )",
      vim.tbl_deep_extend("force", opts, {
        filetypes = { lua = { pairs = { ["("] = { skip_space = false } } } },
      })
    )
    local entry = seed("(value│ )")
    plugin.setup(opts)
    vim.b.pairs_rules = { ["("] = { skip_space = false } }
    eq(plugin.explain(")", { assume_insert = true }).action, "pass")
    vim.b.pairs_rules = { ["("] = { skip_space = true } }
    eq(plugin.explain(")", { assume_insert = true }).move, 2)
    vim.b.pairs_rules = nil
    feed(entry .. ")<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(value )│")
  end)
  test("space skip: bounded prefix is scanned once", function()
    seed("(value│ )")
    plugin.setup(opts)
    local lex = require("pairs.lex")
    local original, calls = lex.scan, 0
    lex.scan = function(...)
      calls = calls + 1
      return original(...)
    end
    local ok, err = pcall(function()
      eq(plugin.explain(")", { assume_insert = true }).move, 2)
      eq(calls, 1)
    end)
    lex.scan = original
    assert(ok, err)
    input(
      "(value│ )",
      ")",
      "(value)│ )",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 5 })
    )
    input(
      "(value│ )",
      ")",
      "(value )│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 6 })
    )
  end)
  test("space skip: invalid booleans and shapes preserve existing setup", function()
    seed("(value│ )")
    plugin.setup(opts)
    for _, invalid in ipairs({
      { pairs = { ["("] = { skip_space = 1 } } },
      { pairs = { ['"'] = { skip_space = true } } },
      { pairs = { ["<"] = { close = ">", skip_space = true } } },
      { filetypes = { python = { pairs = { ["("] = { skip_space = "yes" } } } } },
    }) do
      eq(pcall(plugin.setup, invalid), false)
      eq(plugin.explain(")", { assume_insert = true }).move, 2)
    end
    vim.b.pairs_rules = { ["("] = { skip_space = "yes" } }
    eq(plugin.explain(")", { assume_insert = true }).reason, "context_error")
    vim.b.pairs_rules = nil
  end)
  test("space skip: existing global closer owner remains intact", function()
    local entry = seed("(value│ )")
    vim.keymap.set("i", ")", "_")
    plugin.setup(opts)
    local ok, err = pcall(function()
      eq(plugin.status().conflicts, { ")" })
      feed(entry .. ")<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "(value_│ )")
      plugin.teardown()
      eq(vim.fn.maparg(")", "i", false, true).rhs, "_")
    end)
    vim.keymap.del("i", ")")
    assert(ok, err)
  end)
  test("space skip: buffer closer owner wins", function()
    local entry = seed("(value│ )")
    vim.keymap.set("i", ")", "_", { buffer = true })
    plugin.setup(opts)
    feed(entry .. ")<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(value_│ )")
  end)
  test("space skip: composed closer moves without owned mappings", function()
    local entry = seed("(value│ )tail")
    plugin.setup(vim.tbl_deep_extend("force", opts, { mappings = { enabled = false } }))
    vim.keymap.set("i", "<F8>", function()
      return plugin.expr(")") or ")"
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "(value )│tail")
    end)
    vim.keymap.del("i", "<F8>")
    assert(ok, err)
  end)
  test("space skip: trace export preserves policy and two-position movement", function()
    local entry = seed("(value│ )")
    plugin.setup(opts)
    local trace = require("pairs.trace")
    trace.clear()
    trace.start()
    feed(entry .. ")<Cmd>lua pairs_test_capture()<CR><Esc>")
    trace.stop()
    eq(_G.pairs_test_result, "(value )│")
    local records = trace.entries()
    eq(#records, 1)
    eq(records[1].decision.reason, "matching_bracket_space")
    eq(records[1].decision.move, 2)
    eq(records[1].options.filetypes.lua.pairs["("].skip_space, true)
    local path = vim.fn.tempname()
    trace.export(path)
    eq(vim.json.decode(table.concat(vim.fn.readfile(path), "\n")).records, records)
    vim.fn.delete(path)
    trace.clear()
  end)
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    for _, case in ipairs({
      {
        "Python multiline string",
        's = """\n(value│ )\n"""',
        ")",
        's = """\n(value)│ )\n"""',
        "python",
      },
      { "Rust block comment", "/*\n(value│ )\n*/", ")", "/*\n(value)│ )\n*/", "rust" },
      { "JS template text", "`(value│ )`", ")", "`(value)│ )`", "javascript" },
      { "JS structural interpolation", "`${value│ }`", "}", "`${value}│ }`", "javascript" },
      { "Python structural interpolation", 'f"{value│ }"', "}", 'f"{value}│ }"', "python" },
      {
        "JS interpolation brackets",
        "`${fn( value│ )}`",
        ")",
        "`${fn( value )│}`",
        "javascript",
      },
      {
        "Python interpolation brackets",
        'f"{fn( value│ )}"',
        ")",
        'f"{fn( value )│}"',
        "python",
      },
      {
        "JS nested object braces",
        "`${({value: 1│ })}`",
        "}",
        "`${({value: 1 }│)}`",
        "javascript",
      },
    }) do
      test("space skip: parser protects " .. case[1], function()
        input(
          case[2],
          case[3],
          case[4],
          vim.tbl_deep_extend("force", opts, { treesitter = true }),
          case[5]
        )
      end)
    end
    test("space skip: pending syntax stays native with one async request", function()
      local entry = seed("(value│ )", "python")
      plugin.setup(vim.tbl_deep_extend("force", opts, { treesitter = true }))
      local parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(value )" })
      local original, calls = parser.parse, 0
      parser.parse = function(_, range, callback)
        calls = calls + 1
        eq(type(range), "table")
        eq(type(callback), "function")
        return nil
      end
      local ok, err = pcall(function()
        feed(entry .. ")<Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "(value)│ )")
        eq(calls, 1)
      end)
      parser.parse = original
      assert(ok, err)
    end)
  end
end

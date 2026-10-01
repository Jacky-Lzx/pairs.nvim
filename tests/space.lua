return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts =
    { pairs = { ["("] = { space = true }, ["["] = { space = true }, ["{"] = { space = true } } }
  for _, bracket in ipairs({ { "(", ")" }, { "[", "]" }, { "{", "}" } }) do
    local open, close = unpack(bracket)
    test("space: empty " .. open .. close .. " inserts one space on each side", function()
      input(open .. "│" .. close, " ", open .. " │ " .. close, opts)
    end)
    test("space: padded " .. open .. close .. " deletes only its spaces", function()
      input(open .. " │ " .. close, "<BS>", open .. "│" .. close, opts)
    end)
    test("space: padded " .. open .. close .. " expands Enter without trailing padding", function()
      input(
        "  " .. open .. " │ " .. close,
        "<CR>x",
        "  " .. open .. "\n    x│\n  " .. close,
        opts
      )
    end)
  end
  for _, case in ipairs({
    { "nonempty body before cursor", "(a│)", " ", "(a │)" },
    { "nonempty body after cursor", "(│a)", " ", "( │a)" },
    { "existing single space", "(│ )", " ", "( │ )" },
    { "space is not added twice", "( │ )", " ", "(  │ )" },
    { "extra left whitespace", "(  │ )", "<BS>", "( │ )" },
    { "extra right whitespace", "( │  )", "<BS>", "(│  )" },
    { "tab padding remains native", "(\t│\t)", "<BS>", "(│\t)" },
    { "mismatched delimiter", "(│]", " ", "( │]" },
    { "unmatched prefix", ") (│)", " ", ") ( │)" },
    { "escaped opener", "\\(│)", " ", "\\( │)" },
    { "escaped padded opener", "\\( │ )", "<BS>", "\\(│ )" },
    { "quoted brackets", '"(│)"', " ", '"( │)"' },
    { "quoted padded brackets", '"( │ )"', "<BS>", '"(│ )"' },
    { "line comment", "-- (│)", " ", "-- ( │)" },
    { "comment padding", "-- ( │ )", "<BS>", "-- (│ )" },
    { "non-ASCII whitespace", "(　│　)", "<BS>", "(│　)" },
  }) do
    test("space: " .. case[1], function()
      input(case[2], case[3], case[4], opts)
    end)
  end
  test("space: default setup owns no Space mapping and keeps padded keys native", function()
    input("(│)", " ", "( │)")
    eq(vim.fn.maparg("<Space>", "i"), "")
    input("{ │ }", "<BS>", "{│ }")
    input("{ │ }", "<CR>", "{ \n│}")
  end)
  test("space: open, delete and newline policies remain independent", function()
    input("(│)", " ", "( │ )", { pairs = { ["("] = { space = true, open = false } } })
    input("( │ )", "<BS>", "(│ )", { pairs = { ["("] = { space = true, delete = false } } })
    input("{ │ }", "<CR>", "{ \n│}", { pairs = { ["{"] = { space = true, newline = false } } })
    input("(│)", " ", "( │)", { pairs = { ["("] = false, ["{"] = { space = true } } })
  end)
  test("space: disabled mappings stay native with padding rules configured", function()
    input(
      "(│)",
      " ",
      "( │)",
      vim.tbl_deep_extend("force", opts, { mappings = { space = false } })
    )
    eq(vim.fn.maparg("<Space>", "i"), "")
    input(
      "( │ )",
      "<BS>",
      "(│ )",
      vim.tbl_deep_extend("force", opts, { mappings = { bs = false } })
    )
    input(
      "{ │ }",
      "<CR>",
      "{ \n│}",
      vim.tbl_deep_extend("force", opts, { mappings = { cr = false } })
    )
  end)
  test("space: continuous input, paired Backspace and undo/redo/dot", function()
    input("│", "( <BS><BS>{ <CR>body", "{\n  body│\n}", opts)
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}" })
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}" })
  end)
  test("space: nested brackets reuse the existing nesting scan", function()
    input("│", "([{ <BS>}])", "([{}])│", opts)
    input("([{│}])", " ", "([{ │ }])", opts)
  end)
  test("space: second Backspace removes the remaining empty brackets", function()
    input("( │ )", "<BS><BS>", "│", opts)
  end)
  test("space: declared filetype rules install one global Space mapping", function()
    local ft = { filetypes = { python = { pairs = { ["("] = { space = true } } } } }
    input("(│)", " ", "( │ )", ft, "python")
    eq(vim.fn.maparg("<Space>", "i", false, true).desc, "pairs.nvim <Space>")
    input("(│)", " ", "( │)", ft, "lua")
  end)
  test("space: buffer disable, replacement and removal remain live", function()
    local entry = seed("(│)")
    plugin.setup(opts)
    vim.b.pairs_rules = { ["("] = { space = false } }
    eq(plugin.explain("<Space>", { assume_insert = true }).action, "pass")
    vim.b.pairs_rules = { ["("] = { space = true } }
    eq(plugin.explain(" ", { assume_insert = true }).reason, "empty_pair_space")
    vim.b.pairs_rules = nil
    feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "( │ )")
  end)
  test("space: filetype disable overrides global enable", function()
    local config = vim.tbl_deep_extend("force", opts, {
      filetypes = { python = { pairs = { ["("] = { space = false } } } },
    })
    input("(│)", " ", "( │)", config, "python")
    input("(│)", " ", "( │ )", config, "lua")
  end)
  test("space: scan budget uses the complete cursor position", function()
    input("xx (│)", " ", "xx ( │)", vim.tbl_deep_extend("force", opts, { max_scan_bytes = 3 }))
    input(
      "xx ( │ )",
      "<BS>",
      "xx (│ )",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 4 })
    )
    input("(│)", " ", "( │ )", vim.tbl_deep_extend("force", opts, { max_scan_bytes = 1 }))
  end)
  test("space: booleans and supported bracket shapes validate before setup", function()
    seed("(│)")
    plugin.setup(opts)
    for _, invalid in ipairs({
      { pairs = { ["("] = { space = 1 } } },
      { pairs = { ['"'] = { space = true } } },
      { pairs = { ["<"] = { close = ">", space = true } } },
      { mappings = { space = "yes" } },
    }) do
      eq(pcall(plugin.setup, invalid), false)
      eq(plugin.explain("<Space>", { assume_insert = true }).action, "pair")
    end
    vim.b.pairs_rules = { ["("] = { space = "yes" } }
    eq(plugin.explain("<Space>", { assume_insert = true }).reason, "context_error")
    vim.b.pairs_rules = nil
  end)
  test("space: ordinary insertion and padded removal remain disabled globally", function()
    input("(│)", " ", "( │)", vim.tbl_deep_extend("force", opts, { enabled = false }))
    input("( │ )", "<BS>", "(│ )", vim.tbl_deep_extend("force", opts, { enabled = false }))
  end)
  test("space: existing global mapping is preserved and reported", function()
    local entry = seed("(│)")
    vim.keymap.set("i", "<Space>", "_")
    plugin.setup(opts)
    local ok, err = pcall(function()
      eq(plugin.status().conflicts, { "<Space>" })
      eq(vim.fn.maparg("<Space>", "i", false, true).rhs, "_")
      feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "(_│)")
      plugin.teardown()
      eq(vim.fn.maparg("<Space>", "i", false, true).rhs, "_")
    end)
    vim.keymap.del("i", "<Space>")
    assert(ok, err)
  end)
  test("space: buffer mapping wins over an installed global mapping", function()
    local entry = seed("(│)")
    vim.keymap.set("i", "<Space>", "_", { buffer = true })
    plugin.setup(opts)
    feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "(_│)")
  end)
  test("space: composed Space and Enter fallbacks work without owned mappings", function()
    local entry = seed("{│}")
    plugin.setup(vim.tbl_deep_extend("force", opts, { mappings = { space = false, cr = false } }))
    vim.keymap.set("i", "<F8>", function()
      return plugin.expr("<Space>") or " "
    end, { expr = true, replace_keycodes = false })
    vim.keymap.set("i", "<F9>", function()
      return plugin.expr("<CR>") or require("pairs.mapping").keycode("<CR>")
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      feed(entry .. "<F8><F9>x<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "{\n  x│\n}")
    end)
    vim.keymap.del("i", "<F8>")
    vim.keymap.del("i", "<F9>")
    assert(ok, err)
  end)
  test("space: teardown and re-setup release only owned Space mappings", function()
    seed("│")
    plugin.setup(opts)
    local owned
    for _, mapping in ipairs(require("pairs.mapping").owned) do
      if mapping.lhs == "<Space>" then
        owned = mapping
      end
    end
    assert(owned)
    plugin.setup()
    eq(vim.fn.maparg("<Space>", "i"), "")
    eq(vim.fn.maparg(owned.plug, "i"), "")
    plugin.setup(opts)
    vim.keymap.set("i", "<Space>", "_")
    plugin.teardown()
    eq(vim.fn.maparg("<Space>", "i", false, true).rhs, "_")
    vim.keymap.del("i", "<Space>")
  end)
  test("space: tabs and soft tab stops preserve exact padding removal", function()
    input("\t{ │ }", "<CR>x", "\t{\n\t    x│\n\t}", opts, "lua", {
      expandtab = false,
      shiftwidth = 4,
      softtabstop = 4,
      vartabstop = "4,8",
    })
    input("( │ )", "<BS>", "(│)", opts, "lua", { softtabstop = 4 })
  end)
  test("space: existing indentexpr is evaluated after trimming the padding", function()
    _G.pairs_space_indent = function()
      local line = vim.fn.getline(vim.v.lnum - 1)
      assert(not line:match(" +$"), "padding reached indentexpr")
      return vim.v.lnum == 2 and 4 or 0
    end
    local ok, err = pcall(function()
      input(
        "{ │ }",
        "<CR>x",
        "{\n    x│\n}",
        opts,
        "lua",
        { indentexpr = "v:lua.pairs_space_indent()" }
      )
    end)
    _G.pairs_space_indent = nil
    assert(ok, err)
  end)
  test("space: trace export preserves the policy and trimmed Enter action", function()
    local entry = seed("{│}")
    plugin.setup(opts)
    local trace = require("pairs.trace")
    trace.clear()
    trace.start()
    feed(entry .. " <CR>x<Esc>")
    trace.stop()
    local records = trace.entries()
    eq(#records, 2)
    eq(records[1].decision.reason, "empty_pair_space")
    eq(records[2].decision.trim_space, true)
    eq(records[2].options.filetypes.lua.pairs["{"].space, true)
    local path = vim.fn.tempname()
    trace.export(path)
    local data = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    eq(data.records, records)
    vim.fn.delete(path)
    trace.clear()
  end)
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    test("space: pending syntax keeps native Space and requests one async parse", function()
      local entry = seed("(│)", "python")
      plugin.setup(vim.tbl_deep_extend("force", opts, { treesitter = true }))
      local parser = vim.treesitter.get_parser(0, "python")
      parser:parse(true)
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "()" })
      local original, calls = parser.parse, 0
      parser.parse = function(_, range, callback)
        calls = calls + 1
        eq(type(range), "table")
        eq(type(callback), "function")
        return nil
      end
      local ok, err = pcall(function()
        feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "( │)")
        eq(calls, 1)
      end)
      parser.parse = original
      assert(ok, err)
    end)
    for _, case in ipairs({
      { "python multiline string", 's = """\n(│)\n"""', " ", 's = """\n( │)\n"""', "python" },
      { "rust block comment", "/*\n(│)\n*/", " ", "/*\n( │)\n*/", "rust" },
      { "javascript template body", "`(│)`", " ", "`( │)`", "javascript" },
      { "javascript interpolation boundary", "`${│}`", " ", "`${ │}`", "javascript" },
      { "javascript padded interpolation", "`${ │ }`", "<BS>", "`${│ }`", "javascript" },
      { "python interpolation boundary", 'f"{│}"', " ", 'f"{ │}"', "python" },
      { "javascript expression brackets", "`${fn(│)}`", " ", "`${fn( │ )}`", "javascript" },
      { "python expression brackets", 'f"{fn(│)}"', " ", 'f"{fn( │ )}"', "python" },
    }) do
      test("space: parser protects " .. case[1], function()
        input(
          case[2],
          case[3],
          case[4],
          vim.tbl_deep_extend("force", opts, { treesitter = true }),
          case[5]
        )
      end)
    end
  end
end

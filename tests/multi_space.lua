return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local triple = string.rep('"', 3)
  local function options(open, extra, top)
    return vim.tbl_deep_extend("force", {
      treesitter = true,
      multi_pairs = { [open] = vim.tbl_extend("force", { space = true }, extra or {}) },
    }, top or {})
  end

  test("multi space: default is off and setup does not mutate options", function()
    local config = require("pairs.config")
    eq(
      config.resolve_multi(config.build({ multi_pairs = { [triple] = {} } }), "python")[triple].space,
      false
    )
    local opts = options(triple)
    local original = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, original)
    eq(vim.fn.maparg("<Space>", "i", false, true).desc, "pairs.nvim: Insert paired spacing")
    plugin.setup({ multi_pairs = { [triple] = {} } })
    eq(vim.fn.maparg("<Space>", "i"), "")
  end)
  test("multi space: invalid options preserve setup and buffer errors recover", function()
    seed(triple .. "│" .. triple, "python")
    plugin.setup(options(triple))
    for _, invalid in ipairs({
      { multi_pairs = { [triple] = { space = "yes" } } },
      { filetypes = { tex = { multi_pairs = { ["$$"] = { space = 1 } } } } },
      { multi_pairs = { ["```"] = { space = true } } },
      { multi_pairs = { ["~~~"] = { space = true } } },
    }) do
      eq(pcall(plugin.setup, invalid), false)
      eq(vim.fn.maparg("<Space>", "i", false, true).desc, "pairs.nvim: Insert paired spacing")
    end
    vim.b.pairs_multi_rules = { [triple] = { space = "yes" } }
    eq(plugin.explain("<Space>", { assume_insert = true }).reason, "context_error")
    vim.b.pairs_multi_rules = nil
    assert(plugin.explain("<Space>", { assume_insert = true }).reason ~= "context_error")
  end)
  test("multi space: filetype declarations install Space without single padding", function()
    seed("│")
    plugin.setup({
      filetypes = { python = { multi_pairs = { [triple] = { space = true } } } },
    })
    eq(vim.fn.maparg("<Space>", "i", false, true).desc, "pairs.nvim: Insert paired spacing")
    input("(│)", " ", "( │)", options(triple))
  end)
  test("multi space: existing global and buffer Space owners are preserved", function()
    local entry = seed(triple .. "│" .. triple, "python")
    vim.keymap.set("i", "<Space>", "_")
    local ok, err = pcall(function()
      plugin.setup(options(triple))
      eq(plugin.status().conflicts, { "<Space>" })
      feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, triple .. "_│" .. triple)
      plugin.teardown()
      eq(vim.fn.maparg("<Space>", "i", false, true).rhs, "_")
    end)
    vim.keymap.del("i", "<Space>")
    assert(ok, err)
    entry = seed(triple .. "│" .. triple, "python")
    vim.keymap.set("i", "<Space>", "_", { buffer = true })
    plugin.setup(options(triple))
    feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, triple .. "_│" .. triple)
  end)
  test("multi space: missing or disabled parsers retain ordinary input", function()
    input(
      triple .. "│" .. triple,
      " ",
      triple .. " │" .. triple,
      options(triple),
      "pairs_missing_parser"
    )
    input("\\(│\\)", " ", "\\( │\\)", options("\\(", nil, { treesitter = false }), "tex")
    input("`${│}`", " ", "`${ │}`", options("${", nil, { treesitter = false }), "javascript")
  end)

  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  local families = {
    { "python double", "python", triple, triple, "", "", 0 },
    { "python single", "python", string.rep("'", 3), string.rep("'", 3), "", "", 0 },
    { "python raw", "python", triple, triple, "r", "", 0 },
    { "python f-string", "python", triple, triple, "f", "", 0 },
  }
  for _, ft in ipairs({ "tex", "plaintex" }) do
    for _, delimiters in ipairs({ { "$$", "$$" }, { "\\(", "\\)" }, { "\\[", "\\]" } }) do
      families[#families + 1] = { ft .. delimiters[1], ft, delimiters[1], delimiters[2], "", "", 0 }
    end
  end
  for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
    families[#families + 1] = { ft .. " interpolation", ft, "${", "}", "`", "`", 2 }
  end
  for _, family in ipairs(families) do
    local name, ft, open, close, prefix, suffix, indent = unpack(family)
    local opts = options(open)
    local function marked(body)
      return prefix .. open .. body .. close .. suffix
    end
    local function case(label, before, keys, after, config)
      test("multi space " .. name .. ": " .. label, function()
        input(before, keys, after, config or opts, ft, { softtabstop = 0 })
      end)
    end
    case("pads exactly once", marked("│"), " ", marked(" │ "))
    case("continuous typing pads once", prefix .. "│" .. suffix, open .. " ", marked(" │ "))
    case(
      "continuous typing and deletion",
      prefix .. "│" .. suffix,
      open .. " <BS>",
      marked("│")
    )
    case("removes just the padding", marked(" │ "), "<BS>", marked("│"))
    case("later spaces are ordinary", marked("│"), "   ", marked("   │ "))
    case("extra left space is deleted first", marked("  │ "), "<BS>", marked(" │ "))
    case("extra right spaces remain native", marked(" │  "), "<BS>", marked("│  "))
    case("tabs remain native", marked("\t│\t"), "<BS>", marked("│\t"))
    case("body before cursor stays native", marked("a│"), " ", marked("a │"))
    case("body after cursor stays native", marked("│a"), " ", marked(" │a"))
    case("disabled padding", marked("│"), " ", marked(" │"), options(open, { space = false }))
    case(
      "opening policy is independent",
      marked("│"),
      " ",
      marked(" │ "),
      options(open, { open = false })
    )
    case(
      "deletion policy is independent",
      marked(" │ "),
      "<BS>",
      marked("│ "),
      options(open, { delete = false })
    )
    case(
      "disabled engine",
      marked("│"),
      " ",
      marked(" │"),
      options(open, nil, { enabled = false })
    )
    case(
      "disabled Space mapping",
      marked("│"),
      " ",
      marked(" │"),
      options(open, nil, { mappings = { space = false } })
    )
    case(
      "disabled BS mapping",
      marked(" │ "),
      "<BS>",
      marked("│ "),
      options(open, nil, { mappings = { bs = false } })
    )
    case(
      "scan budget",
      marked("│"),
      " ",
      marked(" │"),
      options(open, nil, { max_scan_bytes = 1 })
    )
    case(
      "second BS removes empty delimiters",
      marked(" │ "),
      "<BS><BS>",
      prefix .. "│" .. suffix
    )
    local newline = open ~= "\\("
    if newline then
      case(
        "trimmed Enter keeps family indentation",
        marked(" │ "),
        "<CR>x",
        prefix .. open .. "\n" .. string.rep(" ", indent) .. "x│\n" .. close .. suffix
      )
    else
      case(
        "inline Enter stays native",
        marked(" │ "),
        "<CR>x",
        prefix .. open .. " \nx│" .. close .. suffix
      )
      case(
        "inline Enter can opt into expansion",
        marked(" │ "),
        "<CR>x",
        prefix .. open .. "\nx│\n" .. close .. suffix,
        options(open, { newline = true })
      )
    end
    case(
      "native Enter comparison",
      marked(" │ "),
      "<CR>x",
      prefix .. open .. " \nx│" .. close .. suffix,
      options(open, { space = false, newline = false })
    )
    case(
      "newline can be disabled",
      marked(" │ "),
      "<CR>x",
      prefix .. open .. " \nx│" .. close .. suffix,
      options(open, { newline = false })
    )
    test("multi space " .. name .. ": live overrides and filetype precedence", function()
      seed(marked("│"), ft)
      plugin.setup(
        options(
          open,
          nil,
          { filetypes = { [ft] = { multi_pairs = { [open] = { space = false } } } } }
        )
      )
      eq(plugin.explain("<Space>", { assume_insert = true }).action, "pass")
      vim.b.pairs_multi_rules = { [open] = { space = true } }
      eq(plugin.explain("<Space>", { assume_insert = true }).reason, "empty_multi_space")
      vim.b.pairs_multi_rules = { [open] = { space = false } }
      eq(plugin.explain("<Space>", { assume_insert = true }).action, "pass")
      vim.b.pairs_multi_rules = nil
      eq(plugin.explain("<Space>", { assume_insert = true }).action, "pass")
    end)
  end

  for _, boundary in ipairs({
    { "python", "python", triple, triple .. "│" .. triple, triple .. " │" .. triple },
    { "javascript", "javascript", "${", "`${│}`", "`${ │}`" },
    { "tex", "latex", "\\(", "\\(│\\)", "\\( │\\)" },
  }) do
    test(
      "multi space: pending " .. boundary[1] .. " syntax requests only an async parse",
      function()
        local entry = seed(boundary[4], boundary[1])
        plugin.setup(options(boundary[3]))
        local parser = vim.treesitter.get_parser(0, boundary[2])
        parser:parse(true)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { (boundary[4]:gsub("│", "")) })
        local original, calls = parser.parse, 0
        parser.parse = function(_, range, callback)
          calls = calls + 1
          eq(type(range), "table")
          eq(type(callback), "function")
          return nil
        end
        local ok, err = pcall(function()
          feed(entry .. " <Cmd>lua pairs_test_capture()<CR><Esc>")
          eq(_G.pairs_test_result, boundary[5])
          eq(calls, 1)
        end)
        parser.parse = original
        assert(ok, err)
      end
    )
  end
  for _, case in ipairs({
    { "Python comment", "python", triple, '# """│"""', '# """ │"""' },
    { "Python incomplete triple", "python", triple, '"""│', '""" │' },
    { "JS literal template", "javascript", "${", "`\\${│}`", "`\\${ │}`" },
    { "JS comment", "javascript", "${", "// `${│}`", "// `${ │}`" },
    { "JS quoted literal", "javascript", "${", "'${│}'", "'${ │}'" },
    { "JS incomplete interpolation", "javascript", "${", "`${│", "`${ │" },
    { "TeX comment", "tex", "\\(", "% \\(│\\)", "% \\( │\\)" },
    { "TeX raw argument", "tex", "\\(", "\\url{\\(│\\)}", "\\url{\\( │\\)}" },
    {
      "TeX verbatim",
      "tex",
      "\\(",
      "\\begin{verbatim}\n\\(│\\)\n\\end{verbatim}",
      "\\begin{verbatim}\n\\( │\\)\n\\end{verbatim}",
    },
    {
      "TeX unknown environment",
      "tex",
      "\\(",
      "\\begin{unknown}\n\\(│\\)\n\\end{unknown}",
      "\\begin{unknown}\n\\( │\\)\n\\end{unknown}",
    },
    { "TeX incomplete math", "tex", "\\(", "\\(│", "\\( │" },
    { "TeX multiline math", "tex", "$$", "$$\n│\n$$", "$$\n │\n$$" },
  }) do
    test("multi space: " .. case[1] .. " stays native", function()
      input(case[4], " ", case[5], options(case[3]), case[2])
    end)
  end
  test("multi space: unrelated single bracket padding remains independent", function()
    local single = { pairs = { ["("] = { space = true } } }
    input("(│)", " ", "( │ )", options("\\(", nil, single), "tex")
    input("`${fn(│)}`", " ", "`${fn( │ )}`", options("${", nil, single), "javascript")
  end)
  test("multi space: typed math retains undo redo and dot repeat", function()
    input("│", "\\[ <CR>x", "\\[\nx│\n\\]", options("\\["), "tex")
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "\\[", "x", "\\]" })
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "\\[", "x", "\\]" })
  end)
  test("multi space: composed Space uses the multi rule without owning Space", function()
    local entry = seed("\\(│\\)", "tex")
    plugin.setup(options("\\(", nil, { mappings = { space = false } }))
    vim.keymap.set("i", "<F8>", function()
      return plugin.expr("<Space>") or " "
    end, { expr = true, replace_keycodes = false })
    local ok, err = pcall(function()
      feed(entry .. "<F8><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "\\( │ \\)")
    end)
    vim.keymap.del("i", "<F8>")
    assert(ok, err)
  end)
  test("multi space: trace export retains padding policy and trimmed Enter", function()
    local entry = seed("\\[│\\]", "tex")
    plugin.setup(options("\\["))
    local trace = require("pairs.trace")
    trace.clear()
    trace.start()
    feed(entry .. " <CR>x<Esc>")
    trace.stop()
    local records = trace.entries()
    eq(records[1].decision.reason, "empty_multi_space")
    eq(records[1].options.filetypes.tex.multi_pairs["\\["].space, true)
    eq(records[2].decision.trim_space, true)
    local path = vim.fn.tempname()
    trace.export(path)
    local exported = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    eq(exported.records, records)
    vim.fn.delete(path)
    trace.clear()
  end)
end

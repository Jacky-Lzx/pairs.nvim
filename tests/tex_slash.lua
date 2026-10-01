return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local math_rules = { ["\\("] = {}, ["\\["] = {} }
  local opts = {
    treesitter = true,
    filetypes = {
      tex = { multi_pairs = math_rules },
      plaintex = { multi_pairs = vim.deepcopy(math_rules) },
    },
  }
  local function options(open, rule)
    local copy = vim.deepcopy(opts)
    copy.filetypes.tex.multi_pairs[open] = rule
    return copy
  end
  local function case(label, before, keys, after, config, ft, bo)
    test("tex slash: " .. label, function()
      input(before, keys, after, config or opts, ft or "tex", bo)
    end)
  end
  test("tex slash: defaults and immutable options", function()
    local original = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, original)
    local config = require("pairs.config")
    local rules = config.resolve_multi(config.build(opts), "tex")
    eq(rules["\\("], { close = "\\)", open = true, skip = true, delete = true, newline = false })
    eq(rules["\\["], { close = "\\]", open = true, skip = true, delete = true, newline = true })
    eq(vim.fn.maparg("\\", "i", false, true).desc, "pairs.nvim \\")
    eq(vim.fn.maparg("<Tab>", "i"), "")
  end)
  test("tex slash: invalid closer keeps existing setup", function()
    plugin.setup(opts)
    eq(pcall(plugin.setup, options("\\(", { close = ")" })), false)
    eq(vim.fn.maparg("\\", "i", false, true).desc, "pairs.nvim \\")
  end)
  test("tex slash: existing backslash mapping is preserved", function()
    plugin.teardown()
    vim.keymap.set("i", "\\", "\\", { desc = "user backslash" })
    plugin.setup(opts)
    eq(vim.fn.maparg("\\", "i", false, true).desc, "user backslash")
    assert(vim.tbl_contains(plugin.status().conflicts, "\\"))
    plugin.teardown()
    eq(vim.fn.maparg("\\", "i", false, true).desc, "user backslash")
    vim.keymap.del("i", "\\")
  end)
  case("default opt-out", "│", "\\(", "\\(│", { treesitter = true })
  case(
    "Tree-sitter required",
    "│",
    "\\[",
    "\\[│",
    vim.tbl_deep_extend("force", opts, { treesitter = false })
  )
  case("other filetype native backslash", "│", "\\x", "\\x│", opts, "lua")
  case("ordinary brackets stay paired", "│", "(x)", "(x)│")
  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  for _, open in ipairs({ "\\(", "\\[" }) do
    local close = open == "\\(" and "\\)" or "\\]"
    local char = open:sub(-1)
    local ending = close:sub(-1)
    case(open .. " continuous opening", "│", open, open .. "│" .. close)
    case(open .. " existing prefix", "\\│", char, open .. "│" .. close)
    case(
      open .. " prose opening",
      "你好 word \\│",
      char,
      "你好 word " .. open .. "│" .. close
    )
    case(open .. " before whitespace", "\\│ ", char, open .. "│" .. close .. " ")
    case(
      open .. " continuous formula",
      "│",
      open .. "x^2" .. close,
      open .. "x^2" .. close .. "│"
    )
    case(open .. " skip backslash", open .. "x│" .. close, "\\", open .. "x\\│" .. ending)
    case(
      open .. " skip final character",
      open .. "x\\│" .. ending,
      ending,
      open .. "x" .. close .. "│"
    )
    case(
      open .. " multiline closing",
      open .. "\nx\n│" .. close,
      close,
      open .. "\nx\n" .. close .. "│"
    )
    case(
      open .. " prime does not hide closer",
      open .. "x'│" .. close,
      close,
      open .. "x'" .. close .. "│"
    )
    case(
      open .. " missing backslash is literal",
      open .. "x│" .. close,
      ending,
      open .. "x" .. ending .. "│" .. close
    )
    case(open .. " delete empty", open .. "│" .. close, "<BS>", "│")
    case(open .. " delete body only", open .. "x│" .. close, "<BS>", open .. "│" .. close)
    case(open .. " escaped prefix", "\\\\│", char, "\\\\" .. char .. "│")
    case(
      open .. " new command after line break",
      "\\\\\\│",
      char,
      "\\\\" .. open .. "│" .. close
    )
    case(open .. " content to right prevents opening", "\\│name", char, open .. "│name")
    case(open .. " comment opening", "% \\│", char, "% " .. open .. "│")
    case(
      open .. " escaped percent permits opening",
      "\\% \\│",
      char,
      "\\% " .. open .. "│" .. close
    )
    case(open .. " inline math prevents nesting", "$x \\│ $", char, "$x " .. open .. "│ $")
    case(
      open .. " display math prevents nesting",
      "$$\n\\│\n$$",
      char,
      "$$\n" .. open .. "│\n$$"
    )
    case(
      open .. " equation environment prevents nesting",
      "\\begin{equation}\n\\│\n\\end{equation}",
      char,
      "\\begin{equation}\n" .. open .. "│\n\\end{equation}"
    )
    case(
      open .. " unknown environment is conservative",
      "\\begin{custommath}\n\\│\n\\end{custommath}",
      char,
      "\\begin{custommath}\n" .. open .. "│\n\\end{custommath}"
    )
    case(
      open .. " unknown environment closing stays native",
      "\\begin{custommath}\n" .. open .. "x│" .. close .. "\n\\end{custommath}",
      close,
      "\\begin{custommath}\n" .. open .. "x" .. close .. "│" .. close .. "\n\\end{custommath}"
    )
    case(
      open .. " recovered math environment closing stays native",
      "\\begin{equation}\n" .. open .. "x│" .. close .. "\n\\end{broken}",
      close,
      "\\begin{equation}\n" .. open .. "x" .. close .. "│" .. close .. "\n\\end{broken}"
    )
    case(
      open .. " unfinished math delimiter is conservative",
      "\\[\n\\│",
      char,
      "\\[\n" .. open .. "│"
    )
    case(
      open .. " nested formula closer is literal",
      "$$ " .. open .. "x│" .. close .. " $$",
      close,
      "$$ " .. open .. "x" .. close .. "│" .. close .. " $$"
    )
    case(
      open .. " full document",
      "\\begin{document}\n│\n\\end{document}",
      open .. "x" .. close,
      "\\begin{document}\n" .. open .. "x" .. close .. "│\n\\end{document}"
    )
    case(
      open .. " unfinished document",
      "\\begin{document}\n\\│",
      char,
      "\\begin{document}\n" .. open .. "│" .. close
    )
    for _, env in ipairs({ "verbatim", "lstlisting", "minted", "comment" }) do
      local begin = "\\begin{" .. env .. "}" .. (env == "minted" and "{tex}" or "") .. "\n"
      local finish = "\n\\end{" .. env .. "}"
      case(
        open .. " " .. env .. " opening stays literal",
        begin .. "\\│" .. finish,
        char,
        begin .. open .. "│" .. finish
      )
      case(
        open .. " " .. env .. " closing stays literal",
        begin .. open .. "x│" .. close .. finish,
        close,
        begin .. open .. "x" .. close .. "│" .. close .. finish
      )
    end
    case(open .. " verb is literal", "\\verb|\\│|", char, "\\verb|" .. open .. "│|")
    case(
      open .. " verb does not delete empty pair",
      "\\verb|" .. open .. "│" .. close .. "|",
      "<BS>",
      "\\verb|\\│" .. close .. "|"
    )
    case(open .. " opening disabled", "│", open, open .. "│", options(open, { open = false }))
    case(
      open .. " skip disabled",
      open .. "x│" .. close,
      close,
      open .. "x" .. close .. "│" .. close,
      options(open, { skip = false })
    )
    case(
      open .. " delete disabled",
      open .. "│" .. close,
      "<BS>",
      "\\│" .. close,
      options(open, { delete = false })
    )
    case(open .. " rule disabled", "│", open, open .. "│", options(open, false))
    case(
      open .. " opening disabled keeps skip",
      open .. "x│" .. close,
      close,
      open .. "x" .. close .. "│",
      options(open, { open = false })
    )
    case(
      open .. " pending parser remains native",
      "  \\│",
      char,
      "  " .. open .. "│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 2 })
    )
  end
  case("plaintex parser alias", "│", "\\(x\\)", "\\(x\\)│", nil, "plaintex")
  case("ordinary backslash command", "│", "\\alpha", "\\alpha│")
  case("ordinary plain parentheses in formula", "│", "\\(f(x)\\)", "\\(f(x)\\)│")
  case("inline Enter stays native", "\\(│\\)", "<CR>", "\\(\n│\\)")
  case("display Enter expands", "│", "\\[<CR>x^2", "\\[\nx^2│\n\\]")
  case("display Enter preserves indent", "  \\[│\\]", "<CR>x", "  \\[\n  x│\n  \\]")
  case(
    "display Enter preserves tabs",
    "\t\\[│\\]",
    "<CR>x",
    "\t\\[\n\tx│\n\t\\]",
    nil,
    nil,
    { expandtab = false, softtabstop = 2 }
  )
  case(
    "display Enter ignores indent shift",
    "  \\[│\\]",
    "<CR>x",
    "  \\[\n  x│\n  \\]",
    nil,
    nil,
    { indentexpr = "8" }
  )
  case("nonempty display Enter stays native", "\\[x│\\]", "<CR>", "\\[x\n│\\]")
  case("newline disabled", "\\[│\\]", "<CR>", "\\[\n│\\]", options("\\[", { newline = false }))
  case(
    "inline newline explicit opt-in",
    "\\(│\\)",
    "<CR>x",
    "\\(\nx│\n\\)",
    options("\\(", { newline = true })
  )
  case("mixed delimiters do not skip", "\\(x│\\]", "\\]", "\\(x\\]│\\]")
  test("tex slash: undo redo and dot retain full display", function()
    input("│", "\\[<CR>x^2", "\\[\nx^2│\n\\]", opts, "tex")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    feed("u")
    eq(vim.api.nvim_get_current_line(), "")
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
  end)
  test("tex slash: undo and dot retain both closing skips", function()
    for _, open in ipairs({ "\\(", "\\[" }) do
      local close = open == "\\(" and "\\)" or "\\]"
      input("│", open .. "x" .. close, open .. "x" .. close .. "│", opts, "tex")
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
      feed("<C-r>")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
      feed("u.")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
    end
  end)
  test("tex slash: missing parser does not edit delimiters", function()
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function()
      return nil
    end
    local ok, err = pcall(function()
      input("\\│", "(", "\\(│", opts, "tex")
      input("\\[│\\]", "<BS>", "\\│\\]", opts, "tex")
      input("\\(x│\\)", "\\)", "\\(x\\)│\\)", opts, "tex")
    end)
    vim.treesitter.get_parser = original
    assert(ok, err)
  end)
  test("tex slash: stale tree never invents an opening", function()
    seed("\\│ ", "tex")
    plugin.setup(opts)
    local parser = vim.treesitter.get_parser(0, "latex")
    parser:parse(true)
    eq(plugin.explain("(", { assume_insert = true }).action, "pair")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "\\ " })
    local original = parser.parse
    parser.parse = function(_, range, callback)
      assert(type(range) == "table" and type(callback) == "function", "forced synchronous parse")
      return nil
    end
    local ok, err = pcall(function()
      eq(plugin.explain("(", { assume_insert = true }).action, "pass")
    end)
    parser.parse = original
    assert(ok, err)
  end)
  test("tex slash: stale closer is never skipped", function()
    seed("\\(x│\\)", "tex")
    plugin.setup(opts)
    local parser = vim.treesitter.get_parser(0, "latex")
    parser:parse(true)
    eq(plugin.explain("\\", { assume_insert = true }).action, "skip")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "\\(x\\)" })
    local original = parser.parse
    parser.parse = function()
      return nil
    end
    local ok, err = pcall(function()
      eq(plugin.explain("\\", { assume_insert = true }).action, "pass")
    end)
    parser.parse = original
    assert(ok, err)
  end)
end

return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = {
    treesitter = true,
    filetypes = {
      tex = { multi_pairs = { ["$$"] = {} } },
      plaintex = { multi_pairs = { ["$$"] = {} } },
    },
  }
  local function options(rule)
    local copy = vim.deepcopy(opts)
    copy.filetypes.tex.multi_pairs["$$"] = rule
    return copy
  end
  local function case(label, before, keys, after, config, ft, bo)
    test("tex: " .. label, function()
      input(before, keys, after, config or opts, ft or "tex", bo)
    end)
  end
  test("tex: defaults and immutable setup", function()
    local original = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, original)
    local config = require("pairs.config")
    eq(
      config.resolve_multi(config.build(opts), "tex")["$$"],
      { close = "$$", open = true, skip = true, delete = true, newline = true }
    )
    eq(vim.fn.maparg("$", "i", false, true).desc, "pairs.nvim $")
  end)
  test("tex: invalid closer rejected", function()
    eq(pcall(plugin.setup, options({ close = "$" })), false)
  end)
  case("default opt-out", "│", "$$", "$$│", { treesitter = true })
  case(
    "Tree-sitter required",
    "│",
    "$$",
    "$$│",
    vim.tbl_deep_extend("force", opts, { treesitter = false })
  )
  case("other filetype stays native", "│", "$$", "$$│", opts, "markdown")
  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  case("first dollar remains literal", "│", "$", "$│")
  case("second dollar upgrades", "│", "$$", "$$│$$")
  for _, env in ipairs({ "document", "center", "itemize", "figure*", "minipage" }) do
    local opening = "\\begin{" .. env .. "}" .. (env == "minipage" and "{\\textwidth}" or "")
    local ending = "\n\\end{" .. env .. "}"
    case(env .. " opening", opening .. "\n│" .. ending, "$$", opening .. "\n$$│$$" .. ending)
  end
  case(
    "complete document with previous text and formula",
    "\\documentclass{article}\n\\begin{document}\nText $x$.\n│\n\\end{document}",
    "$$<CR>x^2",
    "\\documentclass{article}\n\\begin{document}\nText $x$.\n$$\nx^2│\n$$\n\\end{document}"
  )
  case(
    "document display deletion",
    "\\begin{document}\n$$│$$\n\\end{document}",
    "<BS>",
    "\\begin{document}\n│\n\\end{document}"
  )
  case(
    "document display closing",
    "\\begin{document}\n$$x│$$\n\\end{document}",
    "$$",
    "\\begin{document}\n$$x$$│\n\\end{document}"
  )
  case(
    "unknown environment recovery stays native",
    "\\begin{custommath}\n$│\n\\end{custommath}",
    "$",
    "\\begin{custommath}\n$$│\n\\end{custommath}"
  )
  case(
    "unknown environment closing stays native",
    "\\begin{custommath}\n$$x│$$\n\\end{custommath}",
    "$$",
    "\\begin{custommath}\n$$x$$│$$\n\\end{custommath}"
  )
  case(
    "unfinished verbatim remains literal",
    "\\begin{verbatim}\n$│",
    "$",
    "\\begin{verbatim}\n$$│"
  )
  case(
    "nested math environment remains literal",
    "\\begin{document}\n\\begin{align*}\n$│\n\\end{align*}\n\\end{document}",
    "$",
    "\\begin{document}\n\\begin{align*}\n$$│\n\\end{align*}\n\\end{document}"
  )
  local long_prefix = "\\begin{document}\n" .. string.rep("\\foo{}\n", 300)
  case(
    "large error recovery stays bounded",
    long_prefix .. "$│\n\\end{document}",
    "$",
    long_prefix .. "$$│\n\\end{document}"
  )
  case("existing single dollar", "$│", "$", "$$│$$")
  case("plaintex alias", "│", "$$", "$$│$$", nil, "plaintex")
  case("continuous formula and closers", "│", "$$x^2$$", "$$x^2$$│")
  case("first closing character", "$$x│$$", "$", "$$x$│$")
  case("second closing character", "$$x$│$", "$", "$$x$$│")
  case("multiline closing", "$$\nx^2\n│$$", "$$", "$$\nx^2\n$$│")
  case("prime does not mask math closing", "$$x'│$$", "$$", "$$x'$$│")
  case("display at line start with indent", "  │", "$$", "  $$│$$")
  case("opening before whitespace", "$│  ", "$", "$$│$$  ")
  case("inline text is not upgraded", "cost $│", "$", "cost $$│")
  case("next content prevents opening", "$│x", "$", "$$│x")
  case("inline pair is not upgraded", "$│$", "$", "$$│$")
  case("inline closing remains literal", "$x│$", "$", "$x$│$")
  case("escaped dollar remains literal", "\\$│", "$", "\\$$│")
  case("comment remains literal", "% $│", "$", "% $$│")
  case("escaped percent is not a comment at display closer", "$$\\%│$$", "$$", "$$\\%$$│")
  case("comment dollar is not skipped", "$$x % │$$\n$$", "$$", "$$x % $$│$$\n$$")
  case("delete empty display", "$$│$$", "<BS>", "│")
  case("delete body only", "$$x│$$", "<BS>", "$$│$$")
  case("Enter empty display", "$$│$$", "<CR>body", "$$\nbody│\n$$")
  case("continuous Enter", "│", "$$<CR>body", "$$\nbody│\n$$")
  case("Enter indentation", "  $$│$$", "<CR>body", "  $$\n  body│\n  $$")
  case(
    "literal tab indentation",
    "\t$$│$$",
    "<CR>body",
    "\t$$\n\tbody│\n\t$$",
    nil,
    nil,
    { expandtab = false, softtabstop = 2 }
  )
  case(
    "ignore language indent shift",
    "  $$│$$",
    "<CR>body",
    "  $$\n  body│\n  $$",
    nil,
    nil,
    { indentexpr = "8" }
  )
  case("ordinary Enter in nonempty display", "$$x│$$", "<CR>", "$$x\n│$$")
  case("unclosed display does not manufacture close", "$$│", "<CR>", "$$\n│")
  case("unclosed display body does not upgrade", "$$\n$│", "$", "$$\n$$│")
  case("inline math from previous line does not upgrade", "$x\n$│", "$", "$x\n$$│")
  case("bracket math from previous line does not upgrade", "\\[\n$│\n\\]", "$", "\\[\n$$│\n\\]")
  case(
    "equation environment does not upgrade",
    "\\begin{equation}\n$│\n\\end{equation}",
    "$",
    "\\begin{equation}\n$$│\n\\end{equation}"
  )
  case("nested display closer is native", "\\[ $$x│$$ \\]", "$$", "\\[ $$x$$│$$ \\]")
  case("mismatched display closer is native", "\\[ x│$$", "$$", "\\[ x$$│$$")
  case("extra dollar is literal after display", "$$x$$│", "$", "$$x$$$│")
  for _, env in ipairs({ "verbatim", "lstlisting", "minted", "comment" }) do
    local begin = "\\begin{" .. env .. "}" .. (env == "minted" and "{tex}" or "")
    case(
      env .. " does not upgrade",
      begin .. "\n$│\n\\end{" .. env .. "}",
      "$",
      begin .. "\n$$│\n\\end{" .. env .. "}"
    )
    case(
      env .. " does not skip",
      begin .. "\n$$x│$$\n\\end{" .. env .. "}",
      "$$",
      begin .. "\n$$x$$│$$\n\\end{" .. env .. "}"
    )
    case(
      env .. " does not delete pair",
      begin .. "\n$$│$$\n\\end{" .. env .. "}",
      "<BS>",
      begin .. "\n$│$$\n\\end{" .. env .. "}"
    )
  end
  case("verb is literal", "\\verb|$$x│$$|", "$$", "\\verb|$$x$$│$$|")
  case("escaped verb command does not mask closing", "$$\\\\verb x│$$", "$$", "$$\\\\verb x$$│")
  case("verb star is literal", "\\verb*+$$│$$+", "<BS>", "\\verb*+$│$$+")
  case("unfinished verb is literal", "\\verb|$$x│$$", "$$", "\\verb|$$x$$│$$")
  case("lstinline is literal", "\\lstinline|$$x│$$|", "$$", "\\lstinline|$$x$$│$$|")
  case(
    "mintinline is literal",
    "\\mintinline{tex}|$$x│$$|",
    "$$",
    "\\mintinline{tex}|$$x$$│$$|"
  )
  case(
    "completed verb does not block following display",
    "\\verb|text| $$x│$$",
    "$$",
    "\\verb|text| $$x$$│"
  )
  case("opening disabled", "│", "$$", "$$│", options({ open = false }))
  case("skip disabled", "$$x│$$", "$", "$$x$│$$", options({ skip = false }))
  case("delete disabled", "$$│$$", "<BS>", "$│$$", options({ delete = false }))
  case("newline disabled", "$$│$$", "<CR>", "$$\n│$$", options({ newline = false }))
  case("rule disabled", "│", "$$", "$$│", options(false))
  case(
    "scan limit",
    "  $│",
    "$",
    "  $$│",
    vim.tbl_deep_extend("force", opts, { max_scan_bytes = 2 })
  )
  test("tex: buffer override", function()
    local entry = seed("$│", "tex")
    plugin.setup(opts)
    vim.b.pairs_multi_rules = { ["$$"] = { open = false } }
    feed(entry .. "$<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "$$│")
  end)
  test("tex: native undo redo and dot", function()
    input("│", "$$<CR>body", "$$\nbody│\n$$", opts, "tex")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    feed("u")
    eq(vim.api.nvim_get_current_line(), "")
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
  end)
  test("tex: missing parser stays native", function()
    local entry = seed("$│", "tex")
    plugin.setup(opts)
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function()
      return nil
    end
    local ok, err = pcall(function()
      feed(entry .. "$<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "$$│")
    end)
    vim.treesitter.get_parser = original
    assert(ok, err)
  end)
  test("tex: stale parser is never used", function()
    seed("$$│$$", "tex")
    plugin.setup(opts)
    local parser = vim.treesitter.get_parser(0, "latex")
    parser:parse(true)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "$$$$" })
    local original = parser.parse
    parser.parse = function()
      return nil
    end
    local ok, err = pcall(function()
      eq(plugin.explain("<BS>", { assume_insert = true }).action, "pass")
    end)
    parser.parse = original
    assert(ok, err)
  end)
end

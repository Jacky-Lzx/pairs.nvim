return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = {
    treesitter = true,
    tex_environments = {
      proof = "text",
      abstract = "text",
      theorem = "text",
      ["theorem*"] = "text",
      mymath = "math",
      mycode = "literal",
    },
    multi_pairs = { ["$$"] = {}, ["\\("] = {}, ["\\["] = {} },
  }
  local function wrap(env, text, ending)
    return "\\begin{"
      .. env
      .. "}\n"
      .. text
      .. (ending == false and "" or "\n\\end{" .. env .. "}")
  end
  local function case(label, before, keys, after, config, ft)
    test("tex environments: " .. label, function()
      input(before, keys, after, config or opts, ft or "tex")
    end)
  end
  test("tex environments: immutable defaults and setup", function()
    local defaults = vim.deepcopy(require("pairs.config").defaults)
    local original = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, original)
    eq(require("pairs.config").defaults, defaults)
    eq(defaults.tex_environments.proof, nil)
    eq(defaults.tex_environments.document, "text")
    eq(defaults.tex_environments.equation, "math")
    eq(defaults.tex_environments.verbatim, "literal")
  end)
  test("tex environments: global filetype buffer precedence", function()
    local config = require("pairs.config")
    local build = config.build({
      tex_environments = { proof = "math" },
      filetypes = { tex = { tex_environments = { proof = "text" } } },
    })
    eq(config.resolve_tex(build, "tex").proof, "text")
    eq(config.resolve_tex(build, "plaintex").proof, "math")
    eq(config.resolve_tex(build, "tex", { proof = "literal" }).proof, "literal")
    eq(config.resolve_tex(build, "tex", { proof = false }).proof, false)
  end)
  for _, invalid in ipairs({
    { tex_environments = false },
    { tex_environments = { proof = true } },
    { tex_environments = { proof = "code" } },
    { tex_environments = { ["bad name"] = "text" } },
    { tex_environments = { ["\\proof"] = "text" } },
    { tex_environments = { [string.rep("p", 63)] = "text" } },
    { tex_environments = { equation = "text" } },
    { tex_environments = { minted = "math" } },
    { tex_environments = { verbatim = false } },
    { filetypes = { tex = { tex_environments = { proof = "invalid" } } } },
    { filetypes = { tex = { tex_environments = false } } },
  }) do
    test("tex environments: reject " .. vim.inspect(invalid), function()
      plugin.setup(opts)
      eq(pcall(plugin.setup, invalid), false)
      eq(vim.fn.maparg("$", "i", false, true).desc, "pairs.nvim: Insert or skip paired delimiter $")
    end)
  end
  test("tex environments: declarations do not enable math rules", function()
    plugin.setup({ treesitter = true, tex_environments = { proof = "text" } })
    eq(vim.fn.maparg("$", "i"), "")
    eq(vim.fn.maparg("\\", "i"), "")
  end)
  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  for _, mode in ipairs({ "text", "math", "literal" }) do
    case(
      "standalone " .. mode .. " declaration at unfinished EOF",
      wrap("myenv", "│", false),
      "$$",
      wrap("myenv", "$$│" .. (mode == "text" and "$$" or ""), false),
      {
        treesitter = true,
        tex_environments = { myenv = mode },
        multi_pairs = { ["$$"] = {} },
      }
    )
  end
  for _, open in ipairs({ "$$", "\\(", "\\[" }) do
    local close = ({ ["$$"] = "$$", ["\\("] = "\\)", ["\\["] = "\\]" })[open]
    for _, env in ipairs({ "proof", "abstract", "theorem", "theorem*" }) do
      case(
        env .. " " .. open .. " continuous formula",
        wrap(env, "│"),
        open .. "x" .. close,
        wrap(env, open .. "x" .. close .. "│")
      )
    end
    case(
      open .. " complete text environment closing",
      wrap("proof", open .. "x│" .. close),
      close,
      wrap("proof", open .. "x" .. close .. "│")
    )
    case(
      open .. " empty pair deletion",
      wrap("proof", open .. "│" .. close),
      "<BS>",
      wrap("proof", "│")
    )
    case(
      open .. " unfinished text environment opening",
      wrap("proof", "│", false),
      open,
      wrap("proof", open .. "│" .. close, false)
    )
    case(
      open .. " unfinished text environment closing",
      wrap("proof", open .. "x│" .. close, false),
      close,
      wrap("proof", open .. "x" .. close .. "│", false)
    )
    case(
      open .. " math environment prevents opening",
      wrap("mymath", "│"),
      open,
      wrap("mymath", open .. "│")
    )
    case(
      open .. " math environment prevents closing skip",
      wrap("mymath", open .. "x│" .. close),
      close,
      wrap("mymath", open .. "x" .. close .. "│" .. close)
    )
    case(
      open .. " math environment prevents pair deletion",
      wrap("mymath", open .. "│" .. close),
      "<BS>",
      wrap("mymath", open:sub(1, -2) .. "│" .. close)
    )
    case(
      open .. " unfinished math environment prevents opening",
      wrap("mymath", "│", false),
      open,
      wrap("mymath", open .. "│", false)
    )
    case(
      open .. " literal environment prevents opening",
      wrap("mycode", "│"),
      open,
      wrap("mycode", open .. "│")
    )
    case(
      open .. " literal environment prevents closing skip",
      wrap("mycode", open .. "x│" .. close),
      close,
      wrap("mycode", open .. "x" .. close .. "│" .. close)
    )
    case(
      open .. " literal environment prevents pair deletion",
      wrap("mycode", open .. "│" .. close),
      "<BS>",
      wrap("mycode", open:sub(1, -2) .. "│" .. close)
    )
    case(
      open .. " unknown environment stays conservative",
      wrap("unknown", "│"),
      open,
      wrap("unknown", open .. "│")
    )
    case(
      open .. " nested text in math is still math",
      wrap("mymath", wrap("proof", "│")),
      open,
      wrap("mymath", wrap("proof", open .. "│"))
    )
    case(
      open .. " nested text in literal is still literal",
      wrap("mycode", wrap("proof", "│")),
      open,
      wrap("mycode", wrap("proof", open .. "│"))
    )
    case(
      open .. " nested literal in text is literal",
      wrap("proof", wrap("mycode", "│")),
      open,
      wrap("proof", wrap("mycode", open .. "│"))
    )
    case(
      open .. " completed inner code does not leak",
      wrap("proof", wrap("mycode", "code") .. "\n│"),
      open,
      wrap("proof", wrap("mycode", "code") .. "\n" .. open .. "│" .. close)
    )
    case(
      open .. " completed inner math does not leak",
      wrap("proof", wrap("mymath", "x") .. "\n│", false),
      open,
      wrap("proof", wrap("mymath", "x") .. "\n" .. open .. "│" .. close, false)
    )
    case(
      open .. " incomplete begin header stays native",
      "\\begin{proof\n│",
      open,
      "\\begin{proof\n" .. open .. "│"
    )
  end
  case(
    "display Enter in proof",
    wrap("proof", "  │"),
    "\\[<CR>x",
    wrap("proof", "  \\[\n  x│\n  \\]")
  )
  case("dollar Enter in proof", wrap("proof", "│"), "$$<CR>x", wrap("proof", "$$\nx│\n$$"))
  case("literal ordinary quote", wrap("mycode", "│"), '"', wrap("mycode", '"│'))
  case("literal ordinary bracket", wrap("mycode", "│"), "(", wrap("mycode", "(│"))
  case("literal basic empty pair deletion", wrap("mycode", "(│)"), "<BS>", wrap("mycode", "│)"))
  case(
    "literal basic Enter stays native",
    wrap("mycode", "{│}"),
    "<CR>",
    wrap("mycode", "{\n│}")
  )
  case("math still allows ordinary brackets", wrap("mymath", "│"), "(", wrap("mymath", "(│)"))
  case("text still allows ordinary brackets", wrap("proof", "│"), "(", wrap("proof", "(│)"))
  case(
    "literal dominates nested unknown for ordinary bracket",
    wrap("mycode", wrap("unknown", "│")),
    "(",
    wrap("mycode", wrap("unknown", "(│"))
  )
  case(
    "unfinished literal protects ordinary brackets",
    wrap("mycode", "│", false),
    "(",
    wrap("mycode", "(│", false)
  )
  case(
    "broken raw dollar body stays literal",
    wrap("mycode", "$\n│", false),
    "(",
    wrap("mycode", "$\n(│", false)
  )
  case(
    "broken raw bracket body stays literal",
    wrap("mycode", "\\[\n│", false),
    '"',
    wrap("mycode", '\\[\n"│', false)
  )
  case(
    "text EOF ordinary brackets",
    wrap("proof", "│", false),
    "(",
    wrap("proof", "(│)", false)
  )
  case(
    "literal wrong end is still raw",
    "\\begin{mycode}\n\\end{proof}\n│",
    '("',
    '\\begin{mycode}\n\\end{proof}\n("│'
  )
  case(
    "literal own end restores ordinary pairing",
    wrap("mycode", "code") .. "\n│",
    "(",
    wrap("mycode", "code") .. "\n(│)"
  )
  case(
    "literal own end at same line restores pairing",
    wrap("mycode", "code") .. "│",
    "(",
    wrap("mycode", "code") .. "(│)"
  )
  case(
    "raw dollar before code end does not leak",
    wrap("mycode", "$\ncode") .. "\n│",
    "(",
    wrap("mycode", "$\ncode") .. "\n(│)"
  )
  case(
    "raw bracket before code end does not leak",
    wrap("mycode", "\\[\ncode") .. "\n│",
    '"',
    wrap("mycode", "\\[\ncode") .. '\n"│"'
  )
  case(
    "raw dollar before code end permits following math",
    wrap("proof", wrap("mycode", "$\ncode") .. "\n│"),
    "\\(",
    wrap("proof", wrap("mycode", "$\ncode") .. "\n\\(│\\)")
  )
  local future = " " .. string.rep("word ", 400)
  case(
    "raw recovery does not visit future body",
    wrap("proof", wrap("mycode", "$\ncode") .. "\n\\│" .. future),
    "(",
    wrap("proof", wrap("mycode", "$\ncode") .. "\n\\(│\\)" .. future)
  )
  case(
    "math upgraded to literal",
    wrap("equation", "│"),
    "(",
    wrap("equation", "(│"),
    vim.tbl_deep_extend("force", opts, { tex_environments = { equation = "literal" } })
  )
  case(
    "plaintex declarations",
    wrap("proof", "│"),
    "\\(x\\)",
    wrap("proof", "\\(x\\)│"),
    nil,
    "plaintex"
  )
  case(
    "classification disabled",
    wrap("proof", "│"),
    "$$",
    wrap("proof", "$$│"),
    vim.tbl_deep_extend("force", opts, { tex_environments = { proof = false } })
  )
  case(
    "classification changed to math",
    wrap("proof", "│"),
    "$$",
    wrap("proof", "$$│"),
    vim.tbl_deep_extend("force", opts, { tex_environments = { proof = "math" } })
  )
  case(
    "wrong matching end is conservative",
    "\\begin{proof}\n│\n\\end{other}",
    "\\(",
    "\\begin{proof}\n\\(│\n\\end{other}"
  )
  test("tex environments: live buffer override", function()
    local entry = seed(wrap("proof", "│"), "tex")
    plugin.setup(opts)
    vim.b.pairs_tex_environments = { proof = "literal" }
    feed(entry .. "(<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, wrap("proof", "(│"))
    vim.b.pairs_tex_environments = { proof = "text" }
    feed("a<BS>\\(<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, wrap("proof", "\\(│\\)"))
  end)
  test("tex environments: invalid buffer declaration passes through with diagnostic", function()
    seed(wrap("proof", "│"), "tex")
    plugin.setup(opts)
    vim.b.pairs_tex_environments = { proof = "invalid" }
    eq(plugin.explain("(", { assume_insert = true }).reason, "context_error")
  end)
  test("tex environments: native undo redo and dot in proof", function()
    input(wrap("proof", "│"), "\\[<CR>x", wrap("proof", "\\[\nx│\n\\]"), opts, "tex")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "\\begin{proof}", "", "\\end{proof}" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
  end)
end

return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = {
    treesitter = true,
    tex_environments = { proof = "text", mycode = "literal", mymath = "math" },
    multi_pairs = { ["$$"] = {}, ["\\("] = {}, ["\\["] = {} },
  }
  local function case(label, before, keys, after, config, ft)
    test("tex arguments: " .. label, function()
      input(before, keys, after, config or opts, ft or "tex")
    end)
  end
  case("Tree-sitter opt out", "\\url{│}", "(", "\\url{(│)}", { treesitter = false })
  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  for _, name in ipairs({
    "section",
    "section*",
    "subsection",
    "chapter",
    "paragraph",
    "textbf",
    "textit",
    "texttt",
    "emph",
    "underline",
  }) do
    local head = "\\" .. name .. "{"
    case(name .. " brackets", head .. "│}", "(x)", head .. "(x)│}")
    case(name .. " continuous inline formula", head .. "│}", "\\(x\\)", head .. "\\(x\\)│}")
    case(name .. " unfinished inline formula", head .. "│", "\\(", head .. "\\(│\\)")
    case(name .. " pending backslash", head .. "\\│}", "(", head .. "\\(│\\)}")
    case(name .. " display opening is native", head .. "│}", "\\[", head .. "\\[│}")
  end
  for _, name in ipairs({ "url", "nolinkurl", "path" }) do
    local head = "\\" .. name .. "{"
    case(name .. " raw quotes brackets", head .. "│}", '("', head .. '("│}')
    case(name .. " raw inline opening", head .. "│}", "\\(", head .. "\\(│}")
    case(name .. " raw display opening", head .. "│}", "\\[", head .. "\\[│}")
    case(name .. " raw dollar", head .. "│}", "$$", head .. "$$│}")
    case(name .. " unfinished raw", head .. "│", '("', head .. '("│')
    case(name .. " multiline raw", head .. "\n│}", "(", head .. "\n(│}")
    case(name .. " EOF raw", head .. "\n│", "(", head .. "\n(│")
    case(name .. " outer Enter remains native", head .. "│}", "<CR>", head .. "\n│}")
    case(name .. " literal empty payload deletion", head .. "(│)}", "<BS>", head .. "│)}")
    case(name .. " empty payload Enter is native", head .. "{│}}", "<CR>", head .. "{\n│}}")
    case(name .. " outer braces pair continuously", "│", "\\" .. name .. "{x}", head .. "x}│")
    case(name .. " structural closer skip", head .. "x│}", "}", head .. "x}│")
    case(name .. " empty structural delete", head .. "│}", "<BS>", "\\" .. name .. "│")
    case(name .. " escaped brace stays raw", head .. "x\\}│}", '"', head .. 'x\\}"│}')
    case(name .. " raw percent is not a comment", head .. "a%20│}", "}", head .. "a%20}│")
    case(
      name .. " closed payload restores bracket pairing",
      head .. "x}│",
      "(",
      head .. "x}(│)"
    )
    case(name .. " closed quote payload restores pairing", head .. '"}│', "(", head .. '"}(│)')
    case(
      name .. " closed percent payload restores pairing",
      head .. "a%20}│",
      "(",
      head .. "a%20}(│)"
    )
    case(
      name .. " content after real comment remains native",
      head .. "a%20} % │",
      "(",
      head .. "a%20} % (│"
    )
    case(
      name .. " nonzero source column",
      "word " .. head .. '"}│',
      "(",
      "word " .. head .. '"}(│)'
    )
  end
  case("href empty address", "\\href{│}{label}", '("', '\\href{("│}{label}')
  case("continuous full text command", "│", "\\textbf{\\(x\\)}", "\\textbf{\\(x\\)}│")
  case("continuous full href command", "│", "\\href{uri}{\\(x\\)}", "\\href{uri}{\\(x\\)}│")
  case("href display text", "\\href{uri}{│}", "\\(x\\)", "\\href{uri}{\\(x\\)│}")
  case("href unfinished display text", "\\href{uri}{│", "\\(", "\\href{uri}{\\(│\\)")
  case("href multiline display text", "\\href{uri}\n{│}", "\\(", "\\href{uri}\n{\\(│\\)}")
  case(
    "href options then raw address",
    "\\href[color=red]{│}{label}",
    "(",
    "\\href[color=red]{(│}{label}"
  )
  case(
    "href raw address ignores command looking payload",
    "\\href{\\textbf{│}}{label}",
    '"',
    '\\href{\\textbf{"│}}{label}'
  )
  case("nested text commands", "\\textbf{\\emph{│}}", "\\(x\\)", "\\textbf{\\emph{\\(x\\)│}}")
  case("raw quote before href label", '\\href{"}{│}', "\\(x\\)", '\\href{"}{\\(x\\)│}')
  case("raw percent before href label", "\\href{a%20}{│}", "\\(", "\\href{a%20}{\\(│\\)}")
  case("raw data before outer text close", '\\textbf{\\path{"}│}', "}", '\\textbf{\\path{"}}│')
  case("nested raw command", "\\textbf{\\url{│}}", "(", "\\textbf{\\url{(│}}")
  case("unknown argument stays conservative for math", "\\unknown{│}", "\\(", "\\unknown{\\(│}")
  case("unsupported star stays conservative", "\\textbf*{│}", "\\(", "\\textbf*{\\(│}")
  case(
    "unknown nested in text stays conservative",
    "\\textbf{\\unknown{│}}",
    "\\(",
    "\\textbf{\\unknown{\\(│}}"
  )
  case("unclosed section optional title", "\\section[│", "\\(", "\\section[\\(│\\)")
  case("section optional title", "\\section[│]{title}", "\\(x\\)", "\\section[\\(x\\)│]{title}")
  case("section optional title closer", "\\section[x│]{title}", "]", "\\section[x]│{title}")
  case(
    "section mandatory after optional",
    "\\section[short]{│}",
    "\\(",
    "\\section[short]{\\(│\\)}"
  )
  case("multiline text formula", "\\textbf{\n│}", "\\(x\\)", "\\textbf{\n\\(x\\)│}")
  case("EOF text formula", "\\textbf{\n│", "\\(", "\\textbf{\n\\(│\\)")
  case("text argument display dollar stays native", "\\textbf{\n│}", "$$", "\\textbf{\n$$│}")
  case("text argument normal Enter", "\\textbf{│}", "<CR>x", "\\textbf{\n  x│\n}")
  case("multiline text closer", "\\textbf{\nx\n│}", "}", "\\textbf{\nx\n}│")
  case("comment payload is protected", "\\textbf{% │}", "(", "\\textbf{% (│}")
  case(
    "comment between command and argument",
    "\\textbf% title\n{│}",
    "\\(",
    "\\textbf% title\n{\\(│\\)}"
  )
  case("prior unmatched math is not lifted", "$ \\textbf{│}", "\\(", "$ \\textbf{\\(│}")
  case("known text mode inside math stays protected", "$\\text{│}$", "\\(", "$\\text{\\(│}$")
  case("escaped command does not introduce raw mode", "\\\\url{│}", "(", "\\\\url{(│)}")
  case(
    "control symbol brace does not end raw scope",
    "\\url{\\{x\\} │}",
    "(",
    "\\url{\\{x\\} (│}"
  )
  case("raw nested braces retain outer scope", "\\path{a{b}│}", '"', '\\path{a{b}"│}')
  case(
    "text argument in math stays math",
    "\\begin{mymath}\n\\textbf{│}\n\\end{mymath}",
    "\\(",
    "\\begin{mymath}\n\\textbf{\\(│}\n\\end{mymath}"
  )
  case(
    "text argument in raw stays raw",
    "\\begin{mycode}\n\\textbf{│}\n\\end{mycode}",
    "(",
    "\\begin{mycode}\n\\textbf{(│}\n\\end{mycode}"
  )
  case(
    "raw outer environment never skips argument braces",
    "\\begin{mycode}\n\\textbf{x│}\n\\end{mycode}",
    "}",
    "\\begin{mycode}\n\\textbf{x}│}\n\\end{mycode}"
  )
  case(
    "unknown outer environment stays conservative",
    "\\begin{unknown}\n\\textbf{│}\n\\end{unknown}",
    "\\(",
    "\\begin{unknown}\n\\textbf{\\(│}\n\\end{unknown}"
  )
  case("plaintex alias", "\\textbf{│}", "\\(", "\\textbf{\\(│\\)}", nil, "plaintex")
  case("UTF-8 text argument", "\\section{标题 \\│}", "(", "\\section{标题 \\(│\\)}")
  case(
    "UTF-8 raw masking preserves byte columns",
    '标题 \\path{路径"}│',
    "(",
    '标题 \\path{路径"}(│)'
  )
  case("raw argument without math rules", "\\url{│}", '("', '\\url{("│}', { treesitter = true })
  case(
    "text does not enable math rules",
    "\\textbf{│}",
    "\\(",
    "\\textbf{\\(│}",
    { treesitter = true }
  )
  case(
    "skip disabled for outer braces",
    "\\url{x│}",
    "}",
    "\\url{x}│}",
    vim.tbl_deep_extend("force", opts, { pairs = { ["{"] = { skip = false } } })
  )
  case(
    "delete disabled for outer braces",
    "\\url{│}",
    "<BS>",
    "\\url│}",
    vim.tbl_deep_extend("force", opts, { pairs = { ["{"] = { delete = false } } })
  )
  case(
    "argument outside 32 line bound",
    "\\path{\n" .. string.rep("x\n", 32) .. "│",
    "(",
    "\\path{\n" .. string.rep("x\n", 32) .. "(│"
  )
  case(
    "argument prefix byte budget",
    "\\textbf{" .. string.rep(string.rep("x", 220) .. "\n", 20) .. "│",
    "\\(",
    "\\textbf{" .. string.rep(string.rep("x", 220) .. "\n", 20) .. "\\(│"
  )
  case(
    "long future payload cannot bypass raw protection",
    "\\url{│ " .. string.rep("x", 4100) .. "}",
    '"',
    '\\url{"│ ' .. string.rep("x", 4100) .. "}"
  )
  test("tex arguments: undo redo and dot retain inline formula", function()
    input("\\textbf{│}", "\\(x\\)", "\\textbf{\\(x\\)│}", opts, "tex")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "\\textbf{}" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
    feed("u.")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
  end)
  test("tex arguments: missing parser retains the line lexer", function()
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function()
      return nil
    end
    local ok, err = pcall(function()
      input("\\url{│}", "(", "\\url{(│)}", opts, "tex")
      input("\\textbf{│}", "\\(", "\\textbf{\\(│}", opts, "tex")
    end)
    vim.treesitter.get_parser = original
    assert(ok, err)
  end)
  test("tex arguments: pending parse never skips a structural closer", function()
    seed("\\url{x│}", "tex")
    plugin.setup(opts)
    local parser = vim.treesitter.get_parser(0, "latex")
    parser:parse(true)
    eq(plugin.explain("}", { assume_insert = true }).action, "skip")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "\\url{x}" })
    local original = parser.parse
    parser.parse = function(_, range, callback)
      assert(type(range) == "table" and type(callback) == "function", "forced synchronous parse")
      return nil
    end
    local ok, err = pcall(function()
      eq(plugin.explain("}", { assume_insert = true }).action, "pass")
    end)
    parser.parse = original
    assert(ok, err)
  end)
  test("tex arguments: over-budget prefix does not fetch body text", function()
    seed("\\path{\n" .. string.rep(string.rep("x", 220) .. "\n", 20) .. "│", "tex")
    plugin.setup(opts)
    local root = vim.treesitter.get_parser(0, "latex"):parse()[1]:root()
    local original = vim.api.nvim_buf_get_text
    vim.api.nvim_buf_get_text = function(buf, sr, sc, er, ec, options)
      assert(sr == er and ec - sc <= 64, "over-budget body read")
      return original(buf, sr, sc, er, ec, options)
    end
    local ok, result = pcall(require("pairs.tex_args").capture, root, 21, 0, "", 0)
    vim.api.nvim_buf_get_text = original
    assert(ok, result)
    eq(result.unsafe, true)
  end)
end

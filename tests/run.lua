local plugin = require("pairs")
local count, failures = 0, {}

local function eq(actual, expected)
  if not vim.deep_equal(actual, expected) then
    error("expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual), 2)
  end
end

local function test(name, run)
  count = count + 1
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    failures[#failures + 1] = name .. "\n" .. err
    io.stderr:write("FAIL: " .. name .. "\n")
  end
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "xt", false)
end

local function seed(marked, ft)
  plugin.teardown()
  vim.cmd("enew!")
  vim.o.paste = false
  vim.bo.buftype = ""
  vim.bo.modifiable = true
  vim.bo.filetype = ft or "lua"
  vim.bo.autoindent = true
  vim.bo.expandtab = true
  vim.bo.shiftwidth = 2
  vim.bo.tabstop = 4
  vim.bo.vartabstop = ""
  vim.bo.indentexpr = ""
  vim.bo.cindent = false
  vim.bo.smartindent = false
  vim.bo.indentkeys = "0{,0},0),0],:,0#,!^F,o,O,e"
  vim.bo.cinkeys = "0{,0},0),0],:,0#,!^F,o,O,e"
  vim.b.pairs_rules = nil
  vim.b.pairs_multi_rules = nil
  vim.b.pairs_tex_environments = nil
  vim.b.pairs_enabled = nil
  local start = assert(marked:find("│", 1, true), "missing cursor marker")
  local prefix, suffix = marked:sub(1, start - 1), marked:sub(start + #"│")
  local text = prefix .. suffix
  local row = #vim.split(prefix, "\n", { plain = true })
  local col = #(prefix:match("[^\n]*$") or "")
  local lines = vim.split(text, "\n", { plain = true })
  vim.bo.undolevels = -1
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.undolevels = 1000
  local entry = col == #lines[row] and col > 0 and "a" or "i"
  vim.api.nvim_win_set_cursor(0, { row, entry == "a" and col - 1 or col })
  return entry, text
end

_G.pairs_test_capture = function()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local pos = vim.api.nvim_win_get_cursor(0)
  lines[pos[1]] = lines[pos[1]]:sub(1, pos[2]) .. "│" .. lines[pos[1]]:sub(pos[2] + 1)
  _G.pairs_test_result = table.concat(lines, "\n")
  _G.pairs_test_mode = vim.fn.mode()
end

local function input(before, keys, after, opts, ft, buffer_options)
  local entry = seed(before, ft)
  plugin.setup(opts)
  for name, value in pairs(buffer_options or {}) do
    vim.bo[name] = value
  end
  feed(entry .. keys .. "<Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, after)
  eq(_G.pairs_test_mode, "i")
end

local cases = {
  { "double quote opens", "│", '"', '"│"' },
  { "single quote opens", "│", "'", "'│'" },
  { "quote closes", '"abc│"', '"', '"abc"│' },
  { "single quote closes", "'abc│'", "'", "'abc'│" },
  { "missing quote closes once", '"abc│', '"', '"abc"│' },
  { "contraction", "don│t", "'", "don'│t" },
  { "apostrophe after word", "dogs│", "'", "dogs'│" },
  { "double quote after word", "name│", '"', 'name"│' },
  { "double quote before text", "│hello", '"', '"│hello' },
  { "single quote before text", "│hello", "'", "'│hello" },
  { "quote before existing quote", '│"', '"', '"│"' },
  { "quote after closing quote", '"x"│', '"', '"x""│' },
  { "apostrophe inside double string", '"don│t"', "'", '"don\'│t"' },
  { "double quote inside single string", "'say │'", '"', "'say \"│'" },
  { "odd backslashes", "\\│", '"', '\\"│' },
  { "even backslashes", "\\\\│", '"', '\\\\"│"' },
  { "three backslashes", "\\\\\\│", '"', '\\\\\\"│' },
  { "long even escape run", string.rep("\\", 512) .. "│", '"', string.rep("\\", 512) .. '"│"' },
  { "escaped quote does not close string", '"a\\"│', '"', '"a\\""│' },
  { "Chinese before quote", "你好│", '"', '你好"│' },
  { "Chinese after quote", "│你好", '"', '"│你好' },
  { "Chinese inside string", '"你好│"', '"', '"你好"│' },
  { "bracket opens", "│", "(", "(│)" },
  { "square bracket opens", "│", "[", "[│]" },
  { "brace opens", "│", "{", "{│}" },
  { "bracket skips", "(│)", ")", "()│" },
  { "nested bracket skips", "([│])", "])", "([])│" },
  { "unmatched closer is inserted", "│)", ")", ")│)" },
  { "wrong nesting is inserted", "([│)", ")", "([)│)" },
  { "unbalanced prefix is conservative", ") (│)", ")", ") ()│)" },
  { "bracket before word", "│name", "(", "(│name" },
  { "bracket inside string", '"│"', "(", '"(│"' },
  { "closer inside string", '"(│)"', ")", '"()│)"' },
  { "delete empty brackets", "(│)", "<BS>", "│" },
  { "delete empty quotes", '"│"', "<BS>", "│" },
  { "delete empty single quotes", "'│'", "<BS>", "│" },
  { "delete only preceding text", "(a│)", "<BS>", "(│)" },
  { "escaped quotes not deleted as pair", '\\"│"', "<BS>", '\\│"' },
  { "brackets in string not deleted as pair", '"(│)"', "<BS>", '"│)"' },
  { "brackets after escaped quote", '"a\\" (│)"', "<BS>", '"a\\" │)"' },
  { "lua comment", "-- │", '"', '-- "│' },
  { "lua apostrophe in comment", "-- don│t", "'", "-- don'│t" },
  { "comment-like text inside string", '"-- │"', '"', '"-- "│' },
  { "python comment", "# │", '"', '# "│', nil, "python" },
  { "escaped TeX percent is not a comment", "\\% │", '"', '\\% "│"', nil, "tex" },
  { "C comment", "// │", '"', '// "│', nil, "c" },
  { "Rust lifetime", "│", "'a", "'a│", nil, "rust" },
  { "Rust character closes", "'x│'", "'", "'x'│", nil, "rust" },
  { "Rust escaped character closes", "'\\n│'", "'", "'\\n'│", nil, "rust" },
  { "Rust Unicode character closes", "'你│'", "'", "'你'│", nil, "rust" },
  {
    "Rust lifetime then parentheses",
    "let x: &'a T = │",
    "(",
    "let x: &'a T = (│)",
    nil,
    "rust",
  },
  { "markdown single quote disabled", "│", "'", "'│", nil, "markdown" },
  { "text single quote disabled", "│", "'", "'│", nil, "text" },
  { "markdown double quote", "│", '"', '"│"', nil, "markdown" },
  { "continuous typing", "│", '("abc")', '("abc")│' },
  { "continuous nested typing", "│", '({["x"]})', '({["x"]})│' },
  { "paired backspace and retype", "│", '"<BS>(x)', "(x)│" },
  {
    "single opening disabled but skip enabled",
    "'x│'",
    "'",
    "'x'│",
    { pairs = { ["'"] = { open = false } } },
  },
  { "single opening disabled", "│", "'", "'│", { pairs = { ["'"] = { open = false } } } },
  { "quote skip disabled", '"x│"', '"', '"x"│"', { pairs = { ['"'] = { skip = false } } } },
  { "quote delete disabled", '"│"', "<BS>", '│"', { pairs = { ['"'] = { delete = false } } } },
  { "whole rule disabled", "│", "(", "(│", { pairs = { ["("] = false } } },
  { "plugin disabled", "│", '"', '"│', { enabled = false } },
  {
    "predicate disabled",
    "│",
    '"',
    '"│',
    {
      enabled = function()
        return false
      end,
    },
  },
  { "filetype disabled", "│", '"', '"│', { disabled_filetypes = { "lua" } } },
  {
    "filetype override",
    "│",
    '"',
    '"│',
    { filetypes = { lua = { pairs = { ['"'] = { open = false } } } } },
  },
  { "scan limit", "long │", '"', 'long "│', { max_scan_bytes = 2 } },
  { "no parser fallback", "│", '"', '"│"', { treesitter = true }, "pairs_missing_parser" },
  { "custom bracket", "│", "<x>", "<x>│", { pairs = { ["<"] = { close = ">" } } } },
  { "custom symmetric pair", "│", "$x$", "$x$│", { pairs = { ["$"] = { close = "$" } } } },
  { "javascript template string", "`│`", '"', '`"│`', nil, "javascript" },
  {
    "explicit backticks",
    "│",
    "`x`",
    "`x`│",
    { pairs = { ["`"] = { close = "`" } } },
    "markdown",
  },
}

for _, case in ipairs(cases) do
  test(case[1], function()
    input(case[2], case[3], case[4], case[5], case[6])
  end)
end

local newline_cases = {
  { "brace expansion", "{│}", "<CR>", "{\n  │\n}" },
  { "parenthesis expansion", "(│)", "<CR>", "(\n  │\n)" },
  { "square expansion", "[│]", "<CR>", "[\n  │\n]" },
  { "indented expansion", "  {│}", "<CR>", "  {\n    │\n  }" },
  { "surrounding text preserved", "fn({│});", "<CR>", "fn({\n  │\n});" },
  { "continuous expansion", "│", "{<CR>body", "{\n  body│\n}" },
  { "nested expansion", "│", "{<CR>[<CR>body", "{\n  [\n    body│\n  ]\n}" },
  { "quotes do not expand", '"│"', "<CR>", '"\n│"' },
  { "single quotes do not expand", "'│'", "<CR>", "'\n│'" },
  { "string brackets do not expand", '"{│}"', "<CR>", '"{\n│}"' },
  { "comment brackets do not expand", "-- {│}", "<CR>", "-- {\n-- │}" },
  { "escaped pair does not expand", "\\{│}", "<CR>", "\\{\n│}" },
  { "nonempty pair does not expand", "{body│}", "<CR>", "{body\n│}" },
  { "ordinary newline fallback", "word│", "<CR>", "word\n│" },
  {
    "disabled newline rule",
    "{│}",
    "<CR>",
    "{\n│}",
    { pairs = { ["{"] = { newline = false } } },
  },
  { "disabled CR mapping", "{│}", "<CR>", "{\n│}", { mappings = { cr = false } } },
  { "disabled plugin does not expand", "{│}", "<CR>", "{\n│}", { enabled = false } },
  {
    "filetype newline override",
    "{│}",
    "<CR>",
    "{\n│}",
    { filetypes = { lua = { pairs = { ["{"] = { newline = false } } } } },
  },
  {
    "tabs",
    "\t{│}",
    "<CR>",
    "\t{\n\t\t│\n\t}",
    nil,
    nil,
    { expandtab = false, shiftwidth = 4 },
  },
  {
    "zero shiftwidth",
    "{│}",
    "<CR>",
    "{\n\t│\n}",
    nil,
    nil,
    { expandtab = false, shiftwidth = 0 },
  },
  {
    "variable tabstops",
    "\t{│}",
    "<CR>",
    "\t{\n\t\t│\n\t}",
    nil,
    nil,
    { expandtab = false, shiftwidth = 4, vartabstop = "2,4" },
  },
  {
    "autoindent disabled",
    "  {│}",
    "<CR>",
    "  {\n    │\n  }",
    nil,
    nil,
    { autoindent = false },
  },
  { "unusual iskeyword", "{│}", "<CR>", "{\n  │\n}", nil, nil, { iskeyword = "@,48-57,_,^x" } },
  {
    "small textwidth",
    "{│}",
    "<CR>",
    "{\n  │\n}",
    nil,
    nil,
    { textwidth = 3, formatoptions = "t" },
  },
}
for _, case in ipairs(newline_cases) do
  test("newline: " .. case[1], function()
    input(case[2], case[3], case[4], case[5], case[6], case[7])
  end)
end

test("newline: undo and redo entire insertion", function()
  input("│", "{<CR>body", "{\n  body│\n}")
  feed("u")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
  feed("<C-r>")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}" })
end)

test("newline: complete dot repeat", function()
  input("│", "{<CR>body", "{\n  body│\n}")
  feed("gg0.")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}{", "  body", "}" })
  feed("u")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}" })
end)

test("newline: counted dot repeat", function()
  input("│", "{<CR>body", "{\n  body│\n}")
  feed("gg02.")
  eq(
    vim.api.nvim_buf_get_lines(0, 0, -1, false),
    { "{", "  body{", "  body", "}", "}{", "  body", "}" }
  )
end)

test("newline: buffer override", function()
  local entry = seed("{│}")
  plugin.setup()
  vim.b.pairs_rules = { ["{"] = { newline = false } }
  feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, "{\n│}")
end)

test("newline: composed Enter keeps undo and dot", function()
  local entry = seed("│")
  plugin.setup({ mappings = { cr = false } })
  vim.keymap.set("i", "<CR>", function()
    return plugin.expr("<CR>") or require("pairs.mapping").keycode("<CR>")
  end, { expr = true, replace_keycodes = false, desc = "completion owner" })
  feed(entry .. "{<CR>body<Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, "{\n  body│\n}")
  feed("u")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
  feed("<C-r>gg0.")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}{", "  body", "}" })
  plugin.teardown()
  eq(vim.fn.maparg("<CR>", "i", false, true).desc, "completion owner")
  vim.keymap.del("i", "<CR>")
end)

test("newline: symmetric rules never expand", function()
  input('"│"', "<CR>", '"\n│"', { pairs = { ['"'] = { newline = true } } })
end)

test("newline: temporary word does not expand abbreviations", function()
  vim.cmd("iabbrev x EXPANDED")
  local ok, err = pcall(input, "{│}", "<CR>", "{\n  │\n}")
  vim.cmd("iunabbrev x")
  assert(ok, err)
end)

_G.pairs_test_indent = function()
  return vim.fn.getline(vim.v.lnum):match("^%s*[}%]%)]") and 0 or 4
end

test("newline: indentexpr indentation", function()
  input("{│}", "<CR>", "{\n    │\n}", nil, nil, { indentexpr = "v:lua.pairs_test_indent()" })
end)

test("newline: indentexpr without reindent key", function()
  input(
    "{│}",
    "<CR>",
    "{\n    │\n}",
    nil,
    nil,
    { indentexpr = "v:lua.pairs_test_indent()", indentkeys = "o,O" }
  )
end)

test("newline: cindent", function()
  input("{│}", "<CR>", "{\n  │\n}", nil, "c", { cindent = true })
end)

test("newline: builtin Lua indentation and dot", function()
  local entry = seed("│")
  plugin.setup()
  vim.b.did_indent = nil
  vim.cmd("runtime indent/lua.vim")
  feed(entry .. "local x = {<CR>value<Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, "local x = {\n  value│\n}")
  feed("gg0.")
  eq(
    vim.api.nvim_buf_get_lines(0, 0, -1, false),
    { "local x = {", "  value", "}local x = {", "  value", "}" }
  )
end)

test("newline: builtin Python continuation indentation", function()
  local entry = seed("value = (│)", "python")
  plugin.setup()
  vim.b.did_indent = nil
  vim.cmd("runtime indent/python.vim")
  feed(entry .. "<CR>item<Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, "value = (\n    item│\n    )")
end)

test("newline: cindent undo and complete dot", function()
  input("│", "{<CR>body", "{\n  body│\n}", nil, "c", { cindent = true })
  feed("u")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
  feed("<C-r>gg0.")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "  body", "}{", "  body", "}" })
end)

test("newline: literal tabs survive dot repeat", function()
  input(
    "│",
    "{<CR>body",
    "{\n\tbody│\n}",
    nil,
    nil,
    { expandtab = false, shiftwidth = 4, softtabstop = 2 }
  )
  feed("gg0.")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "\tbody", "}{", "\tbody", "}" })
end)

test("newline: custom indentexpr replay", function()
  input(
    "│",
    "{<CR>body",
    "{\n    body│\n}",
    nil,
    nil,
    { indentexpr = "v:lua.pairs_test_indent()", indentkeys = "o,O" }
  )
  feed("gg0.")
  eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "{", "    body", "}{", "    body", "}" })
end)

test("newline: raw string passthrough with Tree-sitter", function()
  local entry = seed("local s = [[\n{│}\n]]")
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, "local s = [[\n{\n│}\n]]")
end)

test("newline: expression callback retains v:lnum and options", function()
  local entry = seed("{│}")
  plugin.setup()
  vim.bo.indentexpr = "v:lua.pairs_test_indent()"
  vim.bo.indentkeys = "o,O"
  local old_lnum = vim.v.lnum
  feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(vim.v.lnum, old_lnum)
  eq(vim.bo.indentexpr, "v:lua.pairs_test_indent()")
  eq(vim.bo.indentkeys, "o,O")
end)

test("opening cursor movement preserves undo", function()
  input("seed │", '("abc")', 'seed ("abc")│')
  feed("u")
  eq(vim.api.nvim_get_current_line(), "seed ")
  feed("<C-r>")
  eq(vim.api.nvim_get_current_line(), 'seed ("abc")')
end)

test("Tree-sitter multiline string", function()
  local entry = seed("local s = [[\n│\n]]")
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, 'local s = [[\n"│\n]]')
end)

test("Tree-sitter multiline comment", function()
  local entry = seed("--[[\n│\n]]")
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '--[[\n"│\n]]')
end)

test("Tree-sitter still allows closing quote", function()
  local entry = seed('local s = "x│"')
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, 'local s = "x"│')
end)

test("raw string quote is inserted rather than skipped", function()
  local entry = seed('local s = [["x│"]]')
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, 'local s = [["x"│"]]')
end)

test("raw string quotes are not deleted as a pair", function()
  local entry = seed('local s = [["│"]]')
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  feed(entry .. "<BS><Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, 'local s = [[│"]]')
end)

test("stale parser tree preserves input", function()
  local entry = seed('local s = "│"')
  plugin.setup({ treesitter = true })
  local parser = vim.treesitter.get_parser(0, "lua")
  parser:parse()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'local s = "a"' })
  eq(parser:is_valid(), false)
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, 'local s = ""│a"')
end)

local syntax_cases = {
  { "line comment at EOL", "-- words │", '"', '-- words "│', "lua" },
  { "C line comment at EOL", "// words │", '"', '// words "│', "c" },
  { "incomplete block comment", "/* words │", '"', '/* words "│', "c" },
  { "incomplete quoted string", 'local s = "words │', '"', 'local s = "words "│', "lua" },
  { "continuous quote input", "│", '("body")', '("body")│', "lua" },
  { "continuous Enter expansion", "│", "{<CR>body", "{\n  body│\n}", "lua" },
  {
    "code after a long string",
    'local s = [[" { ]] ; │',
    '"',
    'local s = [[" { ]] ; "│"',
    "lua",
  },
  {
    "code after multiline string",
    'local s = [[\n" {\n]]; │',
    '"',
    'local s = [[\n" {\n]]; "│"',
    "lua",
  },
  {
    "long string contents at EOL",
    "local s = [=[\nbody │\n]=]",
    '"',
    'local s = [=[\nbody "│\n]=]',
    "lua",
  },
  { "block comment contents", "/*\n│\n*/", '"', '/*\n"│\n*/', "c" },
  { "after a block comment", '/* " { */ │', '"', '/* " { */ "│"', "c" },
  { "bracket stack around a string", 'fn("x"│)', ")", 'fn("x")│', "c" },
}
if vim.env.PAIRS_TEST_PARSER_ROOT then
  vim.list_extend(syntax_cases, {
    { "Python conversion suffix", 's = f"{x!r│}"', "(", 's = f"{x!r(│}"', "python" },
    { "incomplete Python triple string", 's = """words │', '"', 's = """words "│', "python" },
    {
      "incomplete JavaScript template",
      "const s = `words │",
      '"',
      'const s = `words "│',
      "javascript",
    },
    { "Python triple double quotes", 's = """\n│\n"""', '"', 's = """\n"│\n"""', "python" },
    { "Python triple single quotes", "s = '''\n│\n'''", "'", "s = '''\n'│\n'''", "python" },
    { "Python single-line triple string", 's = """│"""', '"', 's = """"│"""', "python" },
    { "Python prefixed quote closer", "s = r'body│'", "'", "s = r'body'│", "python" },
    {
      "Python f-string contents",
      's = f"hello │{name}"',
      '"',
      's = f"hello "│{name}"',
      "python",
    },
    { "Python f-string expression", 's = f"{fn(│)}"', '"', 's = f"{fn("│")}"', "python" },
    {
      "Python f-string expression closing",
      's = f"{fn("body│")}"',
      '"',
      's = f"{fn("body"│)}"',
      "python",
    },
    { "Python empty f-string expression", 's = f"{│}"', '"', 's = f"{"│"}"', "python" },
    { "Python format specifier text", 's = f"{x:│}"', '"', 's = f"{x:"│}"', "python" },
    {
      "Python nested format expression",
      's = f"{x:{fn(│)}}"',
      '"',
      's = f"{x:{fn("│")}}"',
      "python",
    },
    {
      "Python after triple string",
      's = """\n" {\n"""; │',
      '"',
      's = """\n" {\n"""; "│"',
      "python",
    },
    { "Rust raw string contents", 'let s = r##"│"##;', '"', 'let s = r##""│"##;', "rust" },
    {
      "Rust raw string internal quote",
      'let s = r##"a "│" b"##;',
      '"',
      'let s = r##"a ""│" b"##;',
      "rust",
    },
    { "Rust raw string deletion", 'let s = r##""│""##;', "<BS>", 'let s = r##"│""##;', "rust" },
    { "Rust raw string Enter", 'let s = r##"{│}"##;', "<CR>", 'let s = r##"{\n│}"##;', "rust" },
    {
      "Rust after raw string",
      'let s = r##" " { "##; │',
      '"',
      'let s = r##" " { "##; "│"',
      "rust",
    },
    {
      "JavaScript template contents",
      "const s = `hello │${name}`;",
      '"',
      'const s = `hello "│${name}`;',
      "javascript",
    },
    {
      "JavaScript template expression",
      "const s = `${fn(│)}`;",
      '"',
      'const s = `${fn("│")}`;',
      "javascript",
    },
    {
      "JavaScript template quote closer",
      'const s = `${fn("body│")}`;',
      '"',
      'const s = `${fn("body"│)}`;',
      "javascript",
    },
    {
      "JavaScript empty template expression",
      "const s = `${│}`;",
      '"',
      'const s = `${"│"}`;',
      "javascript",
    },
    {
      "JavaScript template expression brackets",
      "const s = `${fn(│)}`;",
      "{<CR>body",
      "const s = `${fn({\n  body│\n})}`;",
      "javascript",
    },
    {
      "JavaScript template comment",
      "const s = `${/* │ */ value}`;",
      '"',
      'const s = `${/* "│ */ value}`;',
      "javascript",
    },
    {
      "JavaScript after template string",
      'const s = `" {`; │',
      '"',
      'const s = `" {`; "│"',
      "javascript",
    },
  })
end
for _, case in ipairs(syntax_cases) do
  test("syntax: " .. case[1], function()
    input(case[2], case[3], case[4], { treesitter = true }, case[5])
  end)
end

test("syntax: forced sync parsing is never requested", function()
  local entry = seed("local s = [[\n│\n]]")
  plugin.setup({ treesitter = true })
  local previous = vim.g._ts_force_sync_parsing
  vim.g._ts_force_sync_parsing = true
  local ok, err = pcall(function()
    eq(plugin.explain('"', { assume_insert = true }).reason, "syntax_pending")
    feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
    eq(_G.pairs_test_result, 'local s = [[\n"│\n]]')
  end)
  vim.g._ts_force_sync_parsing = previous
  assert(ok, err)
end)

test("syntax: unfinished asynchronous parse preserves input", function()
  local entry = seed("local s = [[\n│\n]]")
  plugin.setup({ treesitter = true })
  local parser = vim.treesitter.get_parser(0, "lua")
  local original = parser.parse
  local calls = 0
  parser.parse = function(_, range, on_parse)
    calls = calls + 1
    eq(type(range), "table")
    eq(type(on_parse), "function")
    return nil
  end
  local ok, err = pcall(function()
    eq(plugin.explain('"', { assume_insert = true }).reason, "syntax_pending")
    feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
    eq(_G.pairs_test_result, 'local s = [[\n"│\n]]')
    assert(calls > 0)
  end)
  parser.parse = original
  assert(ok, err)
end)

test("syntax: incomplete literal has a diagnostic reason", function()
  seed("/* words │", "c")
  plugin.setup({ treesitter = true })
  eq(plugin.explain('"', { assume_insert = true }).reason, "syntax_incomplete")
end)

test("syntax: complex line traversal is bounded", function()
  local before = "local x = {" .. string.rep("a,", 300) .. "}; "
  local entry = seed(before .. "│")
  plugin.setup({ treesitter = true })
  vim.treesitter.get_parser(0, "lua"):parse()
  eq(plugin.explain('"', { assume_insert = true }).reason, "syntax_limit")
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, before .. '"│')
end)

test("completion-provided brackets are not duplicated", function()
  local entry = seed("│")
  plugin.setup()
  _G.pairs_test_complete = function()
    vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, { "call()" })
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
  end
  feed(entry .. "<Cmd>lua pairs_test_complete()<CR>)<Cmd>lua pairs_test_capture()<CR><Esc>")
  eq(_G.pairs_test_result, "call()│")
end)

test("snippet-provided quotes can be closed", function()
  local entry = seed("│")
  plugin.setup()
  _G.pairs_test_snippet = function()
    vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, { 'fn("x")' })
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
  end
  feed(entry .. '<Cmd>lua pairs_test_snippet()<CR>")<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, 'fn("x")│')
end)

test("read-only explanation uses insertion context", function()
  seed('"x│"')
  plugin.setup()
  local before = vim.api.nvim_get_current_line()
  eq(plugin.explain('"').reason, "mode")
  local result = plugin.explain('"', { assume_insert = true })
  eq(result.action, "skip")
  eq(result.reason, "matching_quote")
  eq(vim.api.nvim_get_current_line(), before)
end)

test("decision engine does not mutate its snapshot", function()
  local config = require("pairs.config").build()
  local ctx = {
    enabled = true,
    line = '"x',
    col = 2,
    rules = config.pairs,
    lex = {
      max_scan_bytes = 4096,
      line_comments = {},
      openers = {},
      closers = {},
      quotes = { ['"'] = true, ["'"] = true },
    },
  }
  local before = vim.deepcopy(ctx)
  local result = require("pairs.engine").decide(ctx, '"')
  eq(result.action, "pass")
  eq(result.reason, "closing_quote")
  eq(ctx, before)
end)

test("callback failure can be diagnosed", function()
  seed("│")
  plugin.setup({
    enabled = function()
      error("test predicate")
    end,
  })
  local result = plugin.explain('"', { assume_insert = true })
  eq(result.action, "pass")
  eq(result.reason, "context_error")
  assert(result.error:find("test predicate", 1, true))
end)

test("CR and Tab mappings remain with their owner", function()
  seed("│")
  vim.keymap.set("i", "<CR>", "accept")
  vim.keymap.set("i", "<Tab>", "snippet")
  plugin.setup()
  eq(vim.fn.maparg("<CR>", "i"), "accept")
  eq(vim.fn.maparg("<Tab>", "i"), "snippet")
  plugin.teardown()
  eq(vim.fn.maparg("<CR>", "i"), "accept")
  eq(vim.fn.maparg("<Tab>", "i"), "snippet")
  vim.keymap.del("i", "<CR>")
  vim.keymap.del("i", "<Tab>")
end)

test("disabled backspace mapping remains native", function()
  input('"│"', "<BS>", '│"', { mappings = { bs = false } })
end)

test("prompt buffer bypasses pairing", function()
  local entry = seed("│")
  plugin.setup()
  vim.bo.buftype = "nofile"
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '"│')
end)

test("quote after custom symmetric delimiter stays literal", function()
  input("$$│", "$", "$$$│", { pairs = { ["$"] = { close = "$" } } })
end)

test("backspace preserves undo", function()
  input("seed │", '"x<BS><BS>', "seed │")
  feed("u")
  eq(vim.api.nvim_get_current_line(), "seed ")
end)

test("conflicting closers are rejected", function()
  local ok = pcall(plugin.setup, { pairs = { ["<"] = { close = ")" } } })
  eq(ok, false)
end)

test("setup does not mutate user rules", function()
  local opts = { pairs = { ["<"] = { close = ">" } } }
  local before = vim.deepcopy(opts)
  plugin.setup(opts)
  eq(opts, before)
end)

test("disabled filetype list can be cleared", function()
  input("│", '"', '"│"', { disabled_filetypes = {} }, "TelescopePrompt")
end)

test("require and commands do not install mappings", function()
  plugin.teardown()
  dofile("plugin/pairs.lua")
  eq(plugin.status().initialized, false)
  eq(plugin.status().mappings, 0)
  eq(vim.fn.exists(":PairsToggle"), 2)
  eq(vim.fn.exists(":PairsInspect"), 2)
end)

test("broken runtime predicate preserves input", function()
  input("│", '"', '"│', {
    enabled = function()
      error("predicate failure")
    end,
  })
end)

test("broken buffer rules preserve input", function()
  local entry = seed("│")
  plugin.setup()
  vim.b.pairs_rules = { ['"'] = { close = "invalid" } }
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '"│')
end)

test("dot repeat", function()
  input("│xx", "(a)", "(a)│xx")
  -- Opening before text is deliberately conservative, so this literal insertion
  -- exercises replay of matching-closer decisions without adding a second closer.
  feed("$.")
  eq(vim.api.nvim_get_current_line(), "(a)x(a)x")
end)

test("dot repeat with generated pairs", function()
  input("│", "(a)", "(a)│")
  feed("0.")
  eq(vim.api.nvim_get_current_line(), "(a)(a)")
end)

test("global and buffer toggles", function()
  local entry = seed("│")
  plugin.setup()
  plugin.disable()
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '"│')
  plugin.toggle()
  local entry2 = seed("│")
  plugin.setup()
  plugin.disable(0)
  feed(entry2 .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '"│')
  plugin.toggle(0)
  eq(vim.b.pairs_enabled, true)
end)

test("buffer rules take precedence", function()
  local entry = seed("│")
  plugin.setup()
  vim.b.pairs_rules = { ['"'] = { open = false } }
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '"│')
end)

test("existing global mapping is preserved", function()
  local entry = seed("│")
  vim.keymap.set("i", '"', function()
    return "custom"
  end, { expr = true })
  plugin.setup()
  eq(plugin.status().conflicts, { '"' })
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, "custom│")
  plugin.teardown()
  assert(vim.fn.maparg('"', "i") ~= "")
  vim.keymap.del("i", '"')
end)

test("existing buffer mapping is preserved", function()
  local entry = seed("│")
  vim.keymap.set("i", '"', "local", { buffer = true })
  plugin.setup()
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, "local│")
  plugin.teardown()
  eq(vim.fn.maparg('"', "i", false, true).buffer, 1)
  vim.keymap.del("i", '"', { buffer = true })
end)

test("teardown does not remove newer mappings", function()
  seed("│")
  plugin.setup()
  vim.keymap.set("i", '"', "newer")
  plugin.teardown()
  eq(vim.fn.maparg('"', "i"), "newer")
  vim.keymap.del("i", '"')
end)

test("setup is idempotent", function()
  seed("│")
  plugin.setup()
  local before = plugin.status().mappings
  plugin.setup()
  eq(plugin.status().mappings, before)
  eq(plugin.status().conflicts, {})
  plugin.teardown()
  eq(plugin.status().mappings, 0)
end)

test("invalid setup preserves current configuration", function()
  seed("│")
  plugin.setup()
  local before = plugin.status().mappings
  local ok = pcall(plugin.setup, { pairs = { ['"'] = { close = "long" } } })
  eq(ok, false)
  eq(plugin.status().mappings, before)
end)

test("expr composes with fallback", function()
  local entry = seed("│")
  plugin.setup({ mappings = { enabled = false } })
  vim.keymap.set("i", '"', function()
    return plugin.expr('"') or "fallback"
  end, { expr = true, replace_keycodes = false })
  feed(entry .. '"<Cmd>lua pairs_test_capture()<CR><Esc>')
  eq(_G.pairs_test_result, '"│"')
  vim.keymap.del("i", '"')
end)

test("typed prefix is applied before quote context", function()
  input("│", "don't", "don't│")
  input("│", 'word"', 'word"│')
  input("│", '# "', '# "│', { treesitter = true }, "python")
end)

test("deferred mappings remove owned private aliases", function()
  seed("│")
  plugin.setup()
  local owned = vim.deepcopy(require("pairs.mapping").owned)
  plugin.teardown()
  for _, mapping in ipairs(owned) do
    eq(vim.fn.maparg(mapping.plug, "i"), "")
  end
end)

test("private alias collision preserves the owner", function()
  seed("│")
  local plug = "<Plug>(pairs.nvim-34)"
  vim.keymap.set("i", plug, "foreign")
  plugin.setup()
  eq(plugin.status().conflicts, { '"' })
  plugin.teardown()
  eq(vim.fn.maparg(plug, "i"), "foreign")
  vim.keymap.del("i", plug)
end)

test("globally disabled quote survives partial filetype policies", function()
  input("│", "'", "'│", { pairs = { ["'"] = false } }, "markdown")
end)

test("complete filetype quote rule can re-enable a disabled rule", function()
  input("│", '"', '"│"', {
    pairs = { ['"'] = false },
    filetypes = { lua = { pairs = { ['"'] = { close = '"' } } } },
  })
end)

test("paste bypasses pairing", function()
  local entry = seed("│")
  plugin.setup()
  vim.o.paste = true
  feed(entry .. '"<Esc>')
  eq(vim.api.nvim_get_current_line(), '"')
  vim.o.paste = false
end)

test("replace mode is untouched", function()
  seed("│abc")
  plugin.setup()
  feed('R"<Esc>')
  eq(vim.api.nvim_get_current_line(), '"bc')
end)

test("macro recording and replay are literal", function()
  seed("│")
  plugin.setup()
  feed('qqi"<Esc>q')
  eq(vim.api.nvim_get_current_line(), '"')
  feed("A <Esc>@q")
  eq(vim.api.nvim_get_current_line(), '"" ')
end)

dofile("tests/triples.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/templates.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/fences.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/long_fences.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/tex.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/tex_slash.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/tex_environments.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/tex_arguments.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/performance.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/trace.lua")({
  test = test,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/space.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/space_skip.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/fast_wrap.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

dofile("tests/fast_wrap_opener.lua")({
  test = test,
  input = input,
  seed = seed,
  feed = feed,
  eq = eq,
  plugin = plugin,
})

plugin.teardown()
if #failures > 0 then
  io.stderr:write(table.concat(failures, "\n\n") .. "\n")
  io.stderr:write(string.format("%d/%d tests failed\n", #failures, count))
  vim.cmd("cquit 1")
else
  print(string.format("PASS: %d tests (real Neovim input, cursor, undo, mappings)", count))
  vim.cmd("qa!")
end

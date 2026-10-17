return function(t)
  local s = require("pairs.surround")
  local function seed(marked, overrides)
    t.seed(marked, "text")
    vim.b.pairs_surround_config = nil
    vim.b.pairs_surround_enabled = nil
    vim.o.selection = "inclusive"
    t.plugin.setup({
      rainbow = { enabled = false },
      surround = vim.tbl_deep_extend("force", { enabled = true }, overrides or {}),
    })
  end
  local function text()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  end
  local function input(name, before, keys, after, opts)
    t.test("surround " .. name, function()
      seed(before, opts)
      t.feed(keys)
      t.eq(text(), after)
    end)
  end

  input("word quotes", "│hello world", 'saiw"', '"hello" world')
  input("word brackets", "│hello", "saiw)", "(hello)")
  input("opening adds padding", "│hello", "saiw(", "( hello )")
  input("motion", "│hello world", "sa$]", "[hello world]")
  input("count before add repeats wrapper", "│hello world", '2saiw"', '""hello"" world')
  input("motion count", "│one two three", "sa2aw]", "[one two ]three")
  input("whole line retains indent", "  │hello  ", "sa_)", "  (hello)  ")
  input("multiline motion", "│one\ntwo", "saj)", "(one\ntwo)")
  input("Visual", "│hello world", 'viwsa"', '"hello" world')
  input("Visual reversed", "hell│o world", 'vbsa"', '"hello" world')
  input("Visual unicode", "│你好世界", 'vlsa"', '"你好"世界')
  input("unicode motion", "│你好", "saiw]", "[你好]")
  input("Visual composing character", "│éfoo", 'vsa"', '"é"foo')
  input("motion composing character", "│éfoo", 'saiw"', '"éfoo"')
  input("delete quotes", '"he│llo"', 'sd"', "hello")
  input("delete brackets", "(he│llo)", "sd)", "hello")
  input("opening trims padding", "(  he│llo  )", "sd(", "hello")
  input("closing keeps padding", "(  he│llo  )", "sd)", "  hello  ")
  input("replace", '"he│llo"', "sr\"'", "'hello'")
  input("replace padded", "(he│llo)", "sr)[", "[ hello ]")
  input("nested innermost", "((he│llo))", "sd)", "(hello)")
  input("nested count", "((he│llo))", "2sd)", "(hello)")
  input("nested count distinguishes outer", "((he│llo) world)", "2sd)", "(hello) world")
  input("nested count distinguishes inner", "((he│llo) world)", "sd)", "(hello world)")
  input("mixed bracket alias", "{[he│llo]}", "sdb", "{hello}")
  input("any quote alias", "'he│llo'", "sdq", "hello")
  input("escaped quote", '"a\\"b│c"', 'sd"', 'a\\"bc')
  input("cross line delete", "(one\n│two)", "sd)", "one\ntwo")
  input("Unicode delimiter", "│hello", "saiw«", "«hello«")
  input("Unicode delimiter delete", "«he│llo«", "sd«", "hello")
  input("no target", "│hello", "sd)", "hello")
  input("cancel add", "│hello", "saiw<Esc>", "hello")
  input("cancel target", "(he│llo)", "sd<Esc>", "(hello)")
  input("cancel replacement", "(he│llo)", "sr)<Esc>", "(hello)")
  input("search cover rejects next", "│x (hello)", "sd)", "x (hello)")
  input("search next suffix", "│x (hello)", "sdn)", "x hello")
  input("search previous suffix", "(hello) │x", "sdl)", "hello x")
  input("cover or next", "│x (hello)", "sd)", "x hello", { search_method = "cover_or_next" })
  input("range zero", "(one\n│two)", "sd)", "(one\ntwo)", { n_lines = 0 })
  input("scan budget", "(he│llo)", "sd)", "(hello)", { max_scan_bytes = 3 })
  input("tag nested", "<div><div>he│llo</div></div>", "sdt", "<div>hello</div>")
  input("tag nested outer count", "<div><div>he│llo</div></div>", "2sdt", "<div>hello</div>")
  input("tag quoted angle", '<a title="x>y">he│llo</a>', "sdt", "hello")
  input("tag selfclosing", "<div><br/>he│llo</div>", "sdt", "<br/>hello")
  input("tag add", "│hello", "saiwtspan class=red<CR>", "<span class=red>hello</span>")
  input("function add", "│hello", "saiwfprint<CR>", "print(hello)")
  input("function delete", "obj.call(he│llo)", "sdf", "hello")
  input("function replace", "obj.call(he│llo)", "srf]", "[hello]")
  input("function dot prompts once", "│one two", "saiwfprint<CR>W.", "print(one) print(two)")
  input("custom literals", "│hello", "saiw*", "**hello**", {
    custom_surroundings = {
      ["*"] = { input = { left = "**", right = "**" }, output = { left = "**", right = "**" } },
    },
  })
  input("custom delete", "**he│llo**", "sd*", "hello", {
    custom_surroundings = { ["*"] = { input = { left = "**", right = "**" } } },
  })
  input("prompt literals", "│hello", "saiw?BEGIN<CR>END<CR>", "BEGINhelloEND")
  input("empty braces", "(│)", "sr)]", "[]")
  input("undo add", "│hello", 'saiw"u', "hello")
  input("redo add", "│hello", 'saiw"u<C-r>', '"hello"')
  input("undo delete", "(he│llo)", "sd)u", "(hello)")
  input("undo replace", "(he│llo)", "sr)]u", "(hello)")
  input("dot add", "│one two", 'saiw"W.', '"one" "two"')
  input("dot delete", "(│one) (two)", "sd)w.", "one two")
  input("dot replace", "(│one) (two)", "sr)]W.", "[one] [two]")
  input("line selection default", "  │one\n  two", "Vjsa)", "  (one\n  two)")
  input(
    "respect line selection",
    "  │one\n  two",
    "Vjsa)",
    "  (\n    one\n    two\n  )",
    { respect_selection_type = true }
  )
  input(
    "respect block selection",
    "│abc\ndef",
    "<C-v>jlsa]",
    "[ab]c\n[de]f",
    { respect_selection_type = true }
  )

  input(
    "block Unicode",
    "│你好甲\n世界乙",
    "<C-v>jlsa]",
    "[你好]甲\n[世界]乙",
    { respect_selection_type = true }
  )
  input(
    "block short line",
    "ab│c\na",
    "<C-v>jsa]",
    "ab[c]\na[]",
    { respect_selection_type = true }
  )
  input("delete standalone wrapper lines", "  (\n    │one\n    two\n  )", "sd)", "  one\n  two")
  input("undo standalone deletion", "(\n  │one\n)", "sd)u", "(\n  one\n)")
  input("macro add", "│one two", 'qqsaiw"Wq@q', '"one" "two"')
  input("macro delete", "(│one) (two)", "qqsd)wq@q", "one two")
  input(
    "custom disabled",
    "│hello",
    "saiw)",
    "hello",
    { custom_surroundings = { [")"] = false } }
  )
  input("too many wrappers", "│hello", "20saiw]", "hello", { max_scan_bytes = 10 })
  input("empty buffer", "│", "sa_)", "()")
  input("blank line retains indent", "  │", "sa_)", "  ()")
  input("Visual count repeats wrappers", "│hello", "viw2sa]", "[[hello]]")
  input("cancel custom prompt", "│hello", "saiwf<Esc>", "hello")
  input("tag cancel", "│hello", "saiwt<Esc>", "hello")
  input("tag malformed", "<div><p>he│llo</div>", "sdt", "<div><p>hello</div>")
  input("find motion for delete", "(│hello)", "dsf)", "()")
  input("find motion Visual", "(│hello)", "vsf)y", "(hello)")

  t.test("surround highlight timers are buffer-local", function()
    seed("(he│llo)", { highlight_duration = 20 })
    t.feed("sh)")
    local first = vim.api.nvim_get_current_buf()
    vim.cmd("enew!")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(hello)" })
    vim.api.nvim_win_set_cursor(0, { 1, 2 })
    t.feed("sh)")
    local second = vim.api.nvim_get_current_buf()
    local ns = vim.api.nvim_get_namespaces()["pairs.surround"]
    vim.wait(150, function()
      return #vim.api.nvim_buf_get_extmarks(first, ns, 0, -1, {}) == 0
        and #vim.api.nvim_buf_get_extmarks(second, ns, 0, -1, {}) == 0
    end)
    t.eq(#vim.api.nvim_buf_get_extmarks(first, ns, 0, -1, {}), 0)
    t.eq(#vim.api.nvim_buf_get_extmarks(second, ns, 0, -1, {}), 0)
  end)
  t.test("surround structural limits reject entire target", function()
    local scan = require("pairs.surround_scan")
    t.eq(
      scan.find(
        string.rep("(", 257) .. "x" .. string.rep(")", 257),
        { left = "(", right = ")" },
        257,
        "cover"
      ),
      nil
    )
    t.eq(scan.find(string.rep("()", 10001), { left = "(", right = ")" }, 1, "cover"), nil)
    local started = vim.uv.hrtime()
    scan.find(string.rep("\\", 50000), { left = "\\", right = "\\" }, 1, "cover")
    assert(vim.uv.hrtime() - started < 2e9, "backslash scan exceeded bounded work budget")
  end)

  t.test("surround Visual exclusive", function()
    seed("│hello world")
    vim.o.selection = "exclusive"
    t.feed('v3lsa"')
    t.eq(text(), '"hel"lo world')
    vim.o.selection = "inclusive"
  end)
  t.test("surround undo does not merge earlier edit", function()
    seed("│one")
    t.feed('A two<Esc>0saiw"u')
    t.eq(text(), "one two")
    t.feed("u")
    t.eq(text(), "one")
  end)
  t.test("surround find cycles", function()
    seed("(he│llo)")
    t.feed("sf)")
    t.eq(vim.api.nvim_win_get_cursor(0), { 1, 6 })
    t.feed("sf)")
    t.eq(vim.api.nvim_win_get_cursor(0), { 1, 0 })
    t.feed("sF)")
    t.eq(vim.api.nvim_win_get_cursor(0), { 1, 6 })
  end)
  t.test("surround temporary highlights", function()
    seed("(he│llo)", { highlight_duration = 10 })
    t.feed("sh)")
    local ns = vim.api.nvim_get_namespaces()["pairs.surround"]
    t.eq(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), 2)
    vim.wait(100, function()
      return #vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}) == 0
    end)
    t.eq(#vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), 0)
  end)
  t.test("surround sn changes buffer search range", function()
    seed("│hello")
    t.feed("sn5<CR>")
    t.eq(vim.b.pairs_surround_config.n_lines, 5)
  end)
  t.test("surround custom text object mapping", function()
    seed("│hello world")
    vim.keymap.set("o", "iz", "iw", { remap = true })
    t.feed("saiz]")
    t.eq(text(), "[hello] world")
    vim.keymap.del("o", "iz")
  end)
  t.test("surround custom callback and buffer override", function()
    seed("│hello")
    vim.b.pairs_surround_config = {
      custom_surroundings = {
        x = {
          output = function()
            return { left = "BEGIN\n", right = "\nEND" }
          end,
          input = function()
            return { left = "BEGIN\n", right = "\nEND" }
          end,
        },
      },
    }
    t.feed("saiwx")
    t.eq(text(), "BEGIN\nhello\nEND")
    t.feed("j0sdx")
    t.eq(text(), "hello")
  end)
  t.test("surround optional vim-surround key layout", function()
    seed("│hello", { mappings = { add = "ys", delete = "ds", replace = "cs" } })
    t.feed("ysiw]")
    t.eq(text(), "[hello]")
    t.feed("ds]")
    t.eq(text(), "hello")
  end)
  t.test("surround Plug without default mapping", function()
    seed("│hello", { mappings = { add = "" } })
    t.eq(vim.fn.maparg("sa", "n"), "")
    vim.keymap.set("n", "gs", "<Plug>(pairs-surround-add)")
    t.feed("gsiw]")
    t.eq(text(), "[hello]")
    vim.keymap.del("n", "gs")
  end)
  t.test("surround buffer mapping takes precedence", function()
    seed("│hello")
    local cb = function() end
    vim.keymap.set("n", "sa", cb, { buffer = true })
    t.feed("sa")
    t.eq(text(), "hello")
    t.eq(vim.fn.maparg("sa", "n", false, true).callback, cb)
    vim.keymap.del("n", "sa", { buffer = true })
  end)
  t.test("surround filetype-only enable", function()
    seed("│hello")
    t.plugin.setup({
      surround = { enabled = false },
      filetypes = { text = { surround = { enabled = true } } },
    })
    t.feed("saiw]")
    t.eq(text(), "[hello]")
  end)
  t.test("surround disabled buffer", function()
    seed("(he│llo)")
    vim.b.pairs_surround_enabled = false
    t.feed("sd)")
    t.eq(text(), "(hello)")
  end)
  t.test("surround global toggle", function()
    seed("(he│llo)")
    t.plugin.disable()
    t.feed("sd)")
    t.eq(text(), "(hello)")
  end)
  t.test("surround preserves mappings and teardown ownership", function()
    t.plugin.teardown()
    local cb = function() end
    vim.keymap.set("n", "sd", cb)
    seed("│hello")
    t.eq(vim.fn.maparg("sd", "n", false, true).callback, cb)
    assert(vim.tbl_contains(s.status().conflicts, "n:sd"))
    local replacement = function() end
    vim.keymap.set("n", "sa", replacement)
    t.plugin.teardown()
    t.eq(vim.fn.maparg("sa", "n", false, true).callback, replacement)
    t.eq(vim.fn.maparg("sd", "n", false, true).callback, cb)
    vim.keymap.del("n", "sa")
    vim.keymap.del("n", "sd")
    t.eq(vim.fn.maparg("sr", "n"), "")
  end)
  t.test("surround repeated setup", function()
    seed("│hello")
    t.plugin.setup({ surround = { enabled = true } })
    t.feed("saiw]")
    t.eq(text(), "[hello]")
  end)
  t.test("surround invalid setup preserves mappings", function()
    seed("│hello")
    t.eq(pcall(t.plugin.setup, { surround = { n_lines = -1 } }), false)
    t.feed("saiw]")
    t.eq(text(), "[hello]")
  end)
  t.test("surround default disabled", function()
    t.plugin.teardown()
    t.plugin.setup()
    t.eq(s.status().mappings, 0)
  end)
end

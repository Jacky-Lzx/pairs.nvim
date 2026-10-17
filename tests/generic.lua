return function(t)
  local plugin = t.plugin
  local function opts(open, close, flags)
    return {
      rainbow = { enabled = false },
      multi_pairs = { [open] = vim.tbl_extend("force", { close = close }, flags or {}) },
    }
  end
  local function input(name, before, keys, after, open, close, flags, ft, buffer)
    t.test("generic " .. name, function()
      t.input(before, keys, after, opts(open, close, flags), ft or "text", buffer)
    end)
  end
  input("bold opens", "│", "**", "**│**", "**", "**")
  input("strike opens", "│", "~~", "~~│~~", "~~", "~~")
  input("comment opens", "│", "/*", "/*│*/", "/*", "*/")
  input("asymmetric opens", "│", "<<", "<<│>>", "<<", ">>")
  input("word delimiters", "│", "BEGIN", "BEGIN│END", "BEGIN", "END")
  input("partial native brackets", "│", "[[", "[[│]]", "[[", "]]")
  input("partial nested native brackets", "│", "(((", "(((│)))", "(((", ")))")
  input("skip every comment closer character", "/* hello│*/", "*/", "/* hello*/│", "/*", "*/")
  input("skip bold", "**hello│**", "**", "**hello**│", "**", "**")
  input("skip word closer", "BEGINhello│END", "END", "BEGINhelloEND│", "BEGIN", "END")
  input("skip disabled", "**hello│**", "*", "**hello*│**", "**", "**", { skip = false })
  input("open disabled", "│", "**", "**│", "**", "**", { open = false })
  input("delete empty", "**│**", "<BS>", "│", "**", "**")
  input("delete asymmetric", "/*│*/", "<BS>", "│", "/*", "*/")
  input("delete disabled", "**│**", "<BS>", "*│**", "**", "**", { delete = false })
  input("nonempty backspace remains native", "**x│**", "<BS>", "**│**", "**", "**")
  input("escaped opener", "\\│", "**", "\\**│", "**", "**")
  input("word neighbor blocks", "│hello", "**", "**│hello", "**", "**")
  input("existing closer", "│**", "**", "**│**", "**", "**")
  input("space padding", "**│**", " ", "** │ **", "**", "**", { space = true })
  input("space padding removal", "** │ **", "<BS>", "**│**", "**", "**", { space = true })
  input("space only first mirrored", "**│**", "  ", "**  │ **", "**", "**", { space = true })
  input("newline enabled", "/*│*/", "<CR>", "/*\n  │\n*/", "/*", "*/", { newline = true })
  input("newline default native", "**│**", "<CR>", "**\n│**", "**", "**")
  input(
    "newline trims padding",
    "/* │ */",
    "<CR>",
    "/*\n  │\n*/",
    "/*",
    "*/",
    { newline = true, space = true }
  )
  input(
    "newline closing skip",
    "/*│*/",
    "<CR>x<Down><Home>*/",
    "/*\n  x\n*/│",
    "/*",
    "*/",
    { newline = true }
  )
  input("string guarded", '"│"', "**", '"**│"', "**", "**")
  input(
    "string explicitly enabled",
    '"│"',
    "**",
    '"**│**"',
    "**",
    "**",
    { contexts = { "string" } }
  )
  input("comment guarded", "# │", "**", "# **│", "**", "**", nil, "python")
  input(
    "comment explicitly enabled",
    "# │",
    "**",
    "# **│**",
    "**",
    "**",
    { contexts = { "comment" } },
    "python"
  )
  input("condition rejects", "│", "**", "**│", "**", "**", {
    condition = function()
      return false
    end,
  })
  input("condition sees action", "│", "**", "**│**", "**", "**", {
    condition = function(ctx, action)
      return ctx.filetype == "text" and action == "open"
    end,
  })
  input("condition exception inert", "│", "**", "**│", "**", "**", {
    condition = function()
      error("condition failure")
    end,
  })
  input("UTF-8 body", "**你好│**", "**", "**你好**│", "**", "**")
  input("nested asymmetric", "<<a<<b│>>>>", ">>", "<<a<<b>>│>>", "<<", ">>")
  input("finished closer never starts new pair", "/*x*/│", "*", "/*x*/*│", "/*", "*/")
  input("finished bold never starts new pair", "**x**│", "*", "**x***│", "**", "**")
  input(
    "comment leaders on newline",
    "/*│*/",
    "<CR>",
    "/*\n  │\n*/",
    "/*",
    "*/",
    { newline = true },
    "c",
    { formatoptions = "r", comments = "s1:/*,mb:*,ex:*/" }
  )

  t.test("generic undo redo and dot", function()
    local entry = t.seed("│\n")
    plugin.setup(opts("**", "**"))
    t.feed(entry .. "**hello<Esc>")
    t.eq(vim.api.nvim_get_current_line(), "**hello**")
    t.feed("u")
    t.eq(vim.api.nvim_get_current_line(), "")
    t.feed("<C-r>")
    t.eq(vim.api.nvim_get_current_line(), "**hello**")
    t.feed("j0.")
    t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "**hello**", "**hello**" })
  end)
  t.test("generic multiline dot uses native expansion", function()
    local entry = t.seed("│\n")
    plugin.setup(opts("/*", "*/", { newline = true }))
    t.feed(entry .. "/*<CR>x<Esc>")
    t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "/*", "  x", "*/", "" })
    t.feed("G0.")
    t.eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "/*", "  x", "*/", "/*", "  x", "*/" })
  end)
  t.test("generic live buffer flags", function()
    local entry = t.seed("│")
    plugin.setup(opts("**", "**"))
    vim.b.pairs_multi_rules = { ["**"] = { open = false } }
    t.feed(entry .. "**<Esc>")
    t.eq(vim.api.nvim_get_current_line(), "**")
  end)
  t.test("generic filetype rules", function()
    local entry = t.seed("│", "markdown")
    plugin.setup({ filetypes = { markdown = { multi_pairs = { ["**"] = {} } } } })
    t.feed(entry .. "**<Esc>")
    t.eq(vim.api.nvim_get_current_line(), "****")
  end)
  t.test("generic definition shared with surround", function()
    t.seed("│hello", "text")
    plugin.setup(
      vim.tbl_extend(
        "force",
        opts("**", "**", { surround = "*", open = false }),
        { surround = { enabled = true } }
      )
    )
    t.feed("saiw*")
    t.eq(vim.api.nvim_get_current_line(), "**hello**")
    t.feed("sd*")
    t.eq(vim.api.nvim_get_current_line(), "hello")
  end)
  t.test("generic ambiguity rejected before setup", function()
    plugin.teardown()
    t.eq(pcall(plugin.setup, { multi_pairs = { ["**"] = {}, ["***"] = {} } }), false)
    t.eq(pcall(plugin.setup, { multi_pairs = { ["xx"] = { close = "\n" } } }), false)
    t.eq(pcall(plugin.setup, { multi_pairs = { ["xx"] = { condition = true } } }), false)
    t.eq(pcall(plugin.setup, { multi_pairs = { ["xx"] = { contexts = false } } }), false)
    t.eq(
      pcall(
        plugin.setup,
        { multi_pairs = { ["ab"] = { close = "END" }, ["cd"] = { close = "END" } } }
      ),
      false
    )
    t.eq(pcall(plugin.setup, { multi_pairs = { ["``"] = {}, ["```"] = {} } }), false)
    local rules = {}
    for i = 1, 129 do
      rules["x" .. i .. "x"] = {}
    end
    t.eq(pcall(plugin.setup, { multi_pairs = rules }), false)
  end)
  t.test("generic scan budget never guesses closer", function()
    t.input(
      "**x│**",
      "**",
      "**x**│**",
      vim.tbl_extend("force", opts("**", "**"), { max_scan_bytes = 3 }),
      "text"
    )
  end)
  t.test("generic explicit surround override wins", function()
    t.seed("│hello", "text")
    plugin.setup(vim.tbl_extend("force", opts("**", "**", { surround = "*" }), {
      surround = {
        enabled = true,
        custom_surroundings = { ["*"] = { output = { left = "[", right = "]" } } },
      },
    }))
    t.feed("saiw*")
    t.eq(vim.api.nvim_get_current_line(), "[hello]")
  end)
  t.test("generic trace retains contexts and discloses callback limits", function()
    local trace = require("pairs.trace")
    local entry = t.seed("│", "text")
    plugin.setup(opts("**", "**", {
      condition = function()
        return true
      end,
      surround = "*",
    }))
    trace.clear()
    trace.start()
    t.feed(entry .. "**<Esc>")
    trace.stop()
    local records = trace.entries()
    local record = records[#records]
    t.eq(record.options.filetypes.text.multi_pairs["**"].contexts, { "code" })
    t.eq(record.options.filetypes.text.multi_pairs["**"].condition, nil)
    assert(vim.inspect(record.limitations):find("Custom multi%-pair conditions"))
  end)
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    local markdown = pcall(vim.treesitter.language.add, "markdown")
    if markdown then
      local combined = {
        treesitter = true,
        rainbow = { enabled = false },
        filetypes = {
          markdown = {
            multi_pairs = {
              ["~~~"] = {},
              ["~~"] = {
                condition = function(ctx)
                  return not ctx.fence
                end,
              },
            },
          },
        },
      }
      t.test("generic strikeout coexists with tilde fences", function()
        t.input("│", "~~~<CR>", "~~~\n│\n~~~", combined, "markdown")
      end)
      t.test("generic inline strikeout is preserved", function()
        t.input("hello │", "~~text~~", "hello ~~text~~│", combined, "markdown")
      end)
    end
    t.test("generic parser typed comment", function()
      t.input(
        "│",
        "/*",
        "/*│*/",
        vim.tbl_extend("force", opts("/*", "*/"), { treesitter = true }),
        "javascript"
      )
    end)
    t.test("generic parser masks code string contents", function()
      local entry = t.seed('[["a]]b"│]]', "javascript")
      plugin.setup(vim.tbl_extend("force", opts("[[", "]]"), { treesitter = true }))
      vim.treesitter.get_parser(0):parse()
      t.eq(plugin.explain("]", { assume_insert = true }).reason, "generic_closer")
      t.feed(entry .. "]]<Esc>")
      t.eq(vim.api.nvim_get_current_line(), '[["a]]b"]]')
    end)
    t.test("generic parser-proven comment maintenance", function()
      local entry = t.seed("/*│*/", "javascript")
      plugin.setup(vim.tbl_extend("force", opts("/*", "*/"), { treesitter = true }))
      vim.treesitter.get_parser(0):parse()
      t.feed(entry .. "<BS><Esc>")
      t.eq(vim.api.nvim_get_current_line(), "")
    end)
    t.test("generic shared literal comment survives surround syntax", function()
      t.seed("/*he│llo*/", "javascript")
      plugin.setup(
        vim.tbl_extend(
          "force",
          opts("/*", "*/", { surround = "c" }),
          { surround = { enabled = true, treesitter = true } }
        )
      )
      t.feed("sdc")
      t.eq(vim.api.nvim_get_current_line(), "hello")
    end)
  end
end

-- Behavioral guards for setup metadata reuse and the single-scan empty actions.
return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local function explain(key)
    return plugin.explain(key, { assume_insert = true })
  end
  test("prepared rules: buffer replacement and removal stay live", function()
    seed("│")
    plugin.setup()
    eq(explain('"').action, "pair")
    vim.b.pairs_rules = { ['"'] = { open = false } }
    eq(explain('"').action, "pass")
    vim.b.pairs_rules = { ['"'] = { open = true } }
    eq(explain('"').action, "pair")
    vim.b.pairs_rules = nil
    eq(explain('"').action, "pair")
  end)
  test("prepared rules: another buffer never inherits overrides", function()
    seed("│")
    plugin.setup()
    local first = vim.api.nvim_get_current_buf()
    vim.b.pairs_rules = { ['"'] = { open = false } }
    eq(explain('"').action, "pass")
    vim.cmd("enew!")
    vim.bo.filetype = "lua"
    eq(explain('"').action, "pair")
    vim.api.nvim_set_current_buf(first)
    eq(explain('"').action, "pass")
  end)
  test("prepared rules: metadata follows filetype changes", function()
    seed("│")
    plugin.setup({ filetypes = { python = { pairs = { ['"'] = { open = false } } } } })
    eq(explain('"').action, "pair")
    vim.bo.filetype = "python"
    eq(explain('"').action, "pass")
    vim.bo.filetype = "lua"
    eq(explain('"').action, "pair")
  end)
  test("prepared rules: re-setup replaces metadata without mutating options", function()
    seed("│")
    local opts = { pairs = { ['"'] = { open = false } } }
    local original = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, original)
    eq(explain('"').action, "pass")
    opts.pairs['"'].open = true
    eq(explain('"').action, "pass")
    plugin.setup(opts)
    eq(explain('"').action, "pair")
    eq(pcall(plugin.setup, { pairs = { ['"'] = { close = "invalid" } } }), false)
    eq(explain('"').action, "pair")
  end)
  test("prepared rules: invalid live rules diagnose and recover", function()
    seed("│")
    plugin.setup()
    vim.b.pairs_rules = { ['"'] = { close = "invalid" } }
    eq(explain('"').reason, "context_error")
    vim.b.pairs_rules = nil
    eq(explain('"').action, "pair")
  end)
  test("prepared rules: public resolvers return independent tables", function()
    local config = require("pairs.config")
    local candidate = config.build({ multi_pairs = { ['"""'] = {} } })
    config.resolve(candidate, "lua")['"'].open = false
    config.resolve_multi(candidate, "python")['"""'].open = false
    eq(config.resolve(candidate, "lua")['"'].open, true)
    eq(config.resolve_multi(candidate, "python")['"""'].open, true)
    eq(config.capture(candidate, "lua").rules['"'].open, true)
    eq(config.capture(candidate, "python").multi_rules['"""'].open, true)
  end)
  test("prepared rules: backtick quote policy never leaks across filetypes", function()
    seed("`│ ")
    plugin.setup()
    vim.bo.filetype = "javascript"
    eq(explain("(").reason, "string")
    vim.bo.filetype = "lua"
    eq(explain("(").action, "pair")
    vim.bo.filetype = "go"
    eq(explain("(").reason, "string")
    vim.bo.filetype = "lua"
    eq(explain("(").action, "pair")
  end)
  test("prepared rules: disabled delimiter requires a complete buffer rule", function()
    seed("│")
    plugin.setup({ pairs = { ["("] = false } })
    vim.b.pairs_rules = { ["("] = { open = true } }
    eq(explain("(").action, "pass")
    vim.b.pairs_rules = { ["("] = { close = ")", open = true } }
    eq(explain("(").action, "pair")
    vim.b.pairs_rules = nil
    eq(explain("(").action, "pass")
  end)
  test("prepared rules: live multi rules still validate on every capture", function()
    seed("│", "python")
    plugin.setup({ multi_pairs = { ['"""'] = {} } })
    vim.b.pairs_multi_rules = { ['"""'] = { open = false } }
    local config = require("pairs.config").build({ multi_pairs = { ['"""'] = {} } })
    local context = require("pairs.context")
    eq(context.capture(config, true, true).multi_rules['"""'].open, false)
    vim.b.pairs_multi_rules = { ['"""'] = { open = true } }
    eq(context.capture(config, true, true).multi_rules['"""'].open, true)
    vim.b.pairs_multi_rules = { ['"""'] = { close = "invalid" } }
    eq(explain('"').reason, "context_error")
    vim.b.pairs_multi_rules = nil
    eq(context.capture(config, true, true).multi_rules['"""'].open, true)
  end)
  test("prepared rules: mutating one override table never yields stale metadata", function()
    local config = require("pairs.config")
    local candidate = config.build()
    local override = { ['"'] = { open = false } }
    eq(config.capture(candidate, "lua", override).rules['"'].open, false)
    override['"'].open = true
    eq(config.capture(candidate, "lua", override).rules['"'].open, true)
    override['"'].close = "invalid"
    eq(pcall(config.capture, candidate, "lua", override), false)
    eq(config.capture(candidate, "lua").rules['"'].open, true)
  end)
  test("prepared rules: predicate multi-rule changes apply in the same capture", function()
    seed("│", "python")
    local enabled = false
    local config = require("pairs.config").build({
      multi_pairs = { ['"""'] = {} },
      enabled = function()
        vim.b.pairs_multi_rules = { ['"""'] = { open = enabled } }
        return true
      end,
    })
    local context = require("pairs.context")
    eq(context.capture(config, true, true).multi_rules['"""'].open, false)
    enabled = true
    eq(context.capture(config, true, true).multi_rules['"""'].open, true)
  end)
  test("single scan: long-prefix deletion", function()
    local prefix = string.rep("x ", 1000)
    input(prefix .. "(│)", "<BS>", prefix .. "│")
  end)
  test("single scan: long-prefix Enter", function()
    local prefix = "  " .. string.rep("x ", 1000)
    input(prefix .. "{│}", "<CR>x", prefix .. "{\n    x│\n  }")
  end)
  test("single scan: final byte can complete a Lua comment marker", function()
    input("--│=", "<BS>", "-│=", { pairs = { ["-"] = { close = "=" } } })
  end)
  test("single scan: final opener can begin a Python comment", function()
    input("#│@", "<BS>", "│@", { pairs = { ["#"] = { close = "@" } } }, "python")
  end)
  test("single scan: the full cursor position retains the scan limit", function()
    input("x (│)", "<BS>", "x │)", { max_scan_bytes = 2 })
    input("(│)", "<BS>", "│", { max_scan_bytes = 1 })
  end)
  test("steady mapped stream: strings, nesting, deletion, undo and dot", function()
    local pattern = '("x")[y](<BS>'
    local expected = string.rep('("x")[y]', 30)
    input("│", string.rep(pattern, 30), expected .. "│")
    feed("u")
    eq(vim.api.nvim_get_current_line(), "")
    feed("<C-r>")
    eq(vim.api.nvim_get_current_line(), expected)
    feed("u.")
    eq(vim.api.nvim_get_current_line(), expected)
  end)
end

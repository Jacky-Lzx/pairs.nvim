return function(h)
  local test, seed, eq, plugin = h.test, h.seed, h.eq, h.plugin
  local config = require("pairs.config")
  local opts = {
    treesitter = true,
    tex_environments = { proof = "text" },
    multi_pairs = { ["$$"] = {}, ["\\("] = {}, ["\\["] = {} },
  }

  test("TeX metadata: public copies and live overrides remain independent", function()
    local candidate = config.build({
      tex_environments = { proof = "text" },
      filetypes = { tex = { tex_environments = { mycode = "literal" } } },
    })
    local public = config.resolve_tex(candidate, "tex")
    public.proof, public.mycode = "math", false
    eq(config.capture_tex(candidate, "tex").environments.proof, "text")
    eq(config.capture_tex(candidate, "tex").custom_literal, true)
    eq(config.capture_tex(candidate, "plaintex").custom_literal, false)
    local live = { proof = "literal" }
    eq(config.capture_tex(candidate, "plaintex", live).custom_literal, true)
    live.proof = false
    eq(config.capture_tex(candidate, "plaintex", live).environments.proof, false)
    eq(config.capture_tex(candidate, "plaintex", live).custom_literal, false)
    live.proof = "invalid"
    eq(pcall(config.capture_tex, candidate, "plaintex", live), false)
    eq(config.capture_tex(candidate, "plaintex").environments.proof, "text")
  end)

  test("TeX metadata: static capture avoids repeated validation", function()
    local candidate = config.build(opts)
    local environments = require("pairs.tex_env")
    local original = environments.validate
    environments.validate = function()
      error("setup-owned environments were validated again")
    end
    local ok, err = pcall(function()
      eq(config.capture_tex(candidate, "tex").environments.proof, "text")
      eq(config.capture_tex(candidate, "plaintex").environments.document, "text")
    end)
    environments.validate = original
    assert(ok, err)
  end)

  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end

  test("TeX native keys: ordinary backslash and deletion avoid parser work", function()
    seed("wordx│ ", "tex")
    plugin.setup(opts)
    local syntax = require("pairs.syntax")
    local original = syntax.capture
    syntax.capture = function()
      error("native input requested parser context")
    end
    local ok, err = pcall(function()
      for _, key in ipairs({ "\\", "<BS>" }) do
        local result = plugin.explain(key, { assume_insert = true })
        eq(result.action, "pass")
        assert(result.reason ~= "context_error", result.error)
      end
    end)
    syntax.capture = original
    assert(ok, err)
  end)

  test("TeX native keys: custom single-character rules retain their actions", function()
    h.input("│", "\\", "\\│~", {
      treesitter = true,
      pairs = { ["\\"] = { close = "~" } },
    }, "tex")
    h.input("@│\\", "\\", "@\\│", {
      treesitter = true,
      pairs = { ["@"] = { close = "\\" } },
    }, "tex")
    h.input("x│y", "<BS>", "│", {
      treesitter = true,
      pairs = { x = { close = "y" } },
    }, "tex")
  end)

  test("TeX metadata: enabled predicate changes environment in the same capture", function()
    seed("\\begin{proof}\n│\n\\end{proof}", "tex")
    local mode = "literal"
    plugin.setup(vim.tbl_extend("force", opts, {
      enabled = function()
        vim.b.pairs_tex_environments = { proof = mode }
        return true
      end,
    }))
    eq(plugin.explain("(", { assume_insert = true }).action, "pass")
    mode = "text"
    eq(plugin.explain("(", { assume_insert = true }).action, "pair")
  end)

  local function without_wide_fields(root, run)
    local methods = getmetatable(root).__index
    local original = methods.field
    methods.field = function(node, name)
      assert(node:child_count() <= 256, "field lookup enumerated a large syntax node: " .. name)
      return original(node, name)
    end
    local ok, err = pcall(run)
    methods.field = original
    assert(ok, err)
  end

  for _, ending in ipairs({ true, false }) do
    test(
      "TeX traversal: large " .. (ending and "complete" or "unfinished") .. " document",
      function()
        local doc = "\\begin{document}\n"
          .. string.rep("Text $x$ and \\textbf{value}.\n", 1000)
          .. "word \\│ "
          .. (ending and "\n\\end{document}" or "")
        seed(doc, "tex")
        plugin.setup(opts)
        local root = vim.treesitter.get_parser(0, "latex"):parse(true)[1]:root()
        without_wide_fields(root, function()
          local result = plugin.explain("(", { assume_insert = true })
          assert(result.reason ~= "context_error", result.error)
          eq(result.action, ending and "pair" or "pass")
        end)
      end
    )
  end

  test("TeX traversal: long command retains raw argument protection", function()
    seed("\\textbf{" .. string.rep("\\url{x}", 300) .. "\\url{│}}", "tex")
    plugin.setup(opts)
    local root = vim.treesitter.get_parser(0, "latex"):parse(true)[1]:root()
    without_wide_fields(root, function()
      local result = plugin.explain("(", { assume_insert = true })
      assert(result.reason ~= "context_error", result.error)
      eq(result.action, "pass")
    end)
  end)

  test("TeX traversal: excessive ancestry preserves input", function()
    seed(
      string.rep("\\begin{center}\n", 260) .. "│\n" .. string.rep("\\end{center}\n", 260),
      "tex"
    )
    plugin.setup(opts)
    eq(plugin.explain("(", { assume_insert = true }).action, "pass")
  end)

  test("TeX raw spans: multiline byte positions and masking", function()
    local lines = { '标题 \\textbf{\\url{a"}', "  \\path{中}", "  \\url{c%20} " }
    seed(table.concat(lines, "\n") .. "│}", "tex")
    plugin.setup(opts)
    local root = vim.treesitter.get_parser(0, "latex"):parse(true)[1]:root()
    local args = require("pairs.tex_args")
    local result = args.capture(root, 2, #lines[3], lines[3] .. "}", 0)
    eq(#result.spans, 3)
    for index, payload in ipairs({ 'a"', "中", "c%20" }) do
      local start = assert(lines[index]:find(payload, 1, true)) - 1
      local span = result.spans[index]
      eq({ span.start_row, span.start_col, span.end_row, span.end_col }, {
        index - 1,
        start,
        index - 1,
        start + #payload,
      })
      eq(args.raw_comment(result, index - 1, start), true)
      eq(args.raw_comment(result, index - 1, start + #payload), false)
    end
    eq(result.lex_line, "  \\url{    } }")
    eq(args.raw_comment(result, 2, #lines[3]), false)
  end)
end

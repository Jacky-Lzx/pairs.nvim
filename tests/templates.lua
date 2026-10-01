return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local rule = { pairs = { ["`"] = { close = "`" } }, multi_pairs = { ["${"] = {} } }
  local opts = { treesitter = true, filetypes = {} }
  for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
    opts.filetypes[ft] = vim.deepcopy(rule)
  end
  local function options(ft, area, delimiter, override)
    local copy = vim.deepcopy(opts)
    copy.filetypes[ft][area][delimiter] = override
    return copy
  end
  test("template: interpolation closer is validated", function()
    eq(pcall(plugin.setup, { multi_pairs = { ["${"] = { close = "]" } } }), false)
  end)
  test("template: setup defaults and mappings without mutating options", function()
    seed("│", "javascript")
    local before = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, before)
    eq(vim.fn.maparg("`", "i", false, true).desc, "pairs.nvim `")
    plugin.teardown()
    eq(vim.fn.maparg("`", "i"), "")
  end)
  test("template: multi-only interpolation registers brace keys", function()
    seed("│", "javascript")
    local copy = vim.deepcopy(opts)
    copy.pairs = { ["{"] = false }
    plugin.setup(copy)
    eq(vim.fn.maparg("{", "i", false, true).desc, "pairs.nvim {")
    eq(vim.fn.maparg("}", "i", false, true).desc, "pairs.nvim }")
  end)
  test("template: other filetypes retain existing behavior", function()
    input("│", "`", "`│", opts, "lua")
  end)
  test("template: default configuration leaves backticks literal", function()
    input("│", "`", "`│", { treesitter = true }, "javascript")
  end)
  test("template: interpolation does not alter missing-parser input", function()
    input("`$│`", "{", "`${│`", opts, "pairs_missing_parser")
  end)
  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
    local function case(label, before, keys, after, config, bo)
      test("template " .. ft .. ": " .. label, function()
        input(before, keys, after, config or opts, ft, bo)
      end)
    end
    case("opening", "│", "`", "`│`")
    case("continuous closing", "│", "`body`", "`body`│")
    case("tagged identifier", "html│", "`body`", "html`body`│")
    case("tagged call", "factory()│", "`body`", "factory()`body`│")
    case("tagged member", "obj.tag│", "`body`", "obj.tag`body`│")
    case("delete empty", "`│`", "<BS>", "│")
    case("delete retains tag", "html`│`", "<BS>", "html│")
    case("nonempty backspace", "`ab│`", "<BS>", "`a│`")
    case("closing after multiline body", "`a\nb│`", "`", "`a\nb`│")
    case("escaped backtick stays body text", "`a │\\` b`", "`", "`a `│\\` b`")
    case("escaped input", "`\\│`", "`", "`\\`│`")
    case("literal quotes", "`│`", "'\"", "`'\"│`")
    case("literal braces", "`│`", "{}", "`{}│`")
    case("newlines remain ordinary", "`│`", "<CR>", "`\n│`")
    case("interpolation opening", "`$│`", "{", "`${│}`")
    case("continuous interpolation", "│", "`${name}`", "`${name}`│")
    case("interpolation close", "`${name│}`", "}", "`${name}│`")
    case("empty interpolation close", "`${│}`", "}", "`${}│`")
    case("interpolation deletion", "`${│}`", "<BS>", "`│`")
    case("nonempty interpolation deletion", "`${ab│}`", "<BS>", "`${a│}`")
    case("expression quote pair", "`${│}`", '"x"', '`${"x"│}`')
    case("nested braces", "`${│}`", "({x: 1})}", "`${({x: 1})}│`")
    case("nested template", "│", "`${`inner ${value}`}`", "`${`inner ${value}`}`│")
    case("string expression protects interpolation", '`${"$│"}`', "{", '`${"${│"}`')
    case("expression comment", "`${/* │ */ x}`", "`", "`${/* `│ */ x}`")
    case("line comment", "// │", "`", "// `│")
    case("block comment", "/* │ */", "`", "/* `│ */")
    case("regex contents", "/a │ b/", "`", "/a `│ b/")
    if ft ~= "typescript" then
      case("JSX text", "<div>a │ b</div>", "`", "<div>a `│ b</div>")
    end
    case("string prevents template opening", '"│"', "`", '"`│"')
    case("before existing text", "│word", "`", "`│word")
    case("escaped dollar", "`\\$│`", "{", "`\\${│`")
    case("even dollar escaping", "`\\\\$│`", "{", "`\\\\${│}`")
    case("before text interpolation stays literal", "`$│word`", "{", "`${│word`")
    case("existing brace is not duplicated", "`$│}`", "{", "`${│}`")
    case("body brace is not skipped", "`a │} b`", "}", "`a }│} b`")
    case("after complete template", "`body` + │", "`", "`body` + `│`")
    case(
      "opening disabled",
      "│",
      "`",
      "`│",
      options(ft, "pairs", "`", { close = "`", open = false })
    )
    case(
      "skip disabled",
      "`body│`",
      "`",
      "`body`│`",
      options(ft, "pairs", "`", { close = "`", skip = false })
    )
    case(
      "delete disabled",
      "`│`",
      "<BS>",
      "│`",
      options(ft, "pairs", "`", { close = "`", delete = false })
    )
    case(
      "interpolation opening disabled",
      "`$│`",
      "{",
      "`${│`",
      options(ft, "multi_pairs", "${", { open = false })
    )
    case(
      "interpolation skip disabled",
      "`${name│}`",
      "}",
      "`${name}│}`",
      options(ft, "multi_pairs", "${", { skip = false })
    )
    case(
      "interpolation deletion disabled",
      "`${│}`",
      "<BS>",
      "`$│}`",
      options(ft, "multi_pairs", "${", { delete = false })
    )
    case(
      "interpolation rule disabled",
      "`$│`",
      "{",
      "`${│`",
      options(ft, "multi_pairs", "${", false)
    )
    case("interpolation Enter", "`${│}`", "<CR>name", "`${\n  name│\n}`")
    case(
      "interpolation Enter disabled",
      "`${│}`",
      "<CR>",
      "`${\n│}`",
      options(ft, "multi_pairs", "${", { newline = false })
    )
    case("multiline expression close", "`${\nname│\n}`", "<Down><Home>}", "`${\nname\n}│`")
    case(
      "disabled plugin",
      "│",
      "`",
      "`│",
      vim.tbl_deep_extend("force", opts, { enabled = false })
    )
    case("incomplete template stays literal", "`unterminated $│", "{", "`unterminated ${│")
    case(
      "multi-only interpolation",
      "`$│`",
      "{",
      "`${│}`",
      vim.tbl_deep_extend("force", opts, {
        pairs = { ["{"] = false },
      })
    )
    test("template " .. ft .. ": undo redo and dot", function()
      input("│", '`${fn("x")}`', '`${fn("x")}`│', opts, ft)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
      feed("<C-r>0.")
      eq(vim.api.nvim_get_current_line(), '`${fn("x")}``${fn("x")}`')
    end)
    test("template " .. ft .. ": interpolation multiline repeat", function()
      input("│", "`${<CR>name", "`${\n  name│\n}`", opts, ft)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
      feed("<C-r>gg0.")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "`${", "  name", "}``${", "  name", "}`" })
    end)
    test("template " .. ft .. ": buffer multi override", function()
      local entry = seed("`$│`", ft)
      plugin.setup(opts)
      vim.b.pairs_multi_rules = { ["${"] = { open = false } }
      feed(entry .. "{<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "`${│`")
    end)
    test("template " .. ft .. ": missing parser preserves input", function()
      local original = vim.treesitter.get_parser
      vim.treesitter.get_parser = function()
        return nil
      end
      local ok, err = pcall(input, "`$│`", "{", "`${│`", opts, ft)
      vim.treesitter.get_parser = original
      assert(ok, err)
    end)
    test("template " .. ft .. ": pending parser preserves input", function()
      local entry = seed("`$│`", ft)
      plugin.setup(opts)
      local language = ({ javascriptreact = "javascript", typescriptreact = "tsx" })[ft] or ft
      local parser = vim.treesitter.get_parser(0, language)
      local parse = parser.parse
      parser.parse = function()
        return nil
      end
      local ok, err = pcall(function()
        feed(entry .. "{<Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "`${│`")
      end)
      parser.parse = parse
      assert(ok, err)
    end)
    test("template " .. ft .. ": injected language keeps outer boundaries", function()
      local language = ({ javascriptreact = "javascript", typescriptreact = "tsx" })[ft] or ft
      vim.treesitter.query.set(
        language,
        "injections",
        [[
        (call_expression
          function: (identifier) @_tag
          arguments: (template_string (string_fragment) @injection.content)
          (#eq? @_tag "c")
          (#set! injection.language "c"))
      ]]
      )
      local ok, err = pcall(function()
        local entry = seed("c`int x;\nint y;│`", ft)
        plugin.setup(opts)
        local parser = vim.treesitter.get_parser(0, language)
        parser:parse(true)
        eq(parser:language_for_range({ 1, 5, 1, 5 }):lang(), "c")
        feed(entry .. "`<Cmd>lua pairs_test_capture()<CR><Esc>")
        eq(_G.pairs_test_result, "c`int x;\nint y;`│")
        input("c`int x;\n$│`", "{", "c`int x;\n${│}`", opts, ft)
      end)
      vim.treesitter.query.set(language, "injections", nil)
      assert(ok, err)
    end)
  end
end

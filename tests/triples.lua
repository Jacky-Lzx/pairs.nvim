return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local double, single = string.rep('"', 3), string.rep("'", 3)
  local opts = {
    treesitter = true,
    filetypes = {
      python = { multi_pairs = { [double] = { close = double }, [single] = { close = single } } },
    },
  }
  local function options(quote, overrides)
    local copy = vim.deepcopy(opts)
    copy.filetypes.python.multi_pairs[string.rep(quote, 3)] = overrides
    return copy
  end

  test("multi: unsupported delimiters are rejected", function()
    eq(pcall(plugin.setup, { multi_pairs = { ["%%"] = { close = "%%" } } }), false)
  end)
  test("multi: mismatched closer is rejected", function()
    eq(pcall(plugin.setup, { multi_pairs = { [double] = { close = single } } }), false)
  end)
  test("multi: invalid action flag is rejected", function()
    eq(pcall(plugin.setup, options('"', { newline = "yes" })), false)
  end)
  test("multi: setup does not mutate options", function()
    local before = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, before)
  end)
  test("multi: mappings exist without the short quote rule", function()
    seed("│", "python")
    local copy = vim.deepcopy(opts)
    copy.pairs = { ['"'] = false, ["'"] = false }
    plugin.setup(copy)
    eq(vim.fn.maparg('"', "i", false, true).desc, 'pairs.nvim "')
    eq(vim.fn.maparg("'", "i", false, true).desc, "pairs.nvim '")
  end)

  if not vim.env.PAIRS_TEST_PARSER_ROOT then
    return
  end
  for _, quote in ipairs({ '"', "'" }) do
    local token = string.rep(quote, 3)
    local name = quote == '"' and "double" or "single"
    local function case(label, before, keys, after, config, ft, bo)
      test("triple " .. name .. ": " .. label, function()
        input(before, keys, after, config or opts, ft or "python", bo)
      end)
    end
    case("continuous upgrade", "│", token, token .. "│" .. token)
    case(
      "upgrade existing empty short string",
      quote .. quote .. "│",
      quote,
      token .. "│" .. token
    )
    case(
      "body and closing sequence",
      "│",
      token .. "body" .. token,
      token .. "body" .. token .. "│"
    )
    case(
      "skip first closing quote",
      token .. "body│" .. token,
      quote,
      token .. "body" .. quote .. "│" .. quote .. quote
    )
    case(
      "skip final closing quote",
      token .. "body" .. quote .. quote .. "│" .. quote,
      quote,
      token .. "body" .. token .. "│"
    )
    case(
      "skip multiline closer",
      token .. "\nbody\n│" .. token,
      token,
      token .. "\nbody\n" .. token .. "│"
    )
    case("delete empty pair", token .. "│" .. token, "<BS>", "│")
    case("ordinary body backspace", token .. "ab│" .. token, "<BS>", token .. "a│" .. token)
    case(
      "ordinary content quote",
      token .. "a │ b" .. token,
      quote,
      token .. "a " .. quote .. "│ b" .. token
    )
    case(
      "internal quote is not skipped",
      token .. "a │" .. quote .. " b" .. token,
      quote,
      token .. "a " .. quote .. "│" .. quote .. " b" .. token
    )
    case("Enter expansion", token .. "│" .. token, "<CR>", token .. "\n│\n" .. token)
    case(
      "indented Enter expansion",
      "  " .. token .. "│" .. token,
      "<CR>body",
      "  " .. token .. "\n  body│\n  " .. token
    )
    case("continuous Enter insertion", "│", token .. "<CR>body", token .. "\nbody│\n" .. token)
    case(
      "literal tabs in Enter",
      "\t" .. token .. "│" .. token,
      "<CR>body",
      "\t" .. token .. "\n\tbody│\n\t" .. token,
      nil,
      nil,
      { expandtab = false, softtabstop = 2 }
    )
    case("prefixed raw upgrade", "│", "r" .. token, "r" .. token .. "│" .. token)
    case("prefixed f-string upgrade", "│", "f" .. token, "f" .. token .. "│" .. token)
    case("prefix retained after deletion", "r" .. token .. "│" .. token, "<BS>", "r│")
    case("assignment upgrade", "value = │", token, "value = " .. token .. "│" .. token)
    case(
      "nested literal does not upgrade",
      token .. "\n" .. quote .. quote .. "│\n" .. token,
      quote,
      token .. "\n" .. quote .. quote .. quote .. "│\n" .. token
    )
    case("comment does not upgrade", "# " .. quote .. quote .. "│", quote, "# " .. token .. "│")
    case("neighbor text prevents upgrade", quote .. quote .. "│word", quote, token .. "│word")
    case(
      "word prefix prevents upgrade",
      "name" .. quote .. quote .. "│",
      quote,
      "name" .. token .. "│"
    )
    case(
      "upgrade action can be disabled",
      quote .. quote .. "│",
      quote,
      token .. "│",
      options(quote, { open = false })
    )
    case(
      "skip action can be disabled",
      token .. "body│" .. token,
      quote,
      token .. "body" .. quote .. "│" .. token,
      options(quote, { skip = false })
    )
    case(
      "delete action can be disabled",
      token .. "│" .. token,
      "<BS>",
      quote .. quote .. "│" .. token,
      options(quote, { delete = false })
    )
    case(
      "newline action can be disabled",
      token .. "│" .. token,
      "<CR>",
      token .. "\n│" .. token,
      options(quote, { newline = false })
    )
    case(
      "whole rule can be disabled",
      quote .. quote .. "│",
      quote,
      token .. "│",
      options(quote, false)
    )
    case(
      "default configuration does not upgrade",
      quote .. quote .. "│",
      quote,
      token .. "│",
      { treesitter = true }
    )
    case(
      "other language does not upgrade",
      quote .. quote .. "│",
      quote,
      token .. "│",
      opts,
      "lua"
    )
    case(
      "disabled plugin preserves input",
      quote .. quote .. "│",
      quote,
      token .. "│",
      vim.tbl_deep_extend("force", opts, { enabled = false })
    )
    case(
      "without syntax context no upgrade",
      quote .. quote .. "│",
      quote,
      token .. "│",
      vim.tbl_deep_extend("force", opts, { treesitter = false })
    )

    test("triple " .. name .. ": Python indentexpr returning -1 and repeat", function()
      local entry = seed("  " .. token .. "│" .. token, "python")
      plugin.setup(opts)
      vim.b.did_indent = nil
      vim.cmd("runtime indent/python.vim")
      -- The native indenter considers these lines string contents. Regression:
      -- 0/Ctrl-D alone could leave an actual zero in the buffer in real config.
      vim.bo.indentkeys = vim.bo.indentkeys:gsub("0#,?", "")
      feed(entry .. "<CR>body<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "  " .. token .. "\n  body│\n  " .. token)
      feed("u")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "  " .. token .. token })
      feed("gg05l.")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "  " .. token, "  body", "  " .. token })
    end)

    test("triple " .. name .. ": no parser cannot upgrade", function()
      local original = vim.treesitter.get_parser
      vim.treesitter.get_parser = function()
        return nil
      end
      local ok, err = pcall(input, quote .. quote .. "│", quote, token .. "│", opts, "python")
      vim.treesitter.get_parser = original
      assert(ok, err)
    end)

    test("triple " .. name .. ": only multi rule can create a pair", function()
      local config = vim.deepcopy(opts)
      config.pairs = { ['"'] = false, ["'"] = false }
      input("│", token, token .. "│" .. token, config, "python")
    end)

    test("triple " .. name .. ": complete insertion undo/redo and dot", function()
      input("│", token .. "body" .. token, token .. "body" .. token .. "│", opts, "python")
      feed("u")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
      feed("<C-r>0.")
      eq(vim.api.nvim_get_current_line(), token .. "body" .. token .. token .. "body" .. token)
    end)
    test("triple " .. name .. ": multiline insertion undo/redo and dot", function()
      input("│", token .. "<CR>body", token .. "\nbody│\n" .. token, opts, "python")
      feed("u")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "" })
      feed("<C-r>gg0.")
      eq(
        vim.api.nvim_buf_get_lines(0, 0, -1, false),
        { token, "body", token .. token, "body", token }
      )
    end)
    test("triple " .. name .. ": deletion undo", function()
      input(token .. "│" .. token, "<BS>", "│", opts, "python")
      feed("u")
      eq(vim.api.nvim_get_current_line(), token .. token)
    end)
    test("triple " .. name .. ": buffer override", function()
      local entry = seed(quote .. quote .. "│", "python")
      plugin.setup(opts)
      vim.b.pairs_multi_rules = { [token] = { open = false } }
      feed(entry .. quote .. "<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, token .. "│")
    end)
  end
end

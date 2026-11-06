return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = {
    treesitter = true,
    filetypes = { markdown = { multi_pairs = { ["```"] = {}, ["~~~"] = {} } } },
  }
  local function options(family, rule)
    local copy = vim.deepcopy(opts)
    copy.filetypes.markdown.multi_pairs[family] = rule
    return copy
  end
  local function case(label, before, keys, after, config, bo)
    test("long fence: " .. label, function()
      input(before, keys, after, config or opts, "markdown", bo)
    end)
  end
  test("long fence: independent family defaults and mappings", function()
    local original = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, original)
    local config = require("pairs.config")
    local rules = config.resolve_multi(config.build(opts), "markdown")
    for _, family in ipairs({ "```", "~~~" }) do
      eq(rules[family], {
        close = family,
        open = true,
        newline = true,
        skip = true,
        delete = false,
        space = false,
      })
      eq(
        vim.fn.maparg(family:sub(1, 1), "i", false, true).desc,
        "pairs.nvim: Insert or skip paired delimiter " .. family:sub(1, 1)
      )
    end
  end)
  test("long fence: longer configuration keys are rejected", function()
    eq(pcall(plugin.setup, { multi_pairs = { ["````"] = {} } }), false)
    eq(pcall(plugin.setup, { multi_pairs = { ["~~~~"] = {} } }), false)
  end)
  test("long fence: tilde configuration rejects deletion and mismatched close", function()
    eq(pcall(plugin.setup, options("~~~", { delete = true })), false)
    eq(pcall(plugin.setup, options("~~~", { close = "~~~~" })), false)
    eq(pcall(plugin.setup, options("~~~", { close = "```" })), false)
  end)
  for _, char in ipairs({ "`", "~" }) do
    local family = char:rep(3)
    for _, length in ipairs({ 3, 4, 8 }) do
      local delimiter = char:rep(length)
      for _, container in ipairs({
        { "", "" },
        { "- ", "  " },
        { "> ", "> " },
        { "> - > ", ">   > " },
      }) do
        local open, prefix = unpack(container)
        local label = delimiter .. " " .. open
        local header = open .. delimiter .. "lua"
        local body = prefix .. "body"
        case(
          "continuous " .. label,
          "│",
          header .. "<CR>body",
          header .. "\n" .. body .. "│\n" .. prefix .. delimiter
        )
        case(
          "continuous before paragraph " .. label,
          "│\n" .. prefix .. "已有正文",
          header .. "<CR>body",
          header
            .. "\n"
            .. body
            .. "│\n"
            .. prefix
            .. delimiter
            .. "\n"
            .. prefix
            .. "已有正文"
        )
        case(
          "close before separated paragraph " .. label,
          header .. "│\n" .. prefix .. "\n" .. prefix .. "已有正文",
          "<CR>",
          header
            .. "\n"
            .. prefix
            .. "│\n"
            .. prefix
            .. delimiter
            .. "\n"
            .. prefix
            .. "\n"
            .. prefix
            .. "已有正文"
        )
        case(
          "reuse closer after content " .. label,
          header .. "│\n" .. prefix .. "existing\n" .. prefix .. delimiter,
          "<CR>",
          header .. "\n" .. prefix .. "│\n" .. prefix .. "existing\n" .. prefix .. delimiter
        )
        case(
          "skip " .. label,
          header .. "\n" .. body .. "\n" .. prefix .. "│" .. delimiter,
          delimiter,
          header .. "\n" .. body .. "\n" .. prefix .. delimiter .. "│"
        )
        local longer = delimiter .. char:rep(2)
        case(
          "reuse longer " .. label,
          header .. "│\n" .. prefix .. longer,
          "<CR>body",
          header .. "\n" .. body .. "│\n" .. prefix .. longer
        )
        case(
          "skip longer before paragraph " .. label,
          header .. "\n" .. body .. "\n" .. prefix .. "│" .. longer .. "\n" .. prefix .. "after",
          longer,
          header .. "\n" .. body .. "\n" .. prefix .. longer .. "│\n" .. prefix .. "after"
        )
      end
    end
    local delimiter = char:rep(5)
    local shorter = char:rep(3)
    local other = (char == "`" and "~" or "`"):rep(5)
    case(
      "shorter delimiter is body " .. char,
      delimiter .. "\n│" .. shorter .. "\n" .. delimiter,
      char,
      delimiter .. "\n" .. char .. "│" .. shorter .. "\n" .. delimiter
    )
    case(
      "other character is body " .. char,
      delimiter .. "\n│" .. other .. "\n" .. delimiter,
      other,
      delimiter .. "\n" .. other .. "│" .. other .. "\n" .. delimiter
    )
    case(
      "close before existing body " .. char,
      delimiter .. "│\nbody",
      "<CR>",
      delimiter .. "\n│\n" .. delimiter .. "\nbody"
    )
    case(
      "family disabled " .. char,
      delimiter .. "│",
      "<CR>",
      delimiter .. "\n│",
      options(family, false)
    )
    case(
      "open disabled " .. char,
      delimiter .. "│",
      "<CR>",
      delimiter .. "\n│",
      options(family, { open = false })
    )
    case(
      "newline disabled " .. char,
      delimiter .. "│",
      "<CR>",
      delimiter .. "\n│",
      options(family, { newline = false })
    )
    case(
      "skip disabled " .. char,
      delimiter .. "\n│" .. delimiter,
      char,
      delimiter .. "\n" .. char .. "│" .. delimiter,
      options(family, { skip = false })
    )
    case(
      "four-space closing indentation is body " .. char,
      delimiter .. "\n    │" .. delimiter .. "\n" .. delimiter,
      char,
      delimiter .. "\n    " .. char .. "│" .. delimiter .. "\n" .. delimiter
    )
    case(
      "closing suffix is body " .. char,
      delimiter .. "\n│" .. delimiter .. "bad\n" .. delimiter,
      char,
      delimiter .. "\n" .. char .. "│" .. delimiter .. "bad\n" .. delimiter
    )
    case(
      "short opening stays native " .. char,
      char:rep(2) .. "│",
      "<CR>",
      char:rep(2) .. "\n│"
    )
    case(
      "inline opener stays native " .. char,
      "text " .. delimiter .. "│",
      "<CR>",
      "text " .. delimiter .. "\n│"
    )
    case(
      "indented code stays native " .. char,
      "    " .. delimiter .. "│",
      "<CR>",
      "    " .. delimiter .. "\n    │"
    )
    case("ordinary Backspace " .. char, delimiter .. "│", "<BS>", delimiter:sub(2) .. "│")
    case(
      "scan limit " .. char,
      delimiter .. "│",
      "<CR>",
      delimiter .. "\n│",
      vim.tbl_deep_extend("force", opts, { max_scan_bytes = 4 })
    )
    case(
      "Tree-sitter disabled " .. char,
      delimiter .. "│",
      "<CR>",
      delimiter .. "\n│",
      vim.tbl_deep_extend("force", opts, { treesitter = false })
    )
    case(
      "native comments and indentation " .. char,
      "> - " .. delimiter .. "lua│",
      "<CR>body",
      "> - " .. delimiter .. "lua\n>   body│\n>   " .. delimiter,
      nil,
      { comments = "b:>,b:-", formatoptions = "rno", indentexpr = "8", expandtab = false }
    )
    test("long fence: undo redo dot preserves following paragraph " .. char, function()
      local original = { "> " .. delimiter .. "lua", "> 已有正文" }
      input(
        original[1] .. "│\n" .. original[2],
        "<CR>body",
        original[1] .. "\n> body│\n> " .. delimiter .. "\n" .. original[2],
        opts,
        "markdown"
      )
      local expanded = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      feed("u")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), original)
      feed("<C-r>")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), expanded)
      feed("u$.")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), expanded)
    end)
    test("long fence: native undo redo dot " .. char, function()
      input(
        "│",
        "> " .. delimiter .. "lua<CR>body",
        "> " .. delimiter .. "lua\n> body│\n> " .. delimiter,
        opts,
        "markdown"
      )
      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
      feed("<C-r>")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
      feed("u.")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
    end)
    test("long fence: outer tree owns injected closing " .. char, function()
      local entry = seed("> " .. delimiter .. "c\n> int x;\n> │" .. delimiter, "markdown")
      plugin.setup(opts)
      local parser = vim.treesitter.get_parser(0, "markdown")
      parser:parse(true)
      eq(parser:language_for_range({ 1, 6, 1, 6 }):lang(), "c")
      feed(entry .. delimiter .. "<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "> " .. delimiter .. "c\n> int x;\n> " .. delimiter .. "│")
    end)
  end
  case(
    "backticks disabled independently",
    "~~~~│",
    "<CR>",
    "~~~~\n│\n~~~~",
    options("```", false)
  )
  case("tildes disabled independently", "````│", "<CR>", "````\n│\n````", options("~~~", false))
  case("tilde info can contain backticks", "~~~~py`example│", "<CR>", "~~~~py`example\n│\n~~~~")
  case("backtick info cannot contain backticks", "````py`example│", "<CR>", "````py`example\n│")
  case(
    "tilde info retains Unicode and spaces",
    "~~~  示例 metadata \t│",
    "<CR>",
    "~~~  示例 metadata \t\n│\n~~~"
  )
  case("Enter inside tilde info", "~~~py│thon", "<CR>", "~~~py\n│thon")
  case("tilde characters remain literal until Enter", "│", "~~~~lua", "~~~~lua│")
  case("a different character is allowed in info", "```~~~│", "<CR>", "```~~~\n│\n```")
  for _, char in ipairs({ "`", "~" }) do
    local delimiter = char:rep(64)
    case(
      "wide opener " .. char,
      delimiter .. "lua│",
      "<CR>body",
      delimiter .. "lua\nbody│\n" .. delimiter
    )
    case(
      "default family opt-out " .. char,
      char:rep(4) .. "│",
      "<CR>",
      char:rep(4) .. "\n│",
      { treesitter = true }
    )
  end
  test("long fence: buffer disables only tilde family", function()
    local entry = seed("~~~~│", "markdown")
    plugin.setup(opts)
    vim.b.pairs_multi_rules = { ["~~~"] = false }
    feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "~~~~\n│")
  end)
end

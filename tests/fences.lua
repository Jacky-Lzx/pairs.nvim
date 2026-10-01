return function(h)
  local test, input, seed, feed, eq, plugin = h.test, h.input, h.seed, h.feed, h.eq, h.plugin
  local opts = {
    treesitter = true,
    filetypes = { markdown = { multi_pairs = { ["```"] = {} } } },
  }
  local function options(overrides)
    local copy = vim.deepcopy(opts)
    copy.filetypes.markdown.multi_pairs["```"] = overrides
    return copy
  end
  local function case(label, before, keys, after, config, ft, bo)
    test("fence: " .. label, function()
      input(before, keys, after, config or opts, ft or "markdown", bo)
    end)
  end
  test("fence: defaults and setup do not mutate options", function()
    local before = vim.deepcopy(opts)
    plugin.setup(opts)
    eq(opts, before)
    local resolved =
      require("pairs.config").resolve_multi(require("pairs.config").build(opts), "markdown")
    eq(resolved["```"], { close = "```", open = true, newline = true, skip = true, delete = false })
    eq(vim.fn.maparg("`", "i", false, true).desc, "pairs.nvim `")
  end)
  test("fence: invalid closer is rejected", function()
    eq(pcall(plugin.setup, options({ close = "~~~" })), false)
  end)
  test("fence: unsupported block deletion is rejected", function()
    eq(pcall(plugin.setup, options({ delete = true })), false)
  end)
  case("plain Enter expansion", "```│", "<CR>", "```\n│\n```")
  case("language info retained", "```python│", "<CR>body", "```python\nbody│\n```")
  case("continuous input", "│", "```python<CR>body", "```python\nbody│\n```")
  case(
    "spaces around language info",
    "```  lua metadata \t│",
    "<CR>",
    "```  lua metadata \t\n│\n```"
  )
  case("Unicode info string", "```示例│", "<CR>", "```示例\n│\n```")
  for indent = 1, 3 do
    local prefix = string.rep(" ", indent)
    case(
      "indent " .. indent,
      prefix .. "```lua│",
      "<CR>body",
      prefix .. "```lua\n" .. prefix .. "body│\n" .. prefix .. "```"
    )
  end
  case(
    "tabs do not expand indentation incorrectly",
    "  ```lua│",
    "<CR>body",
    "  ```lua\n  body│\n  ```",
    nil,
    nil,
    { expandtab = false, softtabstop = 2 }
  )
  case(
    "indentexpr does not add shiftwidth to a fence",
    "  ```│",
    "<CR>body",
    "  ```\n  body│\n  ```",
    nil,
    nil,
    { indentexpr = "8" }
  )
  case("four spaces are indented code", "    ```│", "<CR>", "    ```\n    │")
  case("tab prefix is indented code", "\t```│", "<CR>", "\t```\n    │")
  case("inline code", "text `code ```│`", "<CR>", "text `code ```\n│`")
  case("ordinary text", "text ```│", "<CR>", "text ```\n│")
  case("invalid info string with backtick", "```py`bad│", "<CR>", "```py`bad\n│")
  case("four-backtick opener expands", "````│", "<CR>", "````\n│\n````")
  case("tilde opener remains opt-in", "~~~│", "<CR>", "~~~\n│")
  case("backticks are typed literally before Enter", "│", "```lua", "```lua│")
  case("Enter in middle of info string", "```py│thon", "<CR>", "```py\n│thon")
  case("Enter before trailing whitespace", "```lua│  ", "<CR>", "```lua\n│")
  case("HTML block does not open fence", "<div>\n```│\n</div>", "<CR>", "<div>\n```\n│\n</div>")
  case("list opener", "- ```lua│", "<CR>body", "- ```lua\n  body│\n  ```")
  case("quote opener", "> ```lua│", "<CR>body", "> ```lua\n> body│\n> ```")
  for _, example in ipairs({
    { "- ", "  " },
    { "+ ", "  " },
    { "* ", "  " },
    { "12. ", "    " },
    { "123) ", "     " },
    { "  - ", "    " },
    { "-   ", "    " },
    { ">", ">" },
    { "> > ", "> > " },
    { ">> ", ">> " },
    { "  > ", "  > " },
    { ">   ", ">   " },
    { "- > ", "  > " },
    { "> - ", ">   " },
    { "> - > ", ">   > " },
    { "- - ", "    " },
    { "-\t", "    " },
    { "> \t", ">   " },
  }) do
    local opening, prefix = unpack(example)
    case(
      "container prefix " .. vim.inspect(opening),
      opening .. "```lua│",
      "<CR>body",
      opening .. "```lua\n" .. prefix .. "body│\n" .. prefix .. "```"
    )
    case(
      "container closer " .. vim.inspect(opening),
      opening .. "```lua\n" .. prefix .. "body\n" .. prefix .. "│```",
      "```",
      opening .. "```lua\n" .. prefix .. "body\n" .. prefix .. "```│"
    )
  end
  case("continuous list input", "│", "- ```lua<CR>body", "- ```lua\n  body│\n  ```")
  case("continuous quote input", "│", "> ```lua<CR>body", "> ```lua\n> body│\n> ```")
  case("list continuation", "- item\n  ```lua│", "<CR>body", "- item\n  ```lua\n  body│\n  ```")
  case(
    "list relative fence indentation",
    "- item\n    ```lua│",
    "<CR>body",
    "- item\n    ```lua\n    body│\n    ```"
  )
  case(
    "quote continuation",
    "> item\n> ```lua│",
    "<CR>body",
    "> item\n> ```lua\n> body│\n> ```"
  )
  case(
    "nested list continuation",
    "- item\n  - ```lua│",
    "<CR>body",
    "- item\n  - ```lua\n    body│\n    ```"
  )
  case("reuse list closer", "- ```lua│\n  ```", "<CR>body", "- ```lua\n  body│\n  ```")
  case("reuse quote closer", "> ```lua│\n> ```", "<CR>body", "> ```lua\n> body│\n> ```")
  case(
    "quote closer before paragraph",
    "> ```lua\n> body\n> │```\n> after",
    "```",
    "> ```lua\n> body\n> ```│\n> after"
  )
  case(
    "list closer before paragraph",
    "- ```lua\n  body\n  │```\n  after",
    "```",
    "- ```lua\n  body\n  ```│\n  after"
  )
  case(
    "reuse quote closer before paragraph",
    "> ```lua│\n> ```\n> after",
    "<CR>body",
    "> ```lua\n> body│\n> ```\n> after"
  )
  case(
    "reuse list closer before paragraph",
    "- ```lua│\n  ```\n  after",
    "<CR>body",
    "- ```lua\n  body│\n  ```\n  after"
  )
  case("preserve quote content", "> ```lua│\n> body", "<CR>", "> ```lua\n> │\n> body")
  case(
    "reuse mixed closer",
    "> - ```lua│\n>   ```",
    "<CR>body",
    "> - ```lua\n>   body│\n>   ```"
  )
  case(
    "four-space quote closer is body",
    "> ```\n>     │```\n> ```",
    "```",
    "> ```\n>     ```│```\n> ```"
  )
  case(
    "four-space list closer is body",
    "- ```\n      │```\n  ```",
    "```",
    "- ```\n      ```│```\n  ```"
  )
  case("four-space quote opener is code", ">     ```│", "<CR>", ">     ```\n│")
  case("task text is not a fence", "- [ ] ```lua│", "<CR>", "- [ ] ```lua\n│")
  case(
    "task continuation fence",
    "- [ ] task\n  ```lua│",
    "<CR>body",
    "- [ ] task\n  ```lua\n  body│\n  ```"
  )
  case(
    "HTML in quote stays ordinary",
    "> <div>\n> ```│\n> </div>",
    "<CR>",
    "> <div>\n> ```\n│\n> </div>"
  )
  case("longer quote opener expands", "> ````│", "<CR>", "> ````\n> │\n> ````")
  case("tilde list opener remains opt-in", "- ~~~│", "<CR>", "- ~~~\n│")
  case(
    "relative four spaces are code",
    "- item\n      ```│",
    "<CR>",
    "- item\n      ```\n      │"
  )
  case("quote language string midpoint", "> ```py│thon", "<CR>", "> ```py\n│thon")
  case("quote opening disabled", "> ```lua│", "<CR>", "> ```lua\n│", options({ open = false }))
  case("quote skip disabled", "> ```\n> │```", "`", "> ```\n> `│```", options({ skip = false }))
  case(
    "list newline disabled",
    "- ```lua│",
    "<CR>",
    "- ```lua\n│",
    options({ newline = false })
  )
  case("reuse adjacent closer", "```lua│\n```", "<CR>body", "```lua\nbody│\n```")
  case("reuse later closer", "```lua│\nbody\n```", "<CR>", "```lua\n│\nbody\n```")
  case("reuse longer closer", "```│\n`````", "<CR>", "```\n│\n`````")
  case("reuse indented closer", "  ```│\n   ```  ", "<CR>", "  ```\n  │\n   ```  ")
  case("existing unclosed content is preserved", "```│\nbody", "<CR>", "```\n│\nbody")
  case("Enter in body stays native", "```lua\nbody│\n```", "<CR>", "```lua\nbody\n│\n```")
  case("Enter on closing line stays native", "```\nbody\n```│", "<CR>", "```\nbody\n```\n│")
  case("short fence inside longer block", "````\n```│\n````", "<CR>", "````\n```\n│\n````")
  case("backticks inside tilde block", "~~~\n```│\n~~~", "<CR>", "~~~\n```\n│\n~~~")
  case("skip closer", "```lua\nbody\n│```", "```", "```lua\nbody\n```│")
  case("skip final quote", "```\nbody\n``│`", "`", "```\nbody\n```│")
  case("skip longer closing delimiter", "```\nbody\n│`````", "`````", "```\nbody\n`````│")
  case("skip indented closer", "```\nbody\n  │```  ", "```", "```\nbody\n  ```│  ")
  case("do not skip opening delimiter", "│```", "`", "`│```")
  case("body backticks do not skip", "```\ntext │`\n```", "`", "```\ntext `│`\n```")
  case("shorter body delimiter is not a closer", "```\n│``\n```", "`", "```\n`│``\n```")
  case("invalid closing suffix is body", "```\n│```bad\n```", "```", "```\n```│```bad\n```")
  case(
    "four-space closing prefix is body",
    "```\n    │```\n```",
    "```",
    "```\n    ```│```\n```"
  )
  case("default options do not expand fence", "```│", "<CR>", "```\n│", { treesitter = true })
  case("another filetype does not expand", "```│", "<CR>", "```\n│", opts, "lua")
  case("newline action disabled", "```│", "<CR>", "```\n│", options({ newline = false }))
  case("opening action disabled", "```│", "<CR>", "```\n│", options({ open = false }))
  case("skip disabled", "```\n│```", "`", "```\n`│```", options({ skip = false }))
  case("whole rule disabled", "```│", "<CR>", "```\n│", options(false))
  case(
    "Tree-sitter disabled",
    "```│",
    "<CR>",
    "```\n│",
    vim.tbl_deep_extend("force", opts, { treesitter = false })
  )
  case(
    "plugin disabled",
    "```│",
    "<CR>",
    "```\n│",
    vim.tbl_deep_extend("force", opts, { enabled = false })
  )
  case(
    "scan limit preserves Enter",
    "```│",
    "<CR>",
    "```\n│",
    vim.tbl_deep_extend("force", opts, { max_scan_bytes = 2 })
  )
  case("Backspace retains ordinary deletion", "```│", "<BS>", "``│")
  test("fence: buffer override", function()
    local entry = seed("```│", "markdown")
    plugin.setup(opts)
    vim.b.pairs_multi_rules = { ["```"] = { newline = false } }
    feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "```\n│")
  end)
  test("fence: no parser preserves input", function()
    local entry = seed("```│", "markdown")
    plugin.setup(opts)
    local original = vim.treesitter.get_parser
    vim.treesitter.get_parser = function()
      return nil
    end
    local ok, err = pcall(function()
      feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "```\n│")
    end)
    vim.treesitter.get_parser = original
    assert(ok, err)
  end)
  test("fence: pending parse never uses stale delimiters", function()
    seed("```│", "markdown")
    plugin.setup(opts)
    local parser = vim.treesitter.get_parser(0, "markdown")
    parser:parse(true)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "plain" })
    local original = parser.parse
    parser.parse = function()
      return nil
    end
    local ok, err = pcall(function()
      eq(plugin.explain("<CR>", { assume_insert = true }).action, "pass")
      eq(plugin.explain("<CR>", { assume_insert = true }).reason, "syntax_pending")
    end)
    parser.parse = original
    assert(ok, err)
  end)
  test("fence: forced sync parsing is bypassed", function()
    local entry = seed("```│", "markdown")
    plugin.setup(opts)
    local previous = vim.g._ts_force_sync_parsing
    vim.g._ts_force_sync_parsing = true
    local ok, err = pcall(function()
      feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, "```\n│")
    end)
    vim.g._ts_force_sync_parsing = previous
    assert(ok, err)
  end)
  test("fence: native undo redo and dot", function()
    input("│", "```lua<CR>body", "```lua\nbody│\n```", opts, "markdown")
    feed("u")
    eq(vim.api.nvim_get_current_line(), "")
    feed("<C-r>gg0.")
    eq(
      vim.api.nvim_buf_get_lines(0, 0, -1, false),
      { "```lua", "body", "``````lua", "body", "```" }
    )
  end)
  test("fence: counted repeat", function()
    input("│", "```lua<CR>body", "```lua\nbody│\n```", opts, "markdown")
    feed("u2.")
    eq(
      vim.api.nvim_buf_get_lines(0, 0, -1, false),
      { "```lua", "body```lua", "body", "```", "```" }
    )
    feed("u")
    eq(vim.api.nvim_get_current_line(), "")
  end)
  test("fence: expansion undo restores existing opener", function()
    input("  ```lua│", "<CR>body", "  ```lua\n  body│\n  ```", opts, "markdown")
    feed("u")
    eq(vim.api.nvim_get_current_line(), "  ```lua")
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "  ```lua", "  body", "  ```" })
  end)
  for _, prefix in ipairs({ "- ", "> ", "> - > " }) do
    local continuation = prefix:gsub("-", " ")
    test("fence: container undo redo and dot " .. prefix, function()
      input(
        "│",
        prefix .. "```lua<CR>body",
        prefix .. "```lua\n" .. continuation .. "body│\n" .. continuation .. "```",
        opts,
        "markdown"
      )
      local original = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
      feed("<C-r>")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), original)
      feed("u.")
      eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), original)
      feed("u")
      eq(vim.api.nvim_get_current_line(), "")
    end)
    case(
      "container ignores indentexpr " .. prefix,
      prefix .. "```lua│",
      "<CR>body",
      prefix .. "```lua\n" .. continuation .. "body│\n" .. continuation .. "```",
      nil,
      nil,
      { indentexpr = "8", expandtab = false, tabstop = 8 }
    )
    case(
      "container with native comment continuation " .. prefix,
      prefix .. "```lua│",
      "<CR>body",
      prefix .. "```lua\n" .. continuation .. "body│\n" .. continuation .. "```",
      nil,
      nil,
      { formatoptions = "rno", comments = "b:>,b:-", autoindent = true }
    )
  end
  test("fence: quote continuation undo", function()
    input("> ```lua│\n> ```", "<CR>body", "> ```lua\n> body│\n> ```", opts, "markdown")
    feed("u")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "> ```lua", "> ```" })
    feed("<C-r>")
    eq(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "> ```lua", "> body", "> ```" })
  end)
  test("fence: container sentinel does not expand abbreviation", function()
    vim.cmd("iabbrev x SENTINEL")
    local ok, err =
      pcall(input, "> ```lua│", "<CR>body", "> ```lua\n> body│\n> ```", opts, "markdown")
    vim.cmd("iunabbrev x")
    assert(ok, err)
  end)
  test("fence: paste bypasses expansion", function()
    local entry = seed("```│", "markdown")
    plugin.setup(opts)
    vim.o.paste = true
    feed(entry .. "<CR><Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "```\n│")
    vim.o.paste = false
  end)
  test("fence: large content keeps lookup shallow", function()
    local text = "```\n" .. string.rep("line\n", 3000) .. "│```"
    local entry = seed(text, "markdown")
    plugin.setup(opts)
    -- Test lookup on a ready tree, independently of the first parse's time
    -- budget. Pending parses are covered separately above.
    vim.treesitter.get_parser(0, "markdown"):parse(true)
    feed(entry .. "```<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, text:gsub("│```$", "```│"))
    eq(_G.pairs_test_mode, "i")
  end)
  for _, example in ipairs({ { "- ", "  " }, { "> ", "> " }, { "> - ", ">   " } }) do
    local open, prefix = unpack(example)
    test("fence: container code injection " .. open, function()
      local entry = seed(open .. "```c\n" .. prefix .. "int x;\n" .. prefix .. "│```", "markdown")
      plugin.setup(opts)
      local parser = vim.treesitter.get_parser(0, "markdown")
      parser:parse(true)
      eq(parser:language_for_range({ 1, #prefix + 4, 1, #prefix + 4 }):lang(), "c")
      feed(entry .. "```<Cmd>lua pairs_test_capture()<CR><Esc>")
      eq(_G.pairs_test_result, open .. "```c\n" .. prefix .. "int x;\n" .. prefix .. "```│")
    end)
  end
  test("fence: injected code does not own Markdown delimiters", function()
    local entry = seed("```c\nint x;\n│```", "markdown")
    plugin.setup(opts)
    local parser = vim.treesitter.get_parser(0, "markdown")
    parser:parse(true)
    eq(parser:language_for_range({ 1, 4, 1, 4 }):lang(), "c")
    feed(entry .. "```<Cmd>lua pairs_test_capture()<CR><Esc>")
    eq(_G.pairs_test_result, "```c\nint x;\n```│")
  end)
end

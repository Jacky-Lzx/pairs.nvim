return function(t)
  local function seed(marked, ft, extra)
    t.seed(marked, ft or "python")
    vim.b.pairs_surround_config, vim.b.pairs_surround_enabled = nil, nil
    t.plugin.setup({
      rainbow = { enabled = false },
      surround = vim.tbl_deep_extend("force", { enabled = true, treesitter = true }, extra or {}),
    })
  end
  local function text()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  end
  local function input(name, before, keys, expected, ft)
    t.test("syntax surround " .. name, function()
      seed(before, ft)
      -- Real grammar, intentionally settled before input. Pending-tree
      -- behavior is checked separately with the native callback contract.
      vim.treesitter.get_parser(0):parse()
      t.feed(keys)
      t.eq(text(), expected)
    end)
  end
  if vim.env.PAIRS_TEST_PARSER_ROOT then
    input("function ignores body quote closer", 'fn("a│)b")', "sdf", '"a)b"')
    input("brackets ignore body quote closer", 'fn("a│)b")', "sd)", 'fn"a)b"')
    input("trim preserves masked body", 'fn(  "a│)b"  )', "sd(", 'fn"a)b"')
    input("replace function", 'fn("a│)b")', "srf]", '["a)b"]')
    input("prompt replacement", 'fn("he│llo")', "sr)?【<CR>】<CR>", 'fn【"hello"】')
    input("prompt target inside string", '"BEGINhe│lloEND"', "sr?BEGIN<CR>END<CR>]", '"[hello]"')
    input("prompt target inside comment", "# BEGINhe│lloEND", "sr?BEGIN<CR>END<CR>]", "# [hello]")
    input("nested function count", 'outer(inner("a│)b"))', "2sdf", 'inner("a)b")')
    input("quoted fake call", 'fn("fake(│x)")', "sdf", '"fake(x)"')
    input("comment fake closers", "fn(\n  │x, # ) fake(y)\n)", "sdf", "x, # ) fake(y)")
    input("comments are not targets", "│# fn(x)", "sdf", "# fn(x)")
    input("triple quote contents", 'fn("""a│)b""")', "sdf", '"""a)b"""')
    input("triple quote target", 'r"""a│)b"""', 'sd"', "ra)b")
    input("template fake calls", "fn(`fake(│x)`)", "sdf", "`fake(x)`", "javascript")
    input(
      "template substitution remains code",
      '`text ${fn("a│)b")}`',
      "sdf",
      '`text ${"a)b"}`',
      "javascript"
    )
    input(
      "f-string substitution remains code",
      "f\"text {fn('a│)b')}\"",
      "sdf",
      "f\"text {'a)b'}\""
    )
    input("escaped quote target", '"a\\"b│c"', 'sd"', 'a\\"bc')
    input("undo", 'fn("a│)b")', "sdfu", 'fn("a)b")')
    input("dot reparses new cursor", 'fn("a│)b"); fn("c)d")', "sdfW.", '"a)b"; "c)d"')
    input("unknown syntax inert", "fn(│x + )", "sdf", "fn(x + )")
  end
  t.test("syntax surround missing parser uses literal fallback", function()
    seed("(he│llo)", "pairs_nonexistent")
    t.feed("sd)")
    t.eq(text(), "hello")
  end)
  t.test("syntax surround pending parser never edits", function()
    seed("fn(│x)")
    local get = vim.treesitter.get_parser
    local requests = 0
    vim.treesitter.get_parser = function()
      return {
        is_valid = function()
          return false
        end,
        parse = function(_, _, callback)
          assert(type(callback) == "function")
          requests = requests + 1
        end,
      }
    end
    t.feed("sdf")
    vim.treesitter.get_parser = get
    t.eq(requests, 1)
    t.eq(text(), "fn(x)")
  end)
  t.test("syntax surround prompted target bypasses parser", function()
    seed("BEGINhe│lloEND")
    local get = vim.treesitter.get_parser
    local requests = 0
    vim.treesitter.get_parser = function()
      requests = requests + 1
      return {
        is_valid = function()
          return false
        end,
        parse = function() end,
      }
    end
    t.feed("sr?BEGIN<CR>END<CR>]")
    vim.treesitter.get_parser = get
    t.eq(text(), "[hello]")
    t.eq(requests, 0)
  end)
  local function regions(context)
    local row = context.position[1]
    local line = context.lines[row - context.first_row + 1]
    local a, b = line:find("<", 1, true), line:find(">", 1, true)
    if not a or not b then
      return nil
    end
    return {
      {
        left = { from = { row, a - 1 }, to = { row, a } },
        right = { from = { row, b - 1 }, to = { row, b } },
      },
    }
  end
  t.test("surround custom region matcher and dot", function()
    seed("<he│llo>\n<world>", "text", { custom_surroundings = { x = { input = regions } } })
    t.feed("sdxj0.")
    t.eq(text(), "hello\nworld")
  end)
  t.test("surround custom region replacement", function()
    seed("<he│llo>", "text", { custom_surroundings = { x = { input = regions } } })
    t.feed("srx]")
    t.eq(text(), "[hello]")
    t.feed("u")
    t.eq(text(), "<hello>")
  end)
  t.test("surround bad region is rejected before edits", function()
    seed("<he│llo>", "text", {
      custom_surroundings = {
        x = {
          input = function()
            return {
              left = { from = { 0, 0 }, to = { 0, 99 } },
              right = { from = { 0, 6 }, to = { 0, 7 } },
            }
          end,
        },
      },
    })
    local old = vim.fn.getcharstr
    vim.fn.getcharstr = function()
      return "x"
    end
    local ok = pcall(require("pairs.surround").action, "highlight")
    vim.fn.getcharstr = old
    t.eq(ok, false)
    t.eq(text(), "<hello>")
  end)
end

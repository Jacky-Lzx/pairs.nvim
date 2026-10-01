# pairs.nvim

A small, conservative auto-pairs plugin for Neovim, with quote behavior as the
first priority. Pure Lua; Neovim 0.11 or newer; no runtime dependencies.

It handles Insert-mode quotes, brackets, matching-closer skipping, empty-pair
backspace, and empty-bracket expansion on Enter. Multi-character delimiters,
wrapping, and command-line mode are planned.

## Local installation

Disable the existing auto-pairs plugin first. With lazy.nvim:

```lua
{
  dir = "/Users/zexili/Documents/Github/nvim_plugins/pairs.nvim",
  name = "pairs.nvim",
  event = "InsertEnter",
  opts = {},
  config = function(_, opts)
    require("pairs").setup(opts)
  end,
}
```

Or add the checkout to `runtimepath` and call `require("pairs").setup()`.
Requiring the module alone does not install mappings.

## Quote behavior

`│` denotes the insertion cursor:

| Before | Input | After |
| --- | --- | --- |
| `│` | `"` | `"│"` |
| `"hello│"` | `"` | `"hello"│` |
| `"hello│` | `"` | `"hello"│` |
| `don│t` | `'` | `don'│t` |
| `dogs│` | `'` | `dogs'│` |
| `│hello` | `"` | `"│hello` |
| `"don│t"` | `'` | `"don'│t"` |
| `\│` | `"` | `\"│` |
| `\\│` | `"` | `\\"│"` |
| `"│"` | `<BS>` | `│` |
| `(│)` | `)` | `()│` |
| `│)` | `)` | `)│)` |

- Quotes after word characters or another quote do not open a pair.
- Non-ASCII neighbors are treated conservatively, so quotes next to Chinese
  text do not automatically open a pair.
- Opening is allowed before whitespace, end of line, configured closing
  brackets, comma, semicolon, or colon. Quotes before existing quotes pass
  through without adding another closing quote.
- Escaping uses the parity of consecutive backslashes, not just the preceding
  character.
- Closing quotes are skipped only when the lexer or syntax context identifies
  a matching opening quote. Bracket skipping also checks nesting, not delimiter counts.
- Single-quote opening is disabled by default for `text`, `markdown`, and
  `rust`. Single-quote skipping/deletion remain separate options.
- Common line comments are recognized by filetype. A string/comment suppresses
  automatic bracket insertion as well as quote insertion.

## Configuration

```lua
require("pairs").setup({
  enabled = true, -- or function(bufnr) return true end
  mappings = { enabled = true, bs = true, cr = true },
  treesitter = false,
  max_scan_bytes = 4096,
  disabled_filetypes = { "TelescopePrompt", "snacks_picker_input" },
  pairs = {
    ["'"] = { open = false }, -- keep skip/delete, disable quote insertion
    ["("] = { skip = false },
    ["{"] = { newline = false }, -- disable Enter expansion for braces
    ["["] = false,           -- disable this entire rule
    -- Additional pairs are opt-in. Asymmetric rules also enable newline.
    ["<"] = { close = ">", open = true, skip = true, delete = true },
  },
  filetypes = {
    lua = { pairs = { ["'"] = { open = true } } },
    markdown = { pairs = { ['"'] = { open = false } } },
    help = { enabled = false },
  },
})
```

Defaults are `()`, `[]`, `{}`, `""`, and `''`. Rules are merged in the order
global defaults → global configuration → filetype → buffer. Delimiters must be
single printable ASCII characters; closing delimiters must be unambiguous.
Multi-character rules such as triple quotes, code fences, and `$$` are not
supported yet. Do not enable `<>` globally unless you want it to pair operators.

Per-buffer overrides:

```lua
vim.b.pairs_enabled = false
vim.b.pairs_rules = { ['"'] = { open = false } }
```

Buffer rules can override existing rules. A newly introduced delimiter requires
its own mapping via `handle()` or a global/filetype declaration at setup time.

Enable `treesitter = true` to recognize multiline strings, raw strings and
block comments using an installed parser. Python f-string expressions and
JavaScript/TypeScript template substitutions are treated as code; their literal
text stays protected. Completed strings/comments are masked in the current
line's lexical prefix so their contents cannot corrupt later bracket nesting.
Normal quoted strings still support skipping their closing quote.

The plugin refreshes stale or unparsed trees through Neovim's time-sliced
`parse(range, callback)` API. It never requests a full synchronous parse or
waits for completion. If the required tree is still pending, or an unfinished
literal cannot be classified safely, the original key passes through. Missing
parsers use the line-local lexer. Current-line syntax traversal is limited to
256 nodes; more complex prefixes pass through with reason `syntax_limit`.
This option does not install parsers or start
highlighting; your usual Tree-sitter highlighter can share the same parser.

Without syntax context, the lexer is intentionally line-local. It does not
fully understand multiline strings, block comments, interpolation, injected
languages, or all language-specific literal forms. Scans exceeding the byte
limit and malformed bracket prefixes pass the original key through.

## Mappings and completion

Setup preserves existing global mappings and leaves buffer mappings alone.
`require("pairs").status().conflicts` reports skipped keys. Disable the previous
pairs plugin instead of running two mapping owners together. Setup is
idempotent; teardown removes only mappings still owned by this plugin.

`<CR>` expands adjacent empty `()`, `[]`, and `{}` into three lines, leaving the
cursor on the indented middle line. Quotes, strings, comments, nonempty pairs,
and ordinary newlines pass through. The plugin uses the buffer's `indentexpr`
or `cindent` when configured; otherwise it adds one `shiftwidth` to the opening
line's indentation and aligns the closing line with it. Tabs and `vartabstop`
are respected. Undo/redo and `.` retain the entire multiline insertion; dot
replays the indentation produced by the original insertion.

`<Tab>` is never mapped. Existing Enter mappings are preserved. When a
completion plugin owns Enter, disable this plugin's Enter mapping and compose
`expr("<CR>")` into that owner's fallback chain. For blink.cmp:

```lua
-- pairs.nvim options
require("pairs").setup({ mappings = { cr = false } })
-- blink.cmp options
keymap = {
  ["<CR>"] = {
    "accept",
    function() return require("pairs").expr("<CR>") end,
    "fallback",
  },
}
```

Completion-provided brackets are not automatically duplicated: only mapped
typed keys create pairs. Run `:checkhealth pairs` to inspect initialization and
mapping conflicts.

For an explicitly composed mapping:

```lua
require("pairs").setup({ mappings = { enabled = false } })
vim.keymap.set("i", '"', function()
  return require("pairs").expr('"') or '"'
end, { expr = true, replace_keycodes = false })
```

- `expr(key)` returns Neovim keycodes when handled, or `nil` for fallback.
- `handle(key)` returns the handled keycodes or the original keycodes.
- `explain(key)` returns the action and reason without changing text. Call it
  in Insert mode to inspect the actual insertion cursor. `:PairsInspect {key}`
  previews insertion **before** the Normal-mode cursor.
- `enable()`, `disable()`, and `toggle()` affect all buffers; pass a buffer
  number (`0` for current) to control one buffer.
- `teardown()` removes the plugin's mappings.

Use key notation such as `<BS>` or `<CR>` for special keys. Returned keycodes should be
used with `replace_keycodes = false` to avoid a second conversion. Insert
movement uses `<C-g>U` so generating/skipping a closer stays in the same undo
block and ordinary insertions remain dot-repeatable. Paste, macro recording
and replay, Replace mode, and special buffers bypass pairing.

## Development

```sh
./tests/run.sh
stylua --check lua tests plugin

# Also exercise actual Python/Rust/JavaScript grammars:
./tests/install-parsers.sh /tmp/pairs-parsers
PAIRS_TEST_PARSER_ROOT=/tmp/pairs-parsers ./tests/run.sh
```

Tests use actual Neovim input and cursor positions in isolated XDG directories.
They cover quotes, nesting, UTF-8 neighbors, backspace, Enter/indentation,
undo/redo, dot repeat,
configuration precedence, Tree-sitter literal/interpolation boundaries and
pending parses, completion/snippet-style buffer edits, macro/paste behavior,
and mapping lifecycle. CI checks the minimum
supported version and the current stable version, with pinned parser fixtures.
Parser fixtures are test-only and do not change your installed parsers. Real blink.cmp/LuaSnip
integration remains a separate manual acceptance check.

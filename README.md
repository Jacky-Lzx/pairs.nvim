# pairs.nvim

A small, conservative auto-pairs plugin for Neovim, with quote behavior as the
first priority. Pure Lua; Neovim 0.11 or newer; no runtime dependencies.

This is an initial implementation. It handles Insert-mode quotes, brackets,
matching-closer skipping, and empty-pair backspace. Pair expansion on Enter,
multi-character delimiters, wrapping, and command-line mode are planned rather
than implemented.

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
- Closing quotes are skipped only when the line-local lexer finds a matching
  opening quote. Bracket skipping also checks nesting, not delimiter counts.
- Single-quote opening is disabled by default for `text`, `markdown`, and
  `rust`. Single-quote skipping/deletion remain separate options.
- Common line comments are recognized by filetype. A string/comment suppresses
  automatic bracket insertion as well as quote insertion.

## Configuration

```lua
require("pairs").setup({
  enabled = true, -- or function(bufnr) return true end
  mappings = { enabled = true, bs = true },
  treesitter = false,
  max_scan_bytes = 4096,
  disabled_filetypes = { "TelescopePrompt", "snacks_picker_input" },
  pairs = {
    ["'"] = { open = false }, -- keep skip/delete, disable quote insertion
    ["("] = { skip = false },
    ["["] = false,           -- disable this entire rule
    -- Additional pairs are opt-in. All three actions default to true.
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

Enable `treesitter = true` to consult an already valid parser tree for string
and comment context, including raw/multiline strings. It does not install
parsers or synchronously parse the entire buffer. Missing parsers fall back to
the line-local lexer; a stale/unparsed tree conservatively passes keys through
until the parser is refreshed. Enable your normal Tree-sitter highlighter or
explicitly parse the buffer to provide that context.

Without syntax context, the lexer is intentionally line-local. It does not
fully understand multiline strings, block comments, interpolation, injected
languages, or all language-specific literal forms. Scans exceeding the byte
limit and malformed bracket prefixes pass the original key through.

## Mappings and completion

Setup preserves existing global mappings and leaves buffer mappings alone.
`require("pairs").status().conflicts` reports skipped keys. Disable the previous
pairs plugin instead of running two mapping owners together. Setup is
idempotent; teardown removes only mappings still owned by this plugin.

`<CR>` and `<Tab>` are never mapped. Completion confirmation and snippet
navigation therefore remain with their existing owners. Completion-provided
brackets are not automatically duplicated: only mapped typed keys create pairs.
Run `:checkhealth pairs` to inspect initialization and mapping conflicts.

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

Use key notation such as `<BS>` for special keys. Returned keycodes should be
used with `replace_keycodes = false` to avoid a second conversion. Insert
movement uses `<C-g>U` so generating/skipping a closer stays in the same undo
block and ordinary insertions remain dot-repeatable. Paste, macro recording
and replay, Replace mode, and special buffers bypass pairing.

## Development

```sh
./tests/run.sh
stylua --check lua tests plugin
```

Tests use actual Neovim input and cursor positions in isolated XDG directories.
They cover quotes, nesting, UTF-8 neighbors, backspace, undo/redo, dot repeat,
configuration precedence, optional Tree-sitter, completion/snippet-style buffer
edits, macro/paste behavior, and mapping lifecycle. CI checks the minimum
supported version and the current stable version. Real blink.cmp/LuaSnip
integration remains a separate manual acceptance check.

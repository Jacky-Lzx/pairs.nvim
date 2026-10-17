# pairs.nvim

Conservative quote and bracket pairing for Neovim 0.11+. Pure Lua, no runtime
dependencies. Supports matching-closer skipping, paired Backspace, indented
Enter, optional space padding, fast wrap, and syntax-aware language rules.

## Install

Disable other auto-pairs plugins. With lazy.nvim:

```lua
{
  "Jacky-Lzx/pairs.nvim",
  event = "InsertEnter",
  opts = {},
  config = function(_, opts)
    require("pairs").setup(opts)
  end,
}
```

For a local checkout, replace the repository name with `dir = "/path/to/pairs.nvim"`.
Calling `setup()` installs mappings; requiring the module alone does not.

## Behavior

`│` marks the insertion cursor. Defaults cover `()`, `[]`, `{}`, `""`, and `''`.

| Before | Input | After |
| --- | --- | --- |
| `│` | `"` | `"│"` |
| `"hello│"` | `"` | `"hello"│` |
| `don│t` | `'` | `don'│t` |
| `│hello` | `"` | `"│hello` |
| `(│)` | `)` | `()│` |
| `(│)` | `<BS>` | `│` |
| `{│}` | `<CR>` | Opening line, indented cursor line, closing line |

Quotes next to words or non-ASCII text open conservatively. Escapes, comments,
strings and bracket nesting are checked before pairing or skipping. Single-quote
opening is disabled in `text`, `markdown` and `rust` by default.

Enter uses `indentexpr` or `cindent` when configured, otherwise `shiftwidth`.
Undo/redo and dot repeat are supported. Tab is never mapped. Paste, macro
recording/replay, Replace mode and special buffers bypass pairing.

## Configure

Only overrides are needed:

```lua
require("pairs").setup({
  treesitter = true, -- optional; uses your installed parsers
  pairs = {
    ["("] = { space = true },
    ["["] = { space = true },
    ["{"] = { space = true },
    ["'"] = { open = false }, -- keep skipping/deletion
  },
  mappings = { fast_wrap = "<M-e>" }, -- optional Insert-mode shortcut
  filetypes = {
    markdown = { pairs = { ['"'] = { open = false } } },
    help = { enabled = false },
  },
})
```

Rules have independent `open`, `skip`, `delete`, `newline`, `space`, `skip_space`
and `wrap` flags; `false` disables a rule. Add custom single-character ASCII
pairs with `close`, e.g. `["<"] = { close = ">" }`. Closing delimiters must be
unique. Re-enabling a rule disabled with `false` requires its `close` value.

Precedence: defaults → global options → filetype → live buffer overrides:

```lua
vim.b.pairs_enabled = false
vim.b.pairs_rules = { ['"'] = { open = false } }
vim.b.pairs_multi_rules = { ["$$"] = false }
```

New delimiter/Space mappings must be declared globally or for a filetype during
setup, or composed explicitly. See `:help pairs-setup` for all options/defaults.

### Space padding

With `space = true` on `()`, `[]` or `{}`:

| Before | Input | After |
| --- | --- | --- |
| `(│)` | Space | `( │ )` |
| `( │ )` | Space | `(  │ )` |
| `( │ )` | `<BS>` | `(│)` |

Only the first space is mirrored; later spaces insert normally. Paired removal
requires exactly one ASCII space on each side. Enter trims this padding before
expanding. Set `skip_space = true` separately to make `( value│ )` + `)` move to
`( value )│`. Both options default to false.

### Fast wrap

With `mappings.fast_wrap = "<M-e>"`, invoke the shortcut immediately after an
opening bracket to wrap the next same-line target:

```text
(│value       → (value)│
(│obj.value   → (obj.value)│
(│)fn(a, b)   → (fn(a, b))│
```

Supports ASCII identifiers, dotted member chains and one complete call, reusing
or moving a matching closer when present. Incomplete calls, indexing, call
chaining and ambiguous literals pass through. See `:help pairs-fast-wrap`.

## Language rules

These features require `treesitter = true` with the appropriate installed
parser. Enable only the filetypes you use:

````lua
local templates = {
  pairs = { ["`"] = { close = "`" } },
  multi_pairs = { ["${"] = {} },
}
local tex = { multi_pairs = { ["$$"] = {}, ["\\("] = {}, ["\\["] = {} } }
require("pairs").setup({
  treesitter = true,
  filetypes = {
    python = { multi_pairs = { [string.rep('"', 3)] = {}, [string.rep("'", 3)] = {} } },
    javascript = templates,
    typescript = templates,
    markdown = { multi_pairs = { ["```"] = {}, ["~~~"] = {} } },
    tex = tex,
    plaintex = tex,
  },
  tex_environments = { theorem = "text", proof = "text", mycode = "literal" },
})
````

- Python: the third quote upgrades an empty string to a triple pair.
- JS/TS: backtick templates and `${…}` interpolation; the same options work for
  `javascriptreact` and `typescriptreact`.
- Markdown: Enter completes fences, including longer fences, lists and quotes.
- LaTeX: display dollars and inline/display backslash math. Environment modes
  are `"text"`, `"math"`, `"literal"`, or `false` to remove a custom declaration.
  Known text command arguments allow inline math; URL/path payloads stay literal.
  Built-in math/raw protections cannot be weakened.

See `:help pairs-triples`, `pairs-templates`, `pairs-fences`, and `pairs-tex`.

Tree-sitter also protects multiline/raw strings and block comments. Parsers are
not installed automatically. Missing parsers use a line-local lexer; pending or
unsafe syntax passes keys through. Work is bounded by `max_scan_bytes` (4096 by
default). General expression/selection wrapping, arbitrary multi-character
pairs and command-line mode are not supported.

## Completion and mappings

Existing global mappings are preserved; buffer mappings take precedence.
Check skipped keys with `:checkhealth pairs` or `require("pairs").status()`.
When blink.cmp owns Enter, compose pairing after completion acceptance:

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

For custom mappings, `expr(key)` returns keycodes or `nil` for fallback;
`handle(key)` returns keycodes including the original key on fallback. Use
`{ expr = true, replace_keycodes = false }` and account for queued input as
explained in `:help map-expression`. Disable the owned mapping when composing it
elsewhere, e.g. `mappings.space = false` for Space. See `:help pairs-api` for
`fast_wrap()`, `explain()`, enable/disable/toggle and teardown.

## Troubleshooting

- `:PairsToggle` toggles pairing globally.
- `:PairsInspect {key}` explains insertion before the Normal-mode cursor;
  accepts `<BS>`, `<CR>`, `<Space>` and the logical action `<FastWrap>`.
- `:checkhealth pairs` checks initialization and mapping conflicts.

To capture an actual mispair after the plugin loads:

```vim
PairsTrace clear
PairsTrace start
" Reproduce while editing, then return to Normal mode.
PairsTrace stop
PairsTrace show
PairsTrace export /tmp/pairs-trace.json
```

Export is explicit and local; use `PairsTrace! export` to overwrite. Records
include nearby text and effective rules, but not the entire buffer or parser
state. Multiline issues may need extra context. See `:help pairs-trace`.

## Development

```sh
./tests/run.sh
stylua --check lua tests plugin

# Optional pinned parser fixtures (separate from installed parsers):
./tests/install-parsers.sh /tmp/pairs-parsers
PAIRS_TEST_PARSER_ROOT=/tmp/pairs-parsers ./tests/run.sh

./tests/bench.sh
```

Tests exercise real Neovim input, cursor positions, mappings and undo/redo/dot
in isolated XDG directories. See [benchmark methods/results](docs/BENCHMARKS.md)
and [implementation notes/roadmap](docs/PLAN.md) for development details.

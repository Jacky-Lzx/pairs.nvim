# pairs.nvim

Quote and bracket pairing for Neovim 0.11+. Pure Lua, no runtime dependencies.

- Matching-closer skipping, paired Backspace and indented Enter.
- Optional space padding, fast wrap and surround editing.
- Rainbow brackets, enabled by default.
- Optional Tree-sitter support, language rules and custom multi-character pairs.

## Install

Disable other auto-pairs plugins. With lazy.nvim:

```lua
{
  "Jacky-Lzx/pairs.nvim",
  event = { "BufReadPost", "BufNewFile" },
  opts = {},
  config = function(_, opts)
    require("pairs").setup(opts)
  end,
}
```

This loads rainbow brackets and any enabled surround mappings before editing.
Use `event = "InsertEnter"` if you only need Insert-mode pairing. For other
plugin managers, call `require("pairs").setup({})` after loading.

## Basics

Defaults cover `()`, `[]`, `{}`, `""` and `''`. `│` marks the cursor:

| Before     | Input  | After                                            |
| ---------- | ------ | ------------------------------------------------ |
| `│`        | `"`    | `"│"`                                            |
| `"hello│"` | `"`    | `"hello"│`                                       |
| `don│t`    | `'`    | `don'│t`                                         |
| `(│)`      | `<BS>` | `│`                                              |
| `{│}`      | `<CR>` | Opening line, indented cursor line, closing line |

Quotes open conservatively near words and non-ASCII text. Single-quote opening
is disabled in `text`, `markdown` and `rust`. Undo/redo and dot repeat are
supported. Tab is never mapped; paste, macros and Replace mode bypass pairing.

## Configure

Setup validates every filetype override before replacing active mappings.
Unchanged rule layers share setup-owned data; matching metadata is compiled once
when that filetype is first used. All required keys are mapped during setup,
including keys used only by another filetype. Public resolve helpers still return
independent tables, and live buffer overrides remain uncached.

Only overrides are needed. Set these in lazy.nvim's `opts`, or pass them to
`setup()`:

```lua
require("pairs").setup({
  treesitter = true, -- optional; requires your own installed parsers
  pairs = {
    ["("] = { space = true },
    ["["] = { space = true },
    ["{"] = { space = true },
    ["'"] = { open = false }, -- keep skipping and paired deletion
  },
  mappings = { fast_wrap = "<M-e>" }, -- optional Insert-mode shortcut
  surround = { enabled = true }, -- optional; disabled by default
  filetypes = {
    markdown = { pairs = { ['"'] = { open = false } } },
    help = { enabled = false },
  },
})
```

Rules merge in this order: defaults → global → filetype → buffer overrides.
Use `false` to disable a rule, or `vim.b.pairs_enabled = false` to disable
pairing in one buffer. See `:help pairs-setup` for all options.

### Space padding and fast wrap

With `space = true`, `(│)` + Space becomes `( │ )`; Backspace removes both
spaces. Set `skip_space = true` to skip padding when typing a closer.
If Space is a mapping prefix, set `mappings.space = false`.

With the fast-wrap shortcut above, `(│value` becomes `(value)│`. Identifiers,
dotted member chains and one complete same-line call are supported.
See `:help pairs-space` and `:help pairs-fast-wrap`.

### Surround editing

With `surround.enabled = true`, these mini.surround-style mappings are available.
Disable competing surround mappings and load the plugin before Normal-mode use.

| Keys                | Action                                        |
| ------------------- | --------------------------------------------- |
| `sa{motion}{id}`    | Add; `saiw"` wraps a word in quotes           |
| Visual `sa{id}`     | Wrap the selection                            |
| `sd{id}`            | Delete; `sd)` removes parentheses             |
| `sr{old}{new}`      | Replace; `sr)"` changes parentheses to quotes |
| `sf{id}` / `sF{id}` | Find delimiter endpoints right / left         |
| `sh{id}`            | Highlight delimiters                          |
| `sn`                | Change the buffer's search range              |

Use closing bracket identifiers for compact output; opening identifiers add
inner spaces. `t` handles tags, `f` functions, and `?` prompts for literal left
and right strings. For example, `sr)?【<Enter>】<Enter>` changes `(word)` to
`【word】`. Dot repeat reuses prompt answers. See `:help pairs-surround` for
search options, custom delimiters and optional syntax-aware matching.

### Rainbow brackets

Enabled by default for `()`, `[]` and `{}`, independently of Tree-sitter.
Set `rainbow = { enabled = false }` to disable, or use `:PairsRainbowToggle`
for the current buffer. Palette, limits and lexical scope: `:help pairs-rainbow`.

`require("pairs.rainbow").snapshot(lines, ft)` returns rainbow decorations for
an immutable full document using the configured palette and lexical scanner.
It creates no buffers, timers or live cache entries. Each span contains
zero-based byte `row`, `col`, `end_col`, `hl_group` and `priority`; disabled or
over-limit documents return `nil`. Read-only hosts can project these spans into
previews, as git-tools does for full-document diffs.

### Language and custom pairs

Language rules are opt-in under `multi_pairs` and require `treesitter = true`
with the appropriate installed parser:

| Language                | Support                                    | Help                    |
| ----------------------- | ------------------------------------------ | ----------------------- |
| Python                  | Triple quotes                              | `:help pairs-triples`   |
| JavaScript / TypeScript | Backtick templates and interpolation       | `:help pairs-templates` |
| Markdown                | Code fences, including lists and quotes    | `:help pairs-fences`    |
| LaTeX                   | Math delimiters and environment protection | `:help pairs-tex`       |

Custom literal pairs can be scoped by filetype:

```lua
require("pairs").setup({
  filetypes = {
    markdown = { multi_pairs = { ["**"] = {}, ["~~"] = {} } },
    c = { multi_pairs = { ["/*"] = { close = "*/", newline = true } } },
  },
})
```

See `:help pairs-multi` for padding, context filters and shared surround rules.

## Mappings and troubleshooting

Existing mappings are preserved. If completion owns Enter, set
`mappings.cr = false` and compose `require("pairs").expr("<CR>")` after
completion acceptance; see `:help pairs-enter` for a blink.cmp example.

- `:PairsToggle` — toggle pairing globally.
- `:checkhealth pairs` — check setup and mapping conflicts.
- `:PairsInspect {key}` — explain pairing at the cursor.
- `:PairsTrace start` / `stop` / `show` — record and inspect a mispair.

Parsers are not installed automatically. Missing parsers use a line-local
lexer; pending or unsafe syntax passes keys through. Full reference:
[doc/pairs.txt](doc/pairs.txt) or `:help pairs.nvim`.

## Development

```sh
./tests/run.sh
stylua --check lua tests plugin
```

For parser fixtures and performance checks, see
[benchmarks](docs/BENCHMARKS.md) and [implementation notes](docs/PLAN.md).

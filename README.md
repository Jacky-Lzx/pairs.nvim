# pairs.nvim

Conservative quote and bracket pairing for Neovim 0.11+. Pure Lua, no runtime
dependencies. Supports matching-closer skipping, paired Backspace, indented
Enter, optional space padding, fast wrap, optional surround editing, rainbow
brackets, and syntax-aware language rules.

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
Rainbow brackets start when the plugin loads. Use `event = { "BufReadPost", "BufNewFile" }`
instead of `InsertEnter` to see colors before the first edit.

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

### Rainbow brackets

Enabled by default for `()`, `[]` and `{}`. Each nesting level cycles through
seven colors; a matching closer uses its opener's color, including across lines.
Unmatched closers keep their normal syntax color. This feature runs independently
of automatic pairing, its rules, and the `treesitter` option.

```lua
require("pairs").setup({
  rainbow = {
    enabled = true, -- false disables the feature entirely
    debounce_ms = 20,
    budget_ms = 2,
    -- Optional: replace the palette with existing highlight groups.
    -- highlights = { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo" },
  },
})
```

Use `:PairsRainbowToggle` for the current buffer, or set
`vim.b.pairs_rainbow = false`. Customize the default groups with `nvim_set_hl`:
`PairsRainbowRed`, `Yellow`, `Blue`, `Orange`, `Green`, `Violet` and `Cyan`
(each name starts with `PairsRainbow`). Color scheme changes restore defaults
without replacing explicit overrides.

The incremental lexer handles ordinary quoted strings, common line comments,
Lua long strings/comments, Python triple strings, C-style block comments,
Rust raw strings/nested comments, Go raw strings and JavaScript template
expressions. It is a lexical highlighter: regex literals, JSX, embedded languages
and other language-specific constructs can need a dedicated parser-based plugin.
Markdown and plain text use literal bracket nesting.

Work is debounced and split into background slices. Editing callbacks only
invalidate the cache; redraw callbacks only paint cached visible lines with
ephemeral highlights. Unchanged suffixes are reused after state convergence,
including after inserting/deleting lines. Hidden buffers release their caches.
Safety limits disable coloring for buffers above 100,000 lines, 2 MiB, 10,000
bytes per line, 256 nesting levels or 100,000 bracket characters. At most 2,000
brackets are painted per window per redraw. Limits are configurable; see
`:help pairs-rainbow`. Pair insertion continues when a rainbow limit is reached.

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

The Space mapping uses `<nowait>` to avoid waiting for a longer mapping. To use
Space as a mapping prefix, set `mappings.space = false`.

For multi-character pairs, enable `space` on the individual rule:

```lua
multi_pairs = { ["\\("] = { space = true } }
```

This supports Python triple quotes, `${…}` and LaTeX `$$`, `\(…\)`, `\[…\]`,
with `treesitter = true` and an installed parser. Space, Backspace and Enter
follow the same padding rules, retaining each family's Enter behavior.
`space` defaults to false and is unsupported for Markdown fences.

### Custom multi-character rules

Define literal pairs alongside the existing language families:

```lua
require("pairs").setup({
  surround = { enabled = true },
  filetypes = {
    markdown = {
      multi_pairs = {
        ["**"] = { surround = "*" }, -- defaults to close = "**"
        ["~~"] = { surround = "~" },
      },
    },
    c = {
      multi_pairs = {
        ["/*"] = { close = "*/", newline = true, surround = "c" },
      },
    },
  },
})
```

Typing the opener's last character completes the pair. Closing characters skip
one at a time only after a complete surrounding is found. Empty pairs support
paired Backspace, optional space padding and optional indented Enter. Existing
complete closers and closers inserted by standard pairs (such as `[[…]]`) are
reused. Native undo/redo and dot repeat work, including multiline expansion.

Generic defaults are `open/skip/delete = true`, `newline/space = false`, and
`contexts = { "code" }`. Opt into string/comment contents with `contexts`.
An optional `condition(ctx, action)` returns true to permit an action (`open`,
`skip`, `delete`, `newline`, `space`); it can further restrict the allowed
contexts. Pending syntax never invokes the condition. For Markdown, use
`condition = function(ctx) return not ctx.fence end` to exclude parsed fences.
Prose markers should be enabled in their filetypes rather than globally.

Openers must be 2-64 printable ASCII bytes; closers 1-64 bytes. At most 128
multi-character rules are allowed. Generic openers cannot be prefixes of each
other or overlap enabled specialized families, and their closers must be unique.
Markdown `~~` can coexist with `~~~`: with parser context, the third tilde on
an empty fence line upgrades the strikeout pair into a fence opener.
Long quote/fence runs still use the existing three-character family. Explicit
language rules retain precedence and their parser guards. Generic searches
cover up to 32 lines ending at the cursor line, within `max_scan_bytes`; an
unproven closer is typed normally. No mutable pair-tracking state is retained.

The optional `surround` identifier shares left/right strings with surround:
`saiw*` / `sd*` use the same Markdown bold definition. Auto-pair action flags do
not control explicit surround edits. Explicit `custom_surroundings` override
shared definitions, including `false` to disable an identifier. Filetype and
live `vim.b.pairs_multi_rules` overrides apply to both features.

### Surround editing

Enable an independent surround module with mini.surround-style
keys. It is disabled by default. Disable mini.surround before using the same
keys, and load pairs.nvim before Normal-mode editing (for example on
`VeryLazy`, instead of only `InsertEnter`):

```lua
require("pairs").setup({
  surround = { enabled = true },
})
```

- `sa{motion}{id}` adds surroundings; `saiw"` wraps a word in double quotes.
  `sa_` wraps the line while preserving its outer whitespace. Visual `sa{id}`
  wraps the selection. User text objects, including mini.ai mappings, work.
- `sd{id}` deletes surroundings; `sd)` changes `(word)` to `word`.
- `sr{old}{new}` replaces surroundings; `sr)"` changes `(word)` to `"word"`.
- `sf{id}` / `sF{id}` cycle right / left through the delimiter endpoints.
- `sh{id}` highlights the delimiters for 500ms; `sn` changes the current
  buffer's search range after a prompt.

Opening bracket identifiers `(`, `[`, `{`, `<` add inner spaces and trim inner
whitespace when deleting/replacing. Closing identifiers use compact output
and preserve inner whitespace. `b` searches any of `()[]{}` and outputs `()`;
`q` searches any quote and outputs double quotes. `t` handles nested HTML/XML
tags and prompts for a tag with optional attributes. `f` handles function
calls and prompts for a function name. `?` prompts for literal left/right
strings. Other characters surround with themselves; escaped delimiters are
ignored during searches.

Search defaults to the innermost surrounding that covers the cursor, within
20 lines in either direction. Counts choose outer surroundings (`2sd)`), or
repeat added wrappers (`2saiw)`). Motion counts work separately (`sa2aw)`).
Suffix `l` / `n` searches previous / next surroundings (`sdl)`, `sdn)`).
Normal-mode edits support native undo/redo, dot repeat and macros. Dot reuses
the resolved identifiers and prompt answers at the new cursor. Visual edits
support undo/redo; they do not register a new surround dot repeat.

```lua
surround = {
  enabled = true,
  treesitter = false, -- true: ignore brackets in parsed strings/comments
  n_lines = 20,
  search_method = "cover", -- also cover_or_next/prev/nearest, next, prev, nearest
  respect_selection_type = false, -- true: linewise blocks / wrap each block row
  custom_surroundings = {
    ["*"] = {
      input = { left = "**", right = "**" },
      output = { left = "**", right = "**" },
    },
  },
}
```

Custom input/output specifications are literal strings or callbacks returning
`{ left = ..., right = ... }` (or `nil` to cancel), including multiline strings.
An input callback can also return a list of regions, each with `left` and
`right` ranges: `{ from = { row, byte_col }, to = { row, byte_col } }`. Positions
are zero-based and ends exclusive. The callback receives the buffer, bounded
search text/lines, and cursor position; it runs again at the new cursor on dot
repeat. Regions are validated before editing. Custom literal specifications
retain literal matching when syntax checking is enabled. These specifications use
pairs.nvim's API, rather than mini.surround's Lua-pattern format.

Optional `surround.treesitter = true` protects brackets inside strings/comments
and selects complete parsed quotes, including triple quotes. For example,
`sdf` inside `fn("a)b")` removes the complete function wrapper. Literal text
inside templates is protected while substitutions remain code. Missing parsers
retain text matching; pending/error trees cancel the operation without waiting.
Queries visit at most 10,000 nodes and 256 levels inside the search window.
Filetype overrides use `filetypes.<ft>.surround`; live buffer overrides use
`vim.b.pairs_surround_config`. Set `vim.b.pairs_surround_enabled = false` to
disable only surround in a buffer. The global/buffer pairs toggle also applies.
Surround mappings are configured globally; use `''` to disable a key, or
`<Plug>(pairs-surround-add/delete/replace/find/find_left/highlight/update_n_lines)`
for custom bindings. Existing mappings are preserved and reported by health.
Search is bounded to 1 MiB by default. See `:help pairs-surround` for details.

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
default). Fast wrap accepts only its documented targets; use surround for
explicit motions/selections. Generic multi-character rules are literal and
bounded; command-line auto-pairing is not supported.

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
- `:PairsRainbowToggle` toggles rainbow brackets in the current buffer.
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
./tests/bench-rainbow.sh
```

Tests exercise real Neovim input, cursor positions, mappings and undo/redo/dot,
plus rendered rainbow colors through an embedded Neovim UI, in isolated XDG
directories. See [benchmark methods/results](docs/BENCHMARKS.md)
and [implementation notes/roadmap](docs/PLAN.md) for development details.

# pairs.nvim

A small, conservative auto-pairs plugin for Neovim, with quote behavior as the
first priority. Pure Lua; Neovim 0.11 or newer; no runtime dependencies.

It handles Insert-mode quotes, brackets, matching-closer skipping, empty-pair
backspace, and empty-bracket expansion on Enter. Python triple quotes,
JavaScript/TypeScript templates and Markdown fences are available as opt-in
rules. Other multi-character delimiters, wrapping, and command-line mode are
planned.

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
Multi-character rules use the separate `multi_pairs` option described below.
LaTeX `$$` is not supported yet. Do not enable `<>` globally unless
you want it to pair operators. To re-enable an entire single-character rule
disabled with `false`, provide its `close` value along with the override.

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

## Python triple quotes

Triple quotes are disabled by default. Enable them for Python with an installed
Python Tree-sitter parser:

```lua
require("pairs").setup({
  treesitter = true,
  filetypes = {
    python = {
      multi_pairs = {
        [string.rep('"', 3)] = {},
        [string.rep("'", 3)] = {},
      },
    },
  },
})
```

Typing three identical quotes upgrades the preceding empty string into a
triple-quoted pair. Both quote styles and Python prefixes `r`, `u`, `b`, `f`,
`br`, `rb`, `fr`, and `rf` are supported, including uppercase variants.

| Before | Input | After |
| --- | --- | --- |
| `""│` | `"` | `"""│"""` |
| `"""body│"""` | `"` | `"""body"│""` |
| `"""│"""` | `<BS>` | `│` |

Three closing-key presses move across a closing triple delimiter one quote at a
time. Quotes inside the body pass through. Enter in an adjacent empty triple
creates a middle and closing line at the opening line's indentation, keeping
docstring content aligned with its delimiter. Undo/redo and dot repeat retain
the complete insertion.

Multi-character rules have independent `open`, `skip`, `delete`, and `newline`
flags, all defaulting to `true`; `false` disables a whole rule. Overrides use
global `multi_pairs`, filetype `multi_pairs`, then `vim.b.pairs_multi_rules`.
This rule family applies only to Python. The parser must confirm an
empty short string or a real closing triple delimiter; unavailable or pending
syntax cannot trigger triple pairing. Ordinary quote behavior remains the
fallback when syntax context is unavailable.

## JavaScript and TypeScript templates

Enable backticks and interpolation separately for the desired filetypes:

```lua
local templates = {
  pairs = { ["`"] = { close = "`" } },
  multi_pairs = { ["${"] = {} },
}
require("pairs").setup({
  treesitter = true,
  filetypes = {
    javascript = templates,
    javascriptreact = templates,
    typescript = templates,
    typescriptreact = templates,
  },
})
```

The rules are opt-in. Install the appropriate JavaScript, TypeScript or TSX
parser for syntax-aware handling. React filetypes use JavaScript/TSX aliases
when no custom parser-language mapping has been registered.

- Backticks create an empty template, including after a tag such as `html` or
  `factory()`. Typing a backtick at the real closing delimiter skips it, even
  on another line. Backspace deletes an adjacent empty template, retaining its
  tag. Template boundaries come from the outer JS/TS grammar even when a tag
  injects HTML or another language. Enter inside a template remains an ordinary
  newline.
- In template text, typing `{` after an unescaped `$` produces `${│}`. An
  existing following `}` is reused. Opening before existing words is suppressed.
- Inside `${...}`, normal code pairing applies, including nested templates,
  strings, parentheses and object braces. Only the real interpolation closing
  `}` is skipped. Literal quotes and ordinary braces in template text pass
  through; string/comment/regex/JSX text contexts remain protected.
- Backspace in `${│}` deletes all three characters. Enter expands it into an
  indented expression and closing line using the usual bracket indentation.

Backtick rules use the standard single-character `open`, `skip` and `delete`
flags. Interpolation rules use `multi_pairs["${"]`, with implicit `close = "}"`
and independent `open`, `skip`, `delete` and `newline` flags, all defaulting to
`true`. Global/filetype/buffer rule precedence is unchanged. Interpolation
handling works independently of the backtick and ordinary brace rules.
Advanced template handling requires current parser context; missing parsers
use the line-local lexer, and pending parses preserve the original key.
Rules follow the [ECMAScript template syntax](https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-template-literal-lexical-components).

## Markdown code fences

Enable the triple-backtick fence rule with an installed Markdown parser:

```lua
require("pairs").setup({
  treesitter = true,
  filetypes = { markdown = { multi_pairs = { ["```"] = {} } } },
})
```

At the end of a new opening line, type three backticks and an optional language
name, then press Enter. The plugin creates a blank middle line and a matching
closing line, placing the cursor on the middle line. The language/info string
is preserved. Content and closing indentation match the opening line, including
its zero to three spaces of indentation relative to any containing list/quote.

An opening line with existing code content or a closing fence inserts a single
line, keeping the existing block intact. Within a list or quote, the new line
receives the container's continuation prefix. Closing fences are skipped one
backtick at a time only at parser-confirmed closing positions; longer closing
fences are recognized. Markdown's outer block tree owns these positions even
when the body has an injected code-language parser.

The rule is opt-in and supports exactly three opening backticks at the top level,
inside lists and block quotes, and in nested combinations. List markers become
continuation indentation; quote markers remain on the body and closing lines.
For example, Enter after `> - ```lua` creates:

````markdown
> - ```lua
>   │
>   ```
````

The cursor marker shows the insertion position. Tabs in container prefixes
become spaces using Markdown's four-column tab stops, independently of the
buffer's `tabstop`/`expandtab`. Native comment continuation and `indentexpr` do
not duplicate or change the generated prefix.

Inline code, HTML blocks, four-space indented code relative to its container,
longer/tilde openers, task-marker text, and Enter within the info string keep their
ordinary input behavior. The rule does not enable inline backtick pairing.
Enter within existing code content remains native buffer behavior.
Its context checks follow [CommonMark fence syntax](https://spec.commonmark.org/0.31.2/#fenced-code-blocks).

`multi_pairs["```"]` has implicit `close = "```"`; `open`, `newline` and `skip`
default to `true`. Both `open` and `newline` must be enabled for expansion.
`false` disables the entire rule. Global/filetype/`vim.b.pairs_multi_rules`
precedence is unchanged. Backspace remains ordinary deletion; `delete = true`
is unsupported and rejected. Undo/redo and dot repeat retain the entire
insertion. Missing/pending parser context preserves the original key.

When blink.cmp owns Enter, keep the existing accept → `pairs.expr("<CR>")` →
fallback chain. Accepting a language-name completion does not expand the fence;
the following Enter does.

## Mappings and completion

Setup preserves existing global mappings and leaves buffer mappings alone.
`require("pairs").status().conflicts` reports skipped keys. Disable the previous
pairs plugin instead of running two mapping owners together. Setup is
idempotent; teardown removes only mappings still owned by this plugin.
Plugin-owned keys flush preceding typed text before evaluating their expression
through a private `<Plug>` mapping. This keeps fast continuous input and string
prefixes consistent with the actual insertion context.

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
When composing your own mappings, account for Neovim's expression evaluation
order: preceding text may still be queued. See the
[expression mapping documentation](https://neovim.io/doc/user/map.html#map-expression)
for the `<Ignore>` pattern used by this plugin's mappings.

## Development

```sh
./tests/run.sh
stylua --check lua tests plugin

# Also exercise actual Python/Rust/JavaScript/TypeScript/TSX grammars:
./tests/install-parsers.sh /tmp/pairs-parsers
PAIRS_TEST_PARSER_ROOT=/tmp/pairs-parsers ./tests/run.sh
```

Tests use actual Neovim input and cursor positions in isolated XDG directories.
They cover quotes, nesting, UTF-8 neighbors, backspace, Enter/indentation,
undo/redo, dot repeat,
configuration precedence, Python triple quotes and prefixes, JavaScript/TypeScript
templates, tagged/nested templates and interpolation, Markdown fence boundaries
and code-language injections,
Tree-sitter literal/interpolation boundaries and
pending parses, completion/snippet-style buffer edits, macro/paste behavior,
and mapping lifecycle. CI checks the minimum
supported version and the current stable version, with pinned parser fixtures.
Parser fixtures are test-only and do not change your installed parsers. Real blink.cmp/LuaSnip
integration remains a separate manual acceptance check.

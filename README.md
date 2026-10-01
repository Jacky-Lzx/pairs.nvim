# pairs.nvim

A small, conservative auto-pairs plugin for Neovim, with quote behavior as the
first priority. Pure Lua; Neovim 0.11 or newer; no runtime dependencies.

It handles Insert-mode quotes, brackets, matching-closer skipping, empty-pair
backspace, empty-bracket expansion on Enter, and explicit same-line wrapping of
identifiers and member chains. Python triple quotes,
JavaScript/TypeScript templates, Markdown fences and LaTeX math delimiters are
available as opt-in rules. Other multi-character delimiters, general expression/
selection wrapping, and command-line mode are planned.

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
Do not enable `<>` globally unless you want it to pair operators. To re-enable an entire single-character rule
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

Enable either fence family with an installed Markdown parser:

```lua
require("pairs").setup({
  treesitter = true,
  filetypes = {
    markdown = { multi_pairs = { ["```"] = {}, ["~~~"] = {} } },
  },
})
```

At the end of a new opening line, type three or more backticks or tildes and an
optional language name, then press Enter. The plugin creates a blank middle line
and a matching closing line, placing the cursor on the middle line. The language/info string
is preserved. The new closing fence uses the opening character and exact length.
Content and closing indentation match the opening line, including
its zero to three spaces of indentation relative to any containing list/quote.

An opening line with existing code content or a closing fence inserts a single
line, keeping the existing block intact. Within a list or quote, the new line
receives the container's continuation prefix. Closing fences are skipped one
character at a time only at parser-confirmed closing positions. Existing closing
fences must use the same character and be at least as long as the opening fence;
shorter or different-character lines remain code content.
Markdown's outer block tree owns these positions even when the body has an
injected code-language parser.

Both families are opt-in and support any opening length of at least three at
the top level, inside lists and block quotes, and in nested combinations. List
markers become continuation indentation; quote markers remain on the body and closing lines.
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
task-marker text, and Enter within the info string keep their
ordinary input behavior. The rule does not enable inline backtick pairing.
Backtick-fence info strings cannot contain backticks; tilde-fence info strings
may contain them.
Enter within existing code content remains native buffer behavior.
Its context checks follow [CommonMark fence syntax](https://spec.commonmark.org/0.31.2/#fenced-code-blocks).

The configuration keys `multi_pairs["```"]` and `multi_pairs["~~~"]` identify
families, covering all lengths. Longer configuration keys are rejected. Each
rule has an implicit `close` matching its family key; the generated closing text
always matches the actual opening length. `open`, `newline` and `skip` default
to `true`. Both `open` and `newline` must be enabled for expansion.
`false` disables that family independently. Global/filetype/`vim.b.pairs_multi_rules`
precedence is unchanged. Backspace remains ordinary deletion; `delete = true`
is unsupported and rejected. Undo/redo and dot repeat retain the entire
insertion. Missing/pending parser context preserves the original key.

When blink.cmp owns Enter, keep the existing accept → `pairs.expr("<CR>")` →
fallback chain. Accepting a language-name completion does not expand the fence;
the following Enter does.

## LaTeX display dollars

Enable the rule with an installed `latex` Tree-sitter parser:

```lua
require("pairs").setup({
  treesitter = true,
  filetypes = {
    tex = { multi_pairs = { ["$$"] = {} } },
    plaintex = { multi_pairs = { ["$$"] = {} } },
  },
})
```

The first `$` remains literal. A second `$` upgrades it only on a line containing
indentation and that single dollar, with whitespace or nothing after the cursor.
`tex` and `plaintex` use the standard `latex` parser alias unless an explicit
language registration overrides it.

| Before | Input | After |
| --- | --- | --- |
| `│` | `$` | `$│` |
| `$│` | `$` | `$$│$$` |
| `cost $│` | `$` | `cost $$│` |
| `$$x│$$` | `$$` | `$$x$$│` |
| `$$│$$` | `<BS>` | `│` |

Enter in `$$│$$` creates `$$\n│\n$$`. The body and closing line use the
opening line's indentation, including tabs. Existing body content keeps native
Enter behavior. Parser-confirmed closing dollars skip one character at a time;
body dollars and mismatched delimiters stay literal. Single-dollar inline math
and `\(...\)`/`\[...\]` pairing are outside this rule.

Comments, existing math, verbatim/listing/minted environments and inline
`\verb` spans keep their original keys. `\lstinline` and `\mintinline` conservatively
protect the rest of their line. Unfinished ordinary environments such as
`document`, `center`, lists and figures can recover an opening boundary;
unknown environments, unresolved earlier delimiters and recovery prefixes
exceeding 256 syntax nodes pass through. Missing/pending parsers
also preserve original input. No synchronous parse or buffer-wide text scan
is requested.

The implicit closer is `"$$"`. Independent `open`, `skip`, `delete` and `newline`
flags default to `true`; `false` disables the rule. Global/filetype/buffer
precedence, native undo/redo/dot and completion-owned Enter composition are the
same as the other opt-in rules.

## LaTeX backslash math delimiters

Enable inline `\(...\)` and display `\[...\]` independently, with
`treesitter = true` and the same installed `latex` parser:

```lua
require("pairs").setup({
  treesitter = true,
  filetypes = {
    tex = { multi_pairs = { ["\\("] = {}, ["\\["] = {} } },
    plaintex = { multi_pairs = { ["\\("] = {}, ["\\["] = {} } },
  },
})
```

| Before | Input | After |
| --- | --- | --- |
| `│` | `\(` | `\(│\)` |
| `word \│` | `(` | `word \(│\)` |
| `│` | `\[` | `\[│\]` |
| `\(x│\)` | `\)` | `\(x\)│` |
| `\[│\]` | `<BS>` | `│` |

An unescaped backslash prefix opens a pair in parser-confirmed text context,
when the next character permits pairing. Existing math, comments, literal code,
unknown environments and unsafe incomplete syntax preserve the original key.
Opening does not require a standalone line. Ordinary brackets and backslash
commands keep their usual behavior.

Both characters of a parser-confirmed closer are skipped individually, including
its backslash. This avoids adding another backslash when typing `\)` or `\]`.
A bare `)` or `]` before the whole closer remains literal. Adjacent empty pairs
can be deleted with Backspace. Enter in `\[│\]` produces `\[\n│\n\]`, with
the opening indentation on the body and closing lines. Inline Enter and Enter
in nonempty formulas use native buffer behavior by default.

The implicit closers are `"\\)"` and `"\\]"`. `open`, `skip` and `delete` default
to `true`. `newline` defaults to `false` for `"\\("` and `true` for `"\\["`;
it can be overridden independently. `false` disables either rule. Existing
precedence and parser-unavailable fallback apply. Native undo/redo and dot
retain the complete insertion.

Enabling either rule registers a deferred Insert mapping for `\` as well as its
bracket keys. Existing mappings are preserved and reported by `status().conflicts`;
a custom owner can compose `expr("\\")` to use the backslash skip behavior.
Completion/snippet buffer edits are not re-paired. Keep the existing
accept → `pairs.expr("<CR>")` → fallback chain when completion owns Enter.

## LaTeX environment declarations

Extend the known environment modes with `tex_environments`. Declarations apply
in `tex` and `plaintex`, require current `latex` parser context and do not enable
math delimiter rules themselves:

```lua
require("pairs").setup({
  treesitter = true,
  tex_environments = {
    abstract = "text",
    theorem = "text",
    proof = "text",
    mymath = "math",
    mycode = "literal",
  },
  multi_pairs = { ["$$"] = {}, ["\\("] = {}, ["\\["] = {} },
})
```

| Mode | Behavior |
| --- | --- |
| `"text"` | Allow configured math pairs at valid boundaries. |
| `"math"` | Preserve math delimiter input; ordinary brackets still pair. |
| `"literal"` | Preserve all plugin-owned keys, including quote/bracket input, Backspace and Enter. |
| `false` | Remove a text/custom declaration; treat the name as unknown. |

Defaults include the previously supported text environments (`document`, lists,
figures, etc.) and the parser's built-in math/raw environments. Unknown names
remain conservative for math delimiters. Names match exactly, including a `*`
suffix; declarations are not wildcard patterns. Names must be 1–62 ASCII letters,
digits or `_`, `.`, `:`, `-`, `*` characters. Built-in math protections can be
strengthened to `"literal"`; built-in math/raw modes cannot be weakened or removed.
Parser-confirmed math, comments and raw nodes retain their protection.

Overrides merge in the order defaults → global `tex_environments` →
`filetypes[ft].tex_environments` → `vim.b.pairs_tex_environments`:

```lua
-- Setup-time override for one filetype:
filetypes = { tex = { tex_environments = { proof = "math" } } }
-- Live buffer override:
vim.b.pairs_tex_environments = { proof = "text", mycode = "literal" }
```

An inner text environment cannot lift an outer math/literal restriction. Raw
code may contain environment-looking text; its matching end command releases
that scope. Completed sibling environments do not affect the following text.
A complete `\begin{name}` header can establish a mode before its `\end{name}`
is written, including file-end blank lines. Partial headers, mismatched scopes
and unprovable recovery preserve input. Each prefix traversal is limited to 256
syntax nodes and excludes future content. Declaring custom raw modes also checks
preceding scope metadata, so unresolved/over-budget prefixes keep all pairing
keys native. No full buffer-text scan, synchronous parse or highlighting setup
is requested.

VimTeX indentation, existing mappings, completion and snippet expansion keep
their own behavior. A missing parser retains the existing line-local lexer
fallback; environment modes require parser evidence. Pending parses pass keys
through. Invalid setup options preserve the current setup; invalid buffer
options pass keys through with a `context_error` diagnostic from `explain()`.

## LaTeX command arguments

With `treesitter = true` and a current `latex` parser, known command arguments
have their own context in `tex` and `plaintex`. No extra option is required.
Existing `multi_pairs` options still control math delimiters:

```lua
require("pairs").setup({
  treesitter = true,
  multi_pairs = { ["\\("] = {} },
})
```

- Text arguments of `\section`, `\subsection`, `\subsubsection`, `\chapter`,
  `\part`, `\paragraph`, `\subparagraph` (including starred forms), `\textbf`,
  `\textit`, `\textrm`, `\textsf`, `\texttt`, `\textnormal`, `\emph` and
  `\underline` allow ordinary brackets and configured `\( … \)` pairs.
  Heading optional titles also count as text. Display openings `\[` and `$$`
  stay native inside command arguments.
- `\url`, `\nolinkurl`, `\path` and the first mandatory `\href` argument keep
  payload quotes, brackets, math delimiters, Backspace and Enter native. The
  second mandatory `\href` argument is text; its optional settings remain
  conservative for math input.
- The outer argument braces, and heading optional-title brackets, follow their
  normal configured rules. Proven structural closers can be skipped, including
  across lines; Backspace between empty outer delimiters can remove both.
  Brackets inside a raw payload do not get this treatment.

For example, typing `\(` at `\textbf{│}` produces `\textbf{\(│\)}`; typing
`(` at `\url{│}` produces `\url{(│}`. A URI quote or `%20` does not hide the
following text after the argument ends. A real comment after a URI remains a
comment. Escaped braces and nested groups are accounted for.

Unfinished mandatory/optional parameters and trailing blank lines use a bounded
prefix anchored in the current syntax tree: at most 32 lines and 4096 bytes.
The byte budget is checked before reading the prefix; no future body text or
full buffer scan is requested. Unsafe or over-budget recovery preserves input.
Unknown command parameters remain conservative for math delimiters. Outer
math/raw environments, comments and parser-confirmed text-in-math nodes retain
their restrictions. Missing parsers retain the existing line-local fallback;
pending parses pass keys through without forcing synchronous parsing. With
Tree-sitter enabled, LaTeX lines beyond `max_scan_bytes` also pass keys through,
so a long future suffix cannot bypass raw protection.

VimTeX indentation, completion/snippet expansion and mapping ownership retain
their existing behavior. Command argument profiles currently cover the built-in
names above; user-defined command profiles are not configurable.

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
- `fast_wrap()` returns keycodes to wrap the next identifier or member chain, or `nil` for fallback.
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

## Fast wrap

Fast wrap encloses the next same-line ASCII identifier or dotted member chain
after an opening `(`, `[` or `{`, leaving the cursor after its closer. It inserts
a missing closer, reuses one immediately after the target, or moves an adjacent
empty pair's closer around the target:

| Before | Action | After |
| --- | --- | --- |
| `(│value` | fast wrap | `(value)│` |
| `(│obj.value` | fast wrap | `(obj.value)│` |
| `(│obj.value)` | fast wrap | `(obj.value)│` |
| `(│)config.options.enabled` | fast wrap | `(config.options.enabled)│` |
| `(│value)` | fast wrap | `(value)│` |
| `(│)value` | fast wrap | `(value)│` |
| `[│]item_2` | fast wrap | `[item_2]│` |
| `fn((│)value, next)` | fast wrap | `fn((value)│, next)` |

No shortcut is installed by default. To enable an optional Insert-mode shortcut:

```lua
require("pairs").setup({ mappings = { fast_wrap = "<M-e>" } })
```

Use a recognized single non-text key such as `<M-e>` or `<F8>`. Text keys,
Backspace/Enter/Tab/Escape and command pseudo-keys are rejected before setup.
Existing global/buffer shortcut owners are preserved and conflicts are reported.
The owned shortcut flushes queued input before deciding and does nothing when
wrapping is unavailable. `mappings.enabled = false` prevents its installation.

`fast_wrap()` is an expression API returning native keycodes or `nil`; it does
not edit the buffer when called. Custom owners can compose it before their own
fallback. Returned keycodes require `replace_keycodes = false`. Account for
queued typed text using the same `<Ignore>`/private expression mapping pattern
as the plugin's owned shortcut.

Type `(` at `│value`, then invoke the shortcut to produce `(value)│`. The normal
opening policy remains the same; fast wrap explicitly supplies the missing
closer. The cursor must be immediately after the opening bracket, with the
target directly after the cursor or an adjacent closer. Each identifier matches
`[A-Za-z_][A-Za-z0-9_]*`; a chain joins these identifiers with single dots and
no intervening whitespace, such as `self.name` or `config.options.enabled`.
Incomplete members, repeated dots, Unicode identifiers, leading whitespace,
padding, quotes, calls, indexing and immediately adjoining operators are
outside this version's target support. Unsupported chains are left untouched,
including `obj.value()`, `obj.value[0]`, `obj?.value` and `obj.`.
End of line, whitespace, commas, semicolons and standard closing brackets
terminate a target; following text is preserved. The whole dotted chain wraps.
An existing matching closer must immediately follow the target to be reused;
spaces and other suffix text are preserved. Reuse follows the current bracket
nesting and does not repair other unclosed outer brackets.

The single-character `wrap` flag defaults to true for standard brackets and
false for other rules. Disable it per rule, filetype or live `b:pairs_rules`.
It is independent of `open`, `skip`, `delete`, `space` and `skip_space`.
Changing a standard closer to a custom one disables inherited wrapping;
existing custom rules remain valid. Explicit `wrap = true` requires a standard pair.
Strings/comments, unsafe/pending syntax, escaped/unmatched prefixes and
structural interpolation delimiters do not wrap. The complete same-line prefix
and target share `max_scan_bytes`, with one boundary-lookahead byte.
Missing parsers retain the existing line-local lexer fallback.

Native movement and any required deletion/insertion preserve undo/redo and dot repeat; dot
replays the recorded movement length rather than selecting a new target.
`:PairsInspect <FastWrap>` previews the decision without editing. Actual calls
are traced with the logical key `<FastWrap>`, the `wrap` policy, target length,
and `remove_close`/`insert_close` flags, including false flags for pure reuse.
Reproduce an exported wrap through `fast_wrap()` or `expr("<FastWrap>")`;
`<FastWrap>` is an API action name, not a physical key. `handle("<FastWrap>")`
returns an empty string on fallback.

## Empty-bracket space padding

Padding is disabled by default. Enable it independently for `()`, `[]` or `{}`:

```lua
require("pairs").setup({
  pairs = {
    ["("] = { space = true },
    ["["] = { space = true },
    ["{"] = { space = true },
  },
})
```

| Before | Input | After |
| --- | --- | --- |
| `(│)` | Space | `( │ )` |
| `[│]` | Space | `[ │ ]` |
| `{ │ }` | `<BS>` | `{│}` |
| `{ │ }` | `<CR>` | `{` + indented middle line + `}` |

Space adds one ASCII space on each side only between adjacent empty brackets.
Backspace removes those two spaces, retaining the brackets; a second Backspace
can remove the remaining empty pair. Enter removes the padding before applying
the existing indentation logic. Undo/redo and dot repeat preserve the insertion.
`space` defaults to false, while `delete` and `newline` retain their independent
control over Backspace and Enter. `open = false` still permits padding of an
existing bracket pair when `space = true`.

Exactly one space must sit on each side of the cursor for paired removal or
Enter expansion. Manually inserted identical padding behaves the same way.
For Space, Backspace and Enter, nonempty brackets, repeated spaces, tabs,
strings, comments, escaped/unproven openers, pending syntax and scans beyond
the budget use ordinary input.
Interpolation's structural braces retain their language rule; ordinary brackets
inside its code expression can opt in. Closing-delimiter skipping requires an
adjacent closer by default. Opt into crossing one right-hand space separately:

```lua
require("pairs").setup({
  pairs = {
    ["("] = { space = true, skip_space = true },
    ["["] = { space = true, skip_space = true },
    ["{"] = { space = true, skip_space = true },
  },
})
```

With `skip_space = true`, `( value│ )` + `)` becomes `( value )│`; nested pairs
work the same way. The right side must contain exactly one ASCII space followed
immediately by the matching closer, with a proven same-line opener in the
existing bounded scan. Multiple spaces, tabs, other intervening text, strings,
comments, escaped/unmatched prefixes and pending syntax keep ordinary input.
Structural interpolation closers retain their language rules.

`skip_space` defaults to false and still requires `skip = true`. It is independent
of `space`: manually entered padding also works, and enabling only `skip_space`
does not install a Space mapping. Only `()`, `[]` and `{}` support this option.
Global, filetype and live `b:pairs_rules` precedence remains the same. Movement
preserves text and the existing typed-key undo/redo/dot behavior; trace exports
include the policy and the two-position movement.

The plugin installs Space only if a global/filetype rule declares `space = true`
and `mappings.space` is true (the default). It preserves existing global and
buffer mappings. Set `mappings.space = false` for a Space mapping owned elsewhere
and compose `expr("<Space>")` before that owner's native fallback. A literal
`" "` works with the API too. Enter composition continues to use `expr("<CR>")`.
Filetype/buffer overrides follow the usual precedence and stay live. A buffer-only
activation requires a Space mapping already declared at setup or explicitly
composed by its owner. The first version supports the standard bracket shapes
only; quote/multi-character padding is not enabled by this option.

## Trace a mispair

After the plugin has loaded, start tracing, reproduce the unexpected behavior,
then stop and inspect it:

```vim
PairsTrace clear
PairsTrace start
" Reproduce the problem while editing, then return to Normal mode.
PairsTrace stop
PairsTrace show
PairsTrace export /tmp/pairs-trace.json
```

Tracing is off by default. It records calls to `expr()`/`handle()` through the
actual mappings or a composed fallback. `explain()` and `PairsInspect` queries
do not create records; keys handled entirely by completion/snippets do not
create a pairing record either. There are no diagnostic reads, snapshots or
timers on the disabled path. The trace hook does not request another parse.

The newest 100 records contain the pre-edit byte cursor, local line, filetype,
key, observed action/reason, effective delimiter policy and available syntax
classification. A ring discards older records; the view reports the count.
Each line snapshot is limited to 4096 bytes around the cursor, preserving valid
UTF-8 boundaries and marking clipping. `show` opens a readonly scratch split
without changing the source text. Stop retains records; start resumes; clear
resets records without changing the switch. Re-setup preserves tracing;
`teardown()` stops it and retains records. Recorder failures stop tracing and
appear in its status/view while normal typing continues.

Export is explicit and local. `PairsTrace export {file}` creates a new JSON file;
use `PairsTrace! export {file}` to replace an existing file. Escape paths with
spaces as for other Ex commands. Nothing is written automatically.
JSON schema 1 uses **zero-based rows and byte columns**, and the line slice starts
at `input.start_col`. The scratch view displays one-based positions.

Exported decisions describe observed behavior. Confirm the intended output
before turning an entry into a regression assertion. The snapshot is a starting
point for reproduction: surrounding lines, parser trees/scheduling, language
declarations, indentation callbacks, completion/snippets and mapping ownership
are not serialized. Clipped lines, failed context capture and callback/runtime
dependencies are marked in the records. A multiline/parser issue may need extra
context added manually.

The Lua API is separate from setup options:

```lua
local trace = require("pairs.trace")
trace.clear()
trace.start()
-- Edit, then stop; entries() returns independent copies in chronological order.
trace.stop()
local records = trace.entries()
local status = trace.status() -- active, count, capacity, dropped, optional error
-- trace.export("/tmp/pairs-trace.json") -- explicit new-file export
-- trace.export("/tmp/pairs-trace.json", true) -- explicit replacement
```

## Development

```sh
./tests/run.sh
stylua --check lua tests plugin

# Also exercise actual Python/Rust/JavaScript/TypeScript/TSX/LaTeX grammars:
./tests/install-parsers.sh /tmp/pairs-parsers
PAIRS_TEST_PARSER_ROOT=/tmp/pairs-parsers ./tests/run.sh

# Decision timing and actual mapped input batches (isolated, headless):
PAIRS_TEST_PARSER_ROOT=/tmp/pairs-parsers \
  PAIRS_BENCH_OUTPUT=/tmp/pairs-benchmark.json ./tests/bench.sh
```

Tests use actual Neovim input and cursor positions in isolated XDG directories.
They cover quotes, nesting, UTF-8 neighbors, backspace, Enter/indentation,
undo/redo, dot repeat,
configuration precedence, Python triple quotes and prefixes, JavaScript/TypeScript
templates, tagged/nested templates and interpolation, Markdown fence boundaries
and code-language injections, LaTeX math delimiters, environment declarations, command arguments and verbatim/math boundaries,
Tree-sitter literal/interpolation boundaries and
pending parses, completion/snippet-style buffer edits, macro/paste behavior,
and mapping lifecycle. CI checks the minimum
supported version and the current stable version, with pinned parser fixtures.
Parser fixtures are test-only and do not change your installed parsers. Real blink.cmp/LuaSnip
integration remains a separate manual acceptance check.

The benchmark reports decision median/P95/max in microseconds and separately
times input batches that edit buffers through the actual mappings. It also checks
the resulting text, undo/redo and dot repeat. `PAIRS_BENCH_SAMPLES` defaults to
1000; `PAIRS_BENCH_LINES` to 50000; `PAIRS_BENCH_MAPPED_SAMPLES` to 20.
Use `PAIRS_BENCH_PROFILE=1` for an additional instrumented stage breakdown.
No parser fixtures are required for the lexer and mapped-input cases.
These measurements exclude screen rendering and physical keyboard latency;
CI checks behavior without a machine-dependent timing threshold.
See [benchmark methods and measured results](docs/BENCHMARKS.md).

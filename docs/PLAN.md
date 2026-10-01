# Implementation milestones

## Initial milestone (implemented)

- Conservative quote opening, matching closer skip, and empty-pair deletion.
- Basic brackets and nesting-aware skip.
- Independent `open`, `skip`, and `delete` policies.
- Pure decision engine; Neovim context/mapping adapters.
- Global/filetype/buffer overrides; preserving existing mappings.
- Optional valid Tree-sitter context and inspectable decisions.
- Real Neovim regression tests, help, health, and local installation instructions.

Validation: the initial suite contained 108 real-input cases on Neovim 0.11.0
and 0.12.5 on macOS arm64. The local plugin is loaded by the user's Neovim
configuration in place of mini.pairs/nvim-autopairs.

## Enter milestone (implemented)

- Empty-bracket expansion, independent per-rule `newline` and `mappings.cr`.
- Language indentation using `indentexpr`/`cindent`, or shiftwidth fallback.
- Tabs, variable tab stops, nesting, and existing mapping ownership.
- Native undo/redo and complete multiline dot repeat, including counted repeat.
- Explicit blink.cmp Enter composition: accept, pairs.expr, native fallback.

The mapping returns native typed commands. A temporary isolated word on the
middle line allows Ctrl-Left to return across a newline without splitting the
insertion record; native Delete removes it. Indentation is evaluated through the
expression register and returned as typed whitespace so dot captures it. No
buffer text edits or override of the user's dot mapping are required. Language
indent callbacks have their cursor/view and v:lnum restored.

Validation: 149 regression tests pass on Neovim 0.11.0 and 0.12.5, including
actual Lua/Python indent functions, C indentation, undo/redo, dot and tabs.
The active Neovim configuration also passed startup smoke for default/minimal/
Python profiles and a real blink.cmp acceptance session: Enter priority, function
auto-brackets, LuaSnip acceptance/placeholder navigation, and Enter undo/dot.
Only a deterministic completion source was injected for this session; blink.cmp
and LuaSnip themselves were the installed plugins.

## Syntax context milestone (implemented)

- Separate Tree-sitter adapter for insertion boundaries and prefix masking.
- Python triple/prefixed strings, Lua long strings, Rust raw literals and block
  comments; no multi-character pair insertion is introduced.
- Python interpolation/format expressions and JavaScript/TypeScript template
  substitutions use code pairing. Nested strings/comments take precedence.
- Completed literals/comments cannot pollute the lexer's later bracket stack.
- Stale trees use the native time-sliced parse callback API, available on 0.11+.
  Pending parses, forced-sync debug mode and unsafe incomplete literals pass
  through. Prefix traversal is bounded to 256 nodes and skips preceding lines
  using binary search.
- CI builds pinned Python/Rust/JavaScript test grammars from generated C sources.
  These fixtures do not add runtime dependencies or change installed parsers.
- Tree-sitter context is enabled in the user's local plugin configuration.

Validation: 191 real-input cases pass on Neovim 0.11.0 and 0.12.5 with pinned
parser fixtures. The actual configuration passed 19 input cases, including
multiline/raw strings, Python/JavaScript/TypeScript interpolation, actual blink.cmp
acceptance, LuaSnip navigation, Enter and native undo/dot. All three startup
smoke profiles passed. Language-server responses and further injected-language
contexts remain separate acceptance work.

## Python triple-quote milestone (implemented)

- Separate opt-in `multi_pairs` rules with global/filetype/buffer overrides.
- Upgrade an empty short Python string only when parser boundaries prove its
  position. Support both quote styles and Python string prefixes.
- Skip the actual closing triple one quote at a time; preserve body quotes.
- Delete an adjacent empty triple pair and expand it on Enter with its middle
  and closing lines aligned with the opening line.
- Preserve independent open/skip/delete/newline policies, mapping ownership,
  native undo/redo, and dot repeat. Missing/pending parser context cannot
  synthesize a triple pair.
- Defer mapped context reads until preceding typed text has been applied,
  covering continuous word/quote and prefixed-string input.
- Reset native indentation before inserting recorded whitespace, including
  Python indent callbacks that return -1 and counted dot repeat.
- Enable both triple-quote rules in the user's local Python configuration.

Validation: 277 cumulative real-input cases pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 175 cases pass without optional fixtures. The actual
configuration passed 29 acceptance cases with installed blink.cmp and LuaSnip
plugins, plus startup smoke for default/minimal/Python profiles. LSP responses
remain separate acceptance work.

## JavaScript/TypeScript template milestone (implemented)

- Opt-in single-character backticks and multi-character `${}` rules, independent
  of each other and ordinary brace rules.
- Parser-proven template and substitution boundaries for closing-key skip,
  empty-pair deletion, and interpolation Enter expansion.
- Tagged, multiline and nested templates; literal body text and escaped dollars
  pass through. Existing interpolation closers are reused. Outer JS/TS trees
  retain delimiter ownership when a tag injects another language.
- String/comment/regex/JSX text contexts stay protected. React filetypes use
  standard parser aliases while preserving explicit language registrations.
- Native undo/redo and dot repeat, including multiline interpolation insertion.
- Pinned TypeScript and TSX parser fixtures alongside Python/Rust/JavaScript.
- Enable all four JS/TS/React filetype rules in the user's local configuration.

Validation: 506 cumulative real-input cases with all five pinned grammar
fixtures, including actual C language injection. Supported Neovim versions
0.11.0 and 0.12.5 are checked before commit; 181 cases run without fixtures.
The active configuration passed 65 input cases, including actual blink.cmp
acceptance inside template expressions, LuaSnip placeholder navigation and
multiline HTML tagged templates. Default/minimal/Python startup smoke passes.
React completion keeps blink's existing kind-resolution policy; LSP semantic
token responses remain separate acceptance work.

## Markdown fence milestone (implemented)

- Opt-in triple-backtick fence expansion on Enter at the end of a new opening
  line, preserving the language/info string and zero to three indentation spaces.
- Add the closing fence through native input commands; cursor stays on the
  middle line. Undo/redo and counted dot repeat retain the entire insertion.
- Ordinary Enter reuses existing closers and preserves existing body content.
- Parser-confirmed closing backticks skip individually, including longer closers.
- The outer Markdown tree owns delimiters independently of injected code trees.
- Inline code, HTML, indented code, longer/tilde openers and list/blockquote
  fences keep ordinary behavior. Whole-block deletion is outside this increment.
- Preserve the blink.cmp accept/Enter fallback chain and enable the rule in the
  user's local Markdown configuration.

Validation: 570 cumulative tests pass on Neovim 0.11.0 and 0.12.5; 245 tests
pass without extra parser fixtures. Markdown and C injection checks use the
bundled grammars. The user's actual configuration passes 75 input cases with
blink.cmp language completion, auto brackets and LuaSnip, plus default/minimal/
Python startup smoke. External LSP responses remain separate acceptance work.
Help tags, health checks, formatting and diff checks pass.

## Subsequent milestones

1. Collect concrete mispair examples from daily use and turn each into a
   regression case before refining heuristics.
2. Extend completion/snippet acceptance to more languages and real LSP sources,
   including auto-insert previews and semantic bracket resolution.
3. Extend Markdown fences to list/blockquote containers and longer/tilde openers,
   then add opt-in LaTeX rules. Evaluate ambiguous angle brackets with explicit
   context and priority.
4. Measure real typing latency before considering caching or incremental scans.
5. Expand beyond Insert mode only after its behavior has settled.

Every milestone should pass the cumulative regression suite before a focused
commit. No publishing/push is part of local implementation.

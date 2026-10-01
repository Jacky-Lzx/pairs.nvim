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

## Subsequent milestones

1. Collect concrete mispair examples from daily use and turn each into a
   regression case before refining heuristics.
2. Extend completion/snippet acceptance to more languages and real LSP sources,
   including auto-insert previews and semantic bracket resolution.
3. Add opt-in language rules for Python triple quotes, Markdown fences, LaTeX,
   and ambiguous angle brackets, with an explicit context/priority contract.
4. Measure real typing latency before considering caching or incremental scans.
5. Expand beyond Insert mode only after its behavior has settled.

Every milestone should pass the cumulative regression suite before a focused
commit. No publishing/push is part of local implementation.

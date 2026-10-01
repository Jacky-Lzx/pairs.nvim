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

## Markdown container milestone (implemented)

- Recognize list/blockquote ancestors in the outer Markdown tree, including
  nested lists, nested quotes and mixed containers.
- Convert opening list markers to continuation indentation and preserve quote
  markers on body/closing lines. Normalize container tabs at Markdown tab stops.
- Reuse existing body/closers with a single Enter that supplies the continuation
  prefix; do not create another closing fence.
- Keep native comment leaders and indentexpr from duplicating generated prefixes.
- Recognize closers before subsequent paragraphs and validate their indentation
  relative to the parsed container continuation.
- Preserve native undo/redo/dot, rule flags, unavailable/pending parser fallback,
  and injected code boundaries. Body Enter and unsupported delimiters stay native.
- The existing local Markdown configuration enables this extension automatically.

Validation: 647 cumulative tests pass on Neovim 0.11.0 and 0.12.5; 322 pass
without extra parser fixtures. Real configuration passes 103 input cases,
including nested container undo/redo/dot, existing closer reuse and blink.cmp
language completion. The configured punctuation undo breaks remain intact.
Default/minimal/Python startup smoke, help tags, health checks, formatting and
diff checks pass. External LSP responses remain separate acceptance work.

## Markdown fence family milestone (implemented)

- Extend the existing backtick family to any opening length >= 3 and add an
  independent opt-in tilde family through multi_pairs['~~~'].
- Generate closers with the opening character and exact length. Reuse/skip
  only parser-confirmed closers of the same character and sufficient length.
- Preserve shorter/different-character lines as content. Apply the backtick
  restriction to backtick info strings while allowing backticks in tilde info.
- Retain container prefixes, injected-code boundaries, native undo/redo/dot,
  disabled-family isolation and original-key fallback without current context.
- Enable both families in the user's local Markdown configuration.

Validation: 795 cumulative tests pass on Neovim 0.11.0 and 0.12.5; 470 pass
without extra parser fixtures. The actual
configuration passes 139 input cases with blink.cmp confirmation, language
completion, LuaSnip, native undo/redo/dot, and existing closer reuse.
Default/minimal/Python startup smoke, help tags, health, formatting and diff
checks pass. External LSP responses remain separate acceptance work.

## LaTeX display-dollar milestone (implemented)

- Opt-in `multi_pairs['$$']` for tex/plaintex using the outer LaTeX grammar.
- Keep the first dollar literal; upgrade the second only at a standalone display
  line. Inline single-dollar and backslash math delimiters remain outside scope.
- Skip parser-confirmed closing dollars individually; delete adjacent empty
  displays and expand them on Enter with the opening line's indentation.
- Protect comments, math, raw environments and inline verb/code commands.
  Recover incomplete known text environments, including full documents, with
  bounded direct-child inspection; unknown/error contexts preserve input.
- Retain time-sliced parsing, action flags, overrides, mapping ownership and
  native undo/redo/dot. Standard tex/plaintex aliases respect custom registrations.
- Build a pinned LaTeX grammar from its official generated-C npm release and
  enable both filetype rules in the user's local configuration.

Validation: 876 cumulative tests pass on Neovim 0.11.0 and 0.12.5; 475 pass
without optional parser fixtures. The actual configuration passes 152 input
cases with installed VimTeX, blink.cmp confirmation, LuaSnip placeholders and
native undo/redo/dot. Default/minimal/Python startup smoke, help tags, health,
formatting and diff checks pass. External LSP responses remain separate
acceptance work.

## LaTeX backslash-math milestone (implemented)

- Independent opt-in `multi_pairs['\\(']` and `multi_pairs['\\[']`, with
  implicit matching closers. Preserve ordinary brackets and control sequences.
- Open after an unescaped backslash in parser-confirmed text; protect existing
  math, comments, verbatim/code, unknown environments and unsafe recovery nodes.
- Generalize outer-tree math metadata to complete matching inline/display pairs.
  Skip both closing characters individually, including the backslash, so typed
  closers reuse their existing control symbol.
- Delete adjacent empty math pairs; expand empty display brackets on Enter with
  base indentation. Inline newline remains native unless explicitly enabled.
- Register the deferred backslash mapping only when either rule is configured;
  preserve existing mapping owners and expose composition through expr().
- Retain action flags, parser/scan-limit fallback, native undo/redo/dot, and
  enable both rules in the user's tex/plaintex configuration.

Validation: 987 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5;
482 pass without optional parser fixtures. The actual configuration passes
181 input cases with installed VimTeX, blink.cmp completion, LuaSnip placeholders,
the existing math shortcut and native undo/redo/dot. Default/minimal/Python
startup smoke, help tags, executable setup examples, health, formatting and
diff checks pass. External LSP responses remain separate acceptance work.

## LaTeX environment classification milestone (implemented)

- Declare exact environment names through `tex_environments`: text/math/literal
  or false, with default/global/filetype/live-buffer precedence.
- Move built-in declarations into metadata; validate names and mode values before
  installing mappings. Built-in math/raw protection cannot be weakened.
- Text declarations allow existing opt-in math rules. Math declarations prevent
  nesting while retaining ordinary brackets. Literal declarations preserve all
  pairing keys; outer restrictive scopes retain priority over inner text.
- Recover complete begin headers without an end, including blank lines at EOF.
  Track matching ends across parser recovery/raw bodies and ignore completed
  siblings. Prefix traversal is bounded and excludes future syntax children.
- Preserve parser-availability fallback, native input commands, VimTeX indentation,
  completion/snippets and undo/redo/dot. Enable abstract/theorem/proof as text in
  the user's local configuration without inventing custom math/code names.

Validation: 1098 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 496 pass without fixtures. The actual local
configuration passes 211 input cases with real blink.cmp/LuaSnip and VimTeX,
including declared text environments, raw recovery, snippets and undo/dot.
Default/minimal/Python startup profiles, executable README/help examples,
help tags, health, formatting and diff checks pass. External LSP responses
remain separate acceptance work.

## LaTeX command argument milestone (implemented)

- Recognize heading/formatting text arguments, including optional heading titles
  and starred heading forms. Allow configured inline math and normal brackets;
  display openings inside command arguments remain native.
- Protect URL/path payloads, distinguish href address from display text, and
  retain structural outer-delimiter skip/delete according to existing rules.
- Recover unfinished/nested/multiline parameters using current syntax anchors
  and a prefix of at most 32 lines/4096 bytes. Check byte budget before reads,
  preserve unsafe/missing/pending contexts and do not force synchronous parsing.
- Mask completed raw payloads in the current line so URI quotes/percent escapes
  cannot poison following code; preserve real comments and outer restrictions.
- Preserve VimTeX, completion/snippets and undo/redo/dot without new user options.

Validation: 1259 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 497 pass without fixtures. The actual local
configuration passes 244 input cases with real blink.cmp/LuaSnip and VimTeX,
including complete continuous commands, argument formulas and snippet jumps.
Default/minimal/Python startup profiles, executable README/help examples,
help tags, health, formatting and diff checks pass. All 172 tracked local
configuration files retain their original bytes. External LSP responses remain
separate acceptance work.

## Subsequent milestones

1. Collect concrete mispair examples from daily use and turn each into a
   regression case before refining heuristics.
2. Extend completion/snippet acceptance to more languages and real LSP sources,
   including auto-insert previews and semantic bracket resolution.
3. Extend command profiles only for concrete editing examples.
   Evaluate angle brackets with explicit context and priority.
4. Measure real typing latency before considering caching or incremental scans.
5. Expand beyond Insert mode only after its behavior has settled.

Every milestone should pass the cumulative regression suite before a focused
commit. No publishing/push is part of local implementation.

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

## Input benchmark and measured optimization milestone (implemented)

- Add an isolated, repeatable headless benchmark for prepared decision timing
  and separate actual mapped input batches. Record median/P95/max, Lua heap
  growth, environment and source fingerprints; optionally instrument stages.
- Cover ordinary delimiters, live buffer overrides, long lines, scan limits,
  large files, current/pending parser context and the first decision after a
  real edit. Verify mapped text, undo/redo and dot repeat; CI gates behavior
  without machine-dependent timing thresholds.
- Reuse setup-validated single/multi rule metadata. Keep buffer overrides live
  and validated, public resolver results independent, and predicate evaluation
  order unchanged. Do not cache text or parser state.
- Scan empty-pair deletion/Enter prefixes once while retaining the quote state
  before the final opener and the full-prefix comment/error/scan-limit guards.

Three matched runs on Neovim 0.12.5/Apple M5 Pro show quote decision medians
5.79 -> 1.83 us and 2000-byte-prefix deletion 44.83 -> 21.21 us. The real first
decision after editing a 50000-line Python buffer remains about 3 ms. These
headless measurements exclude rendering and physical keyboard latency.
See [benchmark methods and results](BENCHMARKS.md).

Validation: 1276 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 514 pass without fixtures. Benchmark smoke runs
pass on the minimum version, with CI parameters, and without parser fixtures.
The actual local configuration passes 244 input cases with real blink.cmp,
LuaSnip and VimTeX; external LSP startup is stubbed. Default/minimal/Python
startup profiles, help tags, executable README/help examples, health, formatting
and diff checks pass. All 172 tracked configuration files retain their original
bytes. Physical keyboard-to-screen latency and real LSP responses remain
separate acceptance work.

## Actual-key trace and local reproduction export milestone (implemented)

- Add opt-in PairsTrace start/stop/show/clear/export commands and a separate Lua
  API. Record only expr()/handle() decisions; explain/inspection stays query-only.
- Retain the newest 100 chronological decisions with pre-edit input/cursor,
  action/reason, syntax classification and copied effective delimiter policy.
  Limit local text to 4096 bytes on valid UTF-8 boundaries and mark clipping.
- Keep the disabled path free of diagnostic reads/copies/timers. Reuse the
  existing context without a second parser request. Preserve native mapped
  behavior, undo/redo/dot, completion and snippets; stop recording on hook errors.
- Show a readonly scratch split and explicitly export JSON schema 1 with byte
  positions, bounded input, options and reproduction limitations. Refuse existing
  destinations without explicit replacement; remove failed new-file exports.
- Export observations rather than expected assertions. Confirm the intended
  output before writing a regression; surrounding text, parser state and external
  callbacks/integrations must be supplied when needed.

Validation: 1305 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 541 pass without fixtures. The 29 added guards
cover capture timing, ring eviction, immutable policies, UTF-8 clipping,
recorder/write failures, explicit overwrite, parser pending state, command
completion, readonly views and local replay of an exported lexer case.
The actual local configuration passes 244 existing input cases with tracing
enabled after the first lazy-load case, including real blink.cmp and LuaSnip,
plus ring/view/export acceptance. External LSP startup remains stubbed.
Default/minimal/Python startup, current/minimum-version benchmarks, executable
trace README/help examples, help tags, health, formatting and diff checks pass.
All 172 tracked configuration files retain their original bytes.

## Empty-bracket space padding milestone (implemented)

- Add opt-in space policies for (), [] and {} with validated global/filetype/
  buffer overrides. Default rules leave Space unmapped. Preserve existing Space
  owners and support composition with expr('<Space>') or a literal space.
- Insert one space per side in an adjacent empty pair. For exactly symmetric
  single-space padding, BS removes only the spaces and CR trims them before
  existing indentation. Respect independent delete/newline flags and retain
  typed-key undo/redo/dot behavior.
- Reuse the existing bounded lexer snapshot; no extra prefix scan, parser call
  or retained buffer state. Strings/comments, unsafe/pending syntax, escaped
  openers, nonempty/extra whitespace and structural interpolation boundaries
  retain ordinary input. Closer skipping retains its adjacent-closer rule.
- Copy the validated space policy and trim_space decision into trace exports;
  inspect queries accept <Space>. No local configuration option is changed.

Validation: 1358 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 585 pass without fixtures. Added cases cover
exact whitespace, disabled policies, native fallbacks, single-scan limits,
mapping ownership/composition, tabs/indentexpr, undo/redo/dot, trace export and
parser/literal/interpolation boundaries. The actual local configuration passes
250 input cases, including six new padding cases with completion-owned Enter,
real blink.cmp/LuaSnip confirmation/navigation and native undo/redo/dot. Padding
is enabled only in the acceptance process and the original options are restored.
External LSP startup remains stubbed. All 172 tracked configuration files retain
their original bytes.
Current/minimum-version and parser-free benchmark runs also pass the added
padding decision and mapped-input cases. Default/minimal/Python startup,
executable README/help examples, help tags, health, formatting and diff checks
pass.

## Cross-space bracket exit milestone (implemented)

- Add a default-off skip_space policy for (), [] and {}. Require skip=true,
  a matching nesting stack and exactly one ASCII space immediately before the
  right delimiter. The option is independent of space insertion and also works
  with manual padding, without installing any additional mapping.
- Reuse the single bounded prefix scan and existing native two-position movement.
  Preserve text, undo/redo/dot, mapping ownership and language-specific structural
  interpolation rules. Strings/comments, escaped/unmatched prefixes, multiple
  spaces/tabs, intervening text and pending syntax retain ordinary input.
- Validate global/filetype/live buffer policy, preserve setup after invalid
  options, and export skip_space plus the movement in actual-key traces.
  Extend mapped and decision benchmark coverage without timing thresholds.

Validation: 1399 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 617 pass without fixtures. The 41 added cases cover
all standard shapes, nesting, Unicode, native fallbacks, policy precedence,
single-scan limits, mapping ownership/composition, undo/redo/dot, trace export,
parser literals/interpolation boundaries and pending parse dispatch.
The actual local configuration passes 257 input cases with real blink.cmp and
LuaSnip, including completion confirmation followed by padded closer exit and
snippet navigation. Options are changed only inside the acceptance process;
all 172 tracked configuration files retain their original bytes. External LSP
startup remains stubbed.
Stable/minimum-version benchmarks pass 23 decisions and seven mapped scenarios;
parser-free smoke passes 14 decisions and the same seven mapped scenarios.
Default/minimal/Python startup, executable README/help examples on both versions,
help tags, health, formatting and diff checks also pass.

## Same-line identifier fast wrap milestone (implemented)

- Add fast_wrap() as a composable expression API, plus logical <FastWrap> for
  expr/explain/inspection/trace. No physical shortcut is installed by default;
  mappings.fast_wrap can opt into a validated single non-text key. Preserve
  existing global/buffer owners, queued-input flushing and teardown ownership.
- Move an adjacent empty standard bracket's closer around one immediately
  following ASCII identifier. Preserve suffix text and leave the cursor after
  the closer using native Del, protected Right movements and insertion.
  Retain undo/redo/dot; dot replays the recorded movement length.
- Keep calls/member access/indexing, Unicode identifiers, padding, intervening
  whitespace, strings/comments, unsafe/pending syntax and structural
  interpolation boundaries outside target support. Share the existing bounded
  prefix scan and max_scan_bytes budget with the forward identifier, plus one
  boundary-lookahead byte. No extra parser request, text cache or buffer edit.
- Add independent wrap policies for standard brackets and validated live
  overrides. Legacy custom closer overrides disable inherited wrapping instead
  of invalidating existing configuration. Trace exports retain policy/target
  length and support confirmed local API replay.

Validation: 1451 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 661 pass without fixtures. The 52 added cases cover
standard shapes, suffix/cursor positions, conservative token boundaries, native
undo/redo/dot, API fallback, single-scan/forward limits, legacy policy overrides,
shortcut validation/ownership/composition, export replay and parser protection.
The actual local configuration passes 265 input cases with real blink.cmp and
LuaSnip, including fast wrap in an active snippet placeholder, subsequent
navigation and nested undo/redo/dot. Options are changed only in the acceptance
process and then restored; all 172 tracked configuration files retain their
original bytes. External LSP startup remains stubbed.
Stable/minimum-version benchmark smoke passes 24 decisions and eight mapped
cases; parser-free smoke passes 15 decisions and the same eight mapped cases.
Default/minimal/Python startup, executable README/help examples on both versions,
help tags, health, formatting and diff checks pass.

## Fast wrap after a typed opening bracket milestone (implemented)

- Extend the existing fast_wrap API/shortcut to an identifier immediately after
  a standard opener. Insert its missing closer or reuse a matching closer
  immediately after the identifier. Preserve adjacent-empty-pair movement and
  the existing wrap policy, syntax protection, single bounded prefix scan and
  identifier/boundary budget. No new mapping or option is required.
- Render each case with native protected movement and only the necessary
  deletion/insertion. Pure reuse preserves both changedtick and undo history.
  Retain typed-opener undo/redo/dot and suffix text; do not infer the historical
  ownership of a closer or repair other unclosed outer brackets.
- Export explicit remove_close/insert_close flags, including false values,
  together with mode-specific reasons. Confirm local export replay in all three
  modes. Keep complex/Unicode targets, whitespace before a target and unsafe
  interpolation/parser contexts outside support.
- Prepare the completed-template parser-ready regression fixture before its
  assertion. Pending-parser tests remain separate and retain asynchronous
  native-input behavior; runtime parsing is unchanged.

Validation: 1497 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 697 pass without fixtures. The 46 new cases cover
standard shapes, natural typed-opener workflows, nesting, insertion/reuse
policies, pure-movement invariants, undo/redo/dot, bounded scans, native fallback,
API composition, trace flag/export replay and syntax/pending protection.
The actual local configuration passes 274 input cases with real blink.cmp and
LuaSnip, including opener insertion and pure reuse in active snippet workflows,
subsequent navigation and undo/redo/dot. Options are changed only during
acceptance and then restored; all 172 tracked configuration files retain their
original bytes. External LSP startup remains stubbed.
Stable/minimum-version benchmarks pass 26 decisions and ten mapped cases;
parser-free smoke passes 17 decisions and the same ten mapped cases. Startup
profiles, executable README/help examples on both versions, help tags, health,
formatting and diff checks pass.

## Same-line member chain fast wrap milestone (implemented)

- Extend all three fast-wrap modes to identifier(.identifier)* targets, including
  self.name and config.options.enabled. Keep the same API, shortcuts, wrap policy
  and native-key renderer. Existing identifier decision reasons and trace schema
  remain compatible; movement length now covers the full contiguous chain.
- Match each ASCII member in the bounded forward window. Every dot requires a
  member; reject malformed/Unicode chains, calls, indexing and adjoining operators
  without wrapping a partial target. The complete prefix, adjacent closer and
  all members share max_scan_bytes, with one byte of boundary lookahead.
- Preserve suffix text, immediate-closer reuse, pure-movement invariants,
  undo/redo/dot, live policies, single prefix scan and syntax/pending guards.
  Add mapped benchmark cases for all three modes and a long-chain decision.

Validation: 1557 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 749 pass without fixtures. The 60 new cases cover
all standard pairs/modes, typed-opener and adjacent-pair undo/redo/dot, long
chains and budget cuts, unsupported targets, suffixes, live policies, edits,
trace export/replay, multiline strings/comments, interpolation and pending syntax.
The actual local configuration passes 295 input cases with real blink.cmp and
LuaSnip, including member insertion/reuse in active snippet placeholders and
subsequent navigation. All 172 tracked configuration files retain their original
bytes; external LSP startup remains stubbed. Default/minimal/Python startup,
executable README/help examples on both versions, help tags and health pass.

Stable/minimum-version benchmarks pass 30 decisions and 13 mapped cases;
parser-free smoke passes 21 decisions and the same 13 mapped cases, including
text and undo/redo/dot assertions. Formatting and diff checks pass.

## Same-line complete call fast wrap milestone (implemented)

- Extend each fast-wrap mode to an ASCII identifier/member chain with one
  immediately adjoining (...) call. Prove balanced standard brackets and
  ordinary single/double-quoted strings with escape parity inside the bounded
  forward window. Preserve suffixes, immediate closer reuse, live policies and
  existing identifier decision reasons/trace schema.
- Keep one prefix lexer scan. Count the complete prefix, adjacent closer, callee,
  arguments and call closer against max_scan_bytes, with one boundary byte.
  Incomplete/mismatched calls and unsupported suffixes/literals remain untouched;
  do not wrap a partial call, interpret general expressions or infer historical
  ownership of a closer. Current text may complete an apparently missing call
  closer, just as bracket reuse follows current nesting.
- Reject argument comments, backticks, triple/long/raw/interpolated literals and
  JS/TS/Ruby/Swift slash expressions conservatively. This is structural boundary
  proof rather than a full language grammar; regex/division distinction and
  chaining after calls remain outside support.
- Retain pure native-key rendering, undo/redo/dot and reuse invariants. Convert
  call text from byte lengths to native character steps, including composing
  characters. Account for tab cells under virtualedit=all/insert with effective
  tabstop/vartabstop and the post-deletion prefix. Pass the captured context to
  the renderer; introduce no retained text, parser requests, mappings or options.
  Trace move stays a byte length; internal target text is omitted from exported
  decisions since the input snapshot already captures it.

Validation: 1639 cumulative real-input tests pass on Neovim 0.11.0 and 0.12.5
with pinned parser fixtures; 821 pass without fixtures. The 82 new cases cover
all three pairs/modes, nested args, quotes/escapes, Unicode/composing characters,
virtual tabs, disabled structural rules, malformed/complex targets, budget cuts,
undo/redo/dot, pure reuse, fresh scans, trace replay and syntax/pending guards.
The actual local configuration passes 317 input cases with real blink.cmp and
LuaSnip, including call insertion/reuse inside active placeholders, subsequent
navigation and Unicode arguments. All 172 tracked configuration files retain
their original bytes; external LSP startup remains stubbed. Default/minimal/Python
startup, executable README/help examples on both versions, help tags and health
pass. Stable/minimum-version benchmarks pass 35 decisions and 16 mapped cases;
parser-free smoke passes 26 decisions and the same 16 mapped cases, with text
and undo/redo/dot assertions. Formatting and diff checks pass.

## Subsequent milestones

1. Collect concrete mispair examples from daily use and turn each into a
   regression case before refining heuristics.
2. Extend completion/snippet acceptance to more languages and real LSP sources,
   including auto-insert previews and semantic bracket resolution.
3. Improve diagnostics for concrete mispair reports; consider angle brackets
   only with explicit context and priority. Further LaTeX features are paused.
4. Measure latency in the real interactive client before considering parser
   scheduling changes or incremental text scans.
5. Expand beyond Insert mode only after its behavior has settled.

Every milestone should pass the cumulative regression suite before a focused
commit. No publishing/push is part of local implementation.

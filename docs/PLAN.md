# Implementation milestones

## Initial milestone (implemented)

- Conservative quote opening, matching closer skip, and empty-pair deletion.
- Basic brackets and nesting-aware skip.
- Independent `open`, `skip`, and `delete` policies.
- Pure decision engine; Neovim context/mapping adapters.
- Global/filetype/buffer overrides; preserving existing mappings.
- Optional valid Tree-sitter context and inspectable decisions.
- Real Neovim regression tests, help, health, and local installation instructions.

Validation: 108 regression tests passed on Neovim 0.11.0 and 0.12.5 on macOS
arm64. Help lookup, health output, and StyLua formatting passed. Completion and
snippet tests exercise buffer-edit contracts; actual blink.cmp/LuaSnip sessions
have not been verified. The user's active Neovim configuration is not changed.

## Subsequent milestones

1. Collect concrete mispair examples from daily use and turn each into a
   regression case before refining heuristics.
2. Add Enter expansion with language indentation. It must preserve both undo
   grouping and the complete multiline insertion under `.`. Do not ship the
   direct buffer-edit prototype: it preserved undo but omitted those edits
   from dot replay. `<CR><C-o>O` also replayed only the last insertion segment.
3. Verify actual blink.cmp and LuaSnip behavior in an isolated real configuration,
   including auto-brackets, snippets, placeholder navigation, and load order.
4. Add opt-in language rules for Python triple quotes, Markdown fences, LaTeX,
   and ambiguous angle brackets, with an explicit context/priority contract.
5. Measure real typing latency before considering caching or incremental scans.
6. Expand beyond Insert mode only after its behavior has settled.

Every milestone should pass the cumulative regression suite before a focused
commit. No publishing/push is part of local implementation.

# Input benchmark

Run `./tests/bench.sh` from the checkout. It uses isolated XDG directories and
does not modify installed Neovim state. Optional pinned grammars enable the
parser scenarios:

```sh
./tests/install-parsers.sh /tmp/pairs-parsers
PAIRS_TEST_PARSER_ROOT=/tmp/pairs-parsers \
  PAIRS_BENCH_SAMPLES=3000 PAIRS_BENCH_LINES=50000 \
  PAIRS_BENCH_MAPPED_SAMPLES=20 \
  PAIRS_BENCH_OUTPUT=/tmp/pairs-benchmark.json ./tests/bench.sh
```

Set `NVIM` to another executable to check a supported version. Defaults are
1000 decision samples (minimum 100), 50000 file lines (minimum 1000), and 20
mapped batch samples (minimum 5). JSON schema 1 records Neovim/CPU/OS versions,
parameters, Git revision/dirty state, runtime source and benchmark SHA-256,
actions/reasons and measured statistics. An archived checkout can label its
revision with `PAIRS_BENCH_REVISION`; unavailable Git state is recorded as null.

## What is measured

Decision timing wraps `pairs.explain(key, { assume_insert = true })` in prepared
buffers. It includes capture, configuration, syntax/lexer context and engine
decision, excluding fixture creation and result validation. Ordinary scenarios
warm up with 100 calls; normal GC remains enabled in the timed samples. Median
and P95 use sorted samples at ceil(N * 0.5) and ceil(N * 0.95); max and mean are
also reported. Expected actions are checked outside each timer; context errors
fail the run.

Lua heap growth is measured separately across 100 calls with GC paused, without
the result-checking/reporting harness. It includes the small caller options
table. It estimates Lua allocations, not retained memory, leaks or C allocations.
`PAIRS_BENCH_PROFILE=1` adds a separate instrumented run with inclusive times
and call counts for configuration, capture, lexer and syntax stages. Nested
inclusive times cannot be added; instrumentation is absent from latency samples.

Parser-ready cases prepare the tree before timing. The pending-dispatch case
stubs `parser.parse` to return nil and verifies range/callback use: it measures
dispatch overhead, not parsing speed. The real after-edit case invalidates the
middle of a large Python buffer before every timed decision. It includes
Neovim's first parse time slice, then waits for the tree to settle outside the
timer before the next edit. It uses 50 samples without warmup and permits only
pairing or a `syntax_pending` pass. Production code never forces a synchronous
parse; synchronous fixture preparation is outside the timers.

Mapped timing feeds actual keys through the installed mappings, including text
edits. It runs three warmup batches, verifies every resulting buffer, and checks
undo/redo/dot on the first measured batch. Native explicit delimiters provide
an editing baseline. Batch medians/P95 are not per-key statistics and should not
be divided into a claimed per-key P95.

The current benchmark also checks opt-in empty-space, padded Backspace/Enter
and cross-space closer decisions, plus mapped padding/deletion/Enter/closer
batches. Other scenarios keep their default rules; padding and skip_space are
not implicitly enabled for the ordinary baseline.
Fast wrap checks adjacent-closer movement, missing-closer insertion and existing
closer reuse in both bounded decisions and mapped cases, including text and
undo/redo/dot checks. These three modes also exercise dotted member chains;
a long chain checks bounded forward scanning. Its shortcut is enabled only in
those mapped cases.

Neither metric measures physical keyboard-to-screen latency: these are headless
runs without UI rendering, real completion/LSP responses or OS event delivery.
CI uses small fixtures and asserts behavior without timing thresholds.

## Measured comparison: 2026-10-01

Baseline: `c58fb978cab23aef254e585c6e8884ba4faae45d`. Optimized runtime:
`3d6f928`, with setup metadata reuse and single-scan empty-pair handling.
Both ran the identical benchmark on Apple M5 Pro, macOS arm64, Neovim 0.12.5
with pinned parser fixtures. Three independent alternating before/after runs
used 3000 decision samples, 50000 lines, 20 mapped samples, plus profiling.
Each table cell is the median of the three runs' corresponding statistic,
not a percentile of pooled samples. Run sequentially with a quiet machine;
absolute timings and GC tails vary between machines and runs.

| Decision (microseconds) | Before median | After median | Before P95 | After P95 |
| --- | ---: | ---: | ---: | ---: |
| Quote opening | 5.79 | 1.83 | 26.58 | 9.00 |
| Bracket opening | 5.79 | 1.83 | 23.08 | 9.21 |
| Matching closer skip | 5.79 | 1.88 | 23.04 | 9.12 |
| Empty-pair Backspace | 5.83 | 1.88 | 23.17 | 9.00 |
| Empty-pair Enter | 5.75 | 1.92 | 22.08 | 9.21 |
| Live buffer override | 6.00 | 4.21 | 22.21 | 17.71 |
| 2000-byte prefix bracket | 25.83 | 21.67 | 42.83 | 29.17 |
| 2000-byte prefix Backspace | 44.83 | 21.21 | 66.50 | 28.88 |
| Over scan budget (8192 bytes) | 6.08 | 2.21 | 24.42 | 7.92 |
| 50000-line buffer, lexer | 5.71 | 1.83 | 19.88 | 8.38 |
| Python, current tree | 8.79 | 4.58 | 54.79 | 31.62 |
| Python multiline string | 8.67 | 4.71 | 45.00 | 31.04 |
| Rust block comment | 7.75 | 3.54 | 45.21 | 23.71 |
| JavaScript template text | 8.25 | 4.46 | 37.25 | 29.58 |
| JavaScript interpolation | 9.62 | 5.50 | 56.46 | 33.92 |
| 50000-line Python, current tree | 12.79 | 8.54 | 62.75 | 38.54 |
| 50000-line Python, string | 9.12 | 5.04 | 43.38 | 32.12 |
| Pending dispatch stub | 6.96 | 2.83 | 32.58 | 14.75 |
| 50000-line Python, first decision after edit | 3054.08 | 3039.21 | 3080.25 | 3071.71 |

| Lua heap growth per decision (bytes) | Before | After |
| --- | ---: | ---: |
| Quote opening | 10067 | 4018 |
| Live buffer override | 10313 | 8169 |
| 2000-byte prefix Backspace | 10369 | 4137 |
| 50000-line Python, current tree | 15086 | 9030 |

| Input batch (milliseconds) | Before median | After median | Before P95 | After P95 |
| --- | ---: | ---: | ---: | ---: |
| Native balanced text, 400 typed characters | 10.580 | 10.272 | 11.169 | 10.673 |
| Mapped balanced text, 300 owned delimiter keys | 20.057 | 17.541 | 20.853 | 18.618 |
| Mapped opening/deletion, 400 owned keys and final `z` | 21.132 | 18.681 | 22.209 | 19.772 |
| Mapped `{<CR>x`, 2 owned keys | 0.359 | 0.346 | 0.383 | 0.399 |

Quote decision medians fell about 68%, long-prefix deletion about 53%, and quote
Lua heap growth about 60%. The mapped balanced/deletion batch medians fell about
12-13%; the short Enter batch does not demonstrate consistent improvement.
Real after-edit parsing remains about 3 ms and needs separate interactive
investigation.
No buffer-text/parser cache or LaTeX feature was added.

Comparison fingerprints (runtime hashes encode sorted path/NUL/content entries
as a JSON array before SHA-256, including on Neovim 0.11):

```text
before runtime 14dd324d35360845b35aefa12c7ecc894b8a24de253cd32f1ee51cad7345946d
after runtime  65da6a633fe794378749784123d1bded236a9c211a71401643f2348ef1f95c13
benchmark      88a4bdf9464bbe4088b6fa441634b40c47c7485277afbb342948c9246bfa2dfd
```

To reproduce the table above, use `tests/bench.lua` and `tests/bench.sh` from
`3d6f928` in both checkouts. Later benchmarks add padding cases requiring that
feature and have a different benchmark fingerprint.

To repeat a revision comparison, archive each runtime revision into its own
temporary directory, copy the same `tests/bench.lua` and `tests/bench.sh` into
both, and run them sequentially with identical environment values. Compare
runtime fingerprints and keep the benchmark fingerprint identical. Keep raw
JSON outside the repository; machine-specific timings are observations, not
portable performance guarantees.

# Reativa benchmarks

A keyed-list benchmark that runs the same application in **Reativa (Melange)**,
**Reativa (js_of_ocaml)**, **xote** and **SolidJS**, and measures operation
latency, startup time, memory, payload size and DOM calls per operation.

The workload is the standard [js-framework-benchmark][jfb] table: rows that get
created, replaced, updated, selected, swapped, appended to and cleared. Every
implementation renders the same DOM, uses the same stylesheet and the same
deterministic data (`shared/data.js`; the OCaml app uses a port of it,
`apps/reativa/bench_data.ml`, that produces identical labels on every
backend), so the only thing that varies is the library doing the work.

The driver, DOM-op counter and report come from xote's benchmark suite, so the
numbers are comparable with xote's own `benchmarks/results/RESULTS.md`.

## Apps

| App | Source | Built by |
| --- | --- | --- |
| `reativa` | `apps/reativa/bench_app.ml` | dune (Melange, `@benchmarks/apps/reativa/bench`), then Vite |
| `reativa-jsoo` | the same file, via `apps/reativa/jsoo/` | dune (js_of_ocaml, release profile), then Vite's minifier |
| `xote` | `apps/xote/BenchApp.res` | ReScript against `xote` from npm, then Vite |
| `solid` | `apps/solid/main.jsx` | Vite with `vite-plugin-solid` |

The Reativa app uses the plain `View` API (no mlx), so it compiles on both
backends from one file.

## Running it

```bash
cd benchmarks
npm install
node build.mjs           # builds every app into dist/ (runs dune for the Reativa apps)
node driver.mjs          # timings, startup, memory and payload; writes results/
node dom-ops.mjs         # DOM calls per operation
```

`build.mjs --apps reativa-jsoo,solid` builds a subset. `driver.mjs` takes
`--iterations N`, `--warmup N`, `--apps a,b`, `--only id,id`, `--out DIR` and
`--headed`; see the header of `driver.mjs`.

The driver prefers `BENCH_CHROME_PATH`, then a preinstalled
`/opt/pw-browsers/chromium`, and otherwise the browser Playwright installed
(`npx playwright install chromium`), which is how CI runs it.

## Comparing two builds

CI runs the suite on pull requests labelled **`benchmark`**
(`.github/workflows/benchmark.yml`) and posts a base-vs-PR comment for each
backend, rendered by `scripts/benchmark-report.mjs`. Adding the label to an
open PR starts a run. Both builds use the PR's benchmark app, so only the
library differs, and all apps run interleaved in one browser: position in the
schedule otherwise costs more than most real changes.

Locally, build the base library's apps from another checkout under a new name
and run them side by side:

```bash
node build.mjs --apps reativa-jsoo --root ../../reativa-main --as reativa-jsoo-base
node driver.mjs --apps reativa-jsoo,reativa-jsoo-base --out ci-results
node dom-ops.mjs --apps reativa-jsoo,reativa-jsoo-base --json ci-results/dom-ops.json
node ../scripts/benchmark-report.mjs --results ci-results/results.json \
  --dom-ops ci-results/dom-ops.json --pairs "js_of_ocaml=reativa-jsoo:reativa-jsoo-base"
```

The full cross-library run can also be started by hand from the **Benchmark**
workflow (**Actions → Benchmark → Run workflow**); it uploads `results/` as an
artifact.

[jfb]: https://github.com/krausest/js-framework-benchmark

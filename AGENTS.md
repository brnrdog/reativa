# AGENTS.md

The reference for AI coding agents and human contributors working on this
repository: architecture, the reactivity and ownership model, the renderer,
the mlx ppx, testing, and the pitfalls that have bitten before. `CLAUDE.md`
only points here; keep this file the single source of truth.

## Project overview

Reativa is a fine-grained reactive UI library for OCaml and ReasonML. State
lives in signals; views are real DOM nodes, mounted once and updated in place
by effects. There is no virtual DOM. The same code compiles to JavaScript with
**Melange** (default) or **js_of_ocaml**; the browser FFI is the only
backend-specific code.

It follows [xote](https://github.com/brnrdog/xote) (ReScript) closely; see
`docs/plans/xote-catch-up.md` for what was ported and why.

## Commands

| Command | What it does |
| --- | --- |
| `opam install . --deps-only --with-test` | install OCaml dependencies |
| `npm install` | install JS dev dependencies (jsdom, vite, semantic-release) |
| `opam exec -- dune build` | build everything (both backends' code, demos, website, benchmarks app) |
| `opam exec -- dune test` | native tests: signals, router, ppx rewrite |
| `npm run test:dom` | DOM suites under jsdom: `test/dom` on Melange and js_of_ocaml, and `test/dom_mlx` (written in mlx) on both |
| `npm run inspect:test` | reativa-inspect CLI and MCP server against a fixture app |
| `scripts/check-api.sh` | compare the public API with `test/api/reativa.api` (`--update` to accept a change) |
| `node scripts/generate-mlx-props.mjs` | regenerate the element props (`--check` in CI) |
| `npm --prefix benchmarks install && node benchmarks/build.mjs && node benchmarks/driver.mjs` | keyed-list benchmark (see `benchmarks/README.md`) |
| `npm run docs:dev` / `docs:build` | the documentation site |
| `node scripts/generate-docs-index.mjs` | regenerate `website/src/docs_index.ml` from `website/docs.pages.mjs` (`--check` in CI) |
| `node scripts/smoke-site.mjs` | visit every route of the compiled site under jsdom (after `dune build @melange`) |

js_of_ocaml targets are gated: set `REATIVA_JSOO=enabled` (as the npm scripts
do) to build them.

## Layout

```
src/                  the library (one dune library, wrapped as Reativa)
  signals/            reactive core: Core (graph), Scheduler, Signal_core, Computed,
                      Effect_core, Owner, Trace (devtools hooks); public faces Signal, Effect
  view.ml / view.mli  the renderer
  router*.ml          routing (Router_match is pure and natively tested)
  context.ml, resource.ml, devtools.ml, suspense_scope.ml
  dom.mli, history.mli, promise.mli   virtual modules (the backend contract)
backends/melange/     Dom/History/Promise over Melange externals (+ reativa_runtime.js)
backends/jsoo/        Dom/History/Promise over Js_of_ocaml.Js.Unsafe (package reativa-jsoo)
ppx/                  the mlx ppx (reativa.mlx_ppx); mlx_prop_table.ml is generated
test/                 native tests; test/dom (jsdom, plain OCaml); test/dom_mlx (jsdom, mlx);
                      test/api (API snapshot); test/consumer (built against installed packages)
inspect/              reativa-inspect: CLI + MCP server over Devtools (Node)
benchmarks/           keyed-list benchmark vs xote and SolidJS
demo/, examples/      the todo demo (Melange) and both demos on js_of_ocaml
website/              documentation site (itself a reativa app, routed by Router) and agent docs;
                      pages are registered in website/docs.pages.mjs (see website/README.md)
docs/                 plans, release process
```

## Architecture

### Public API boundary

The public API is exactly what the `.mli` files of the re-exported modules
declare: `Signal`, `Computed`, `Effect`, `Owner`, `Dom`, `Promise`, `View`,
`Context`, `Resource`, `Devtools`, `Router_match`, `Router` (with `Route`,
`Link`, `Redirect`). `src/reativa.ml` re-exports them as **plain module
aliases** and must stay that way: native test executables link only the
modules they use, and the Melange backend's externals cannot link natively. A
`reativa.mli` with module signatures would turn `Reativa` into a real module
and drag every module into every native link.

Internals that other library modules need but users must not see live in
`*_core` modules that are not re-exported: `Signal_core` (the signal record;
`Signal.t` is a manifest of `Signal_core.t`, opaque outside the library) and
`Effect_core` (`leaf`, the owner-less effect the renderer uses).

`test/api/reativa.api` is the compiler's print of the whole public signature;
CI fails when it changes. Run `scripts/check-api.sh --update` (after a byte
build) and commit the diff when a change is intended.

### Backends

`Dom`, `History` and `Promise` are dune **virtual modules**: `src/*.mli`
declares them, each backend implements them. `View`, `Router` and everything
else compile once against the signatures. The Melange backend is the
`default_implementation`; `(libraries reativa reativa-jsoo)` selects
js_of_ocaml.

The Melange backend is also compiled natively (the core library must carry
melange mode), so its externals must be bound to **plain identifiers** —
browser globals, `[@@mel.send]` methods, or functions exported by
`backends/melange/reativa_runtime.js` — never `"#..."` primitive spellings,
and never non-function externals.

Value representation differs: js_of_ocaml represents `None`, `false` and `0`
as the same JS value, so runtime classification (`Dom.classify`,
`View.child`) supports strings, ints, floats, views and thunks only, never
options or bools.

### Reactivity

`src/signals/core.ml` is a doubly linked dependency graph: a `node` per
signal, computed or effect, a `link` per edge, threaded through both the
source's subscriber list and the target's dependency list. The scheduler
(`scheduler.ml`) re-tracks dependencies on every run (reusing links through a
cursor), processes pending computeds then effects in level order (glitch-free),
and batches through `Signal.batch`.

Semantics to preserve (each has a test in `test/test_signals.ml`):
- an effect disposed while queued is skipped by the flush and its cleanup runs
  exactly once (`flag_disposed`);
- a computed whose last subscriber goes away **detaches** from its sources and
  recomputes on its next read (`Core.detach`);
- `Computed.make` restores the tracking target even if its first run raises;
- a computed with `~equals` defers downstream effects until it has recomputed,
  so an unchanged result cancels them.

### Ownership

`Owner` (`src/signals/owner.ml`) is the tree that disposes things. Rules:

- Every effect has an owner that is current while its body runs and is
  **reset before each re-run**: whatever one run created is gone before the
  next. The effect is disposed with the owner current at its creation.
- Owners do not register with their parent; the parent pointer is only for
  context lookups and error handlers. Whoever creates an owner disposes it
  (`make_child` is the attached variant).
- Components (`View.component`, which the ppx wraps around every component
  tag), keyed rows, region passes, portals, boundaries and `View.mount` roots
  each have an owner.
- `Context` values live on owners; lookups walk up from the active owner.
- Errors from effects go to `Owner.handle_error`: the nearest
  `set_error_handler` up the chain (error boundaries), else re-raised.

### Rendering (`src/view.ml`)

A `View.t` is a description; `insert` builds DOM from it under the current
owner. Node kinds: text and reactive text, elements, fragments, `Dynamic`
regions (rebuilt wholesale when a read changes, anchored by a comment),
components, keyed lists, templates, boundaries, portals, suspense.

- **Leaves** (reactive text, attributes, properties) are `Effect_core.leaf`
  effects that remember the last value written and skip equal writes.
- **Regions** insert through their anchor's *current* parent
  (`parent_of anchor`), because their nodes can move (a keyed row is built in
  a fragment, then inserted; suspense moves its child in and out of a
  fragment).
- **A region whose old and new content are a single text** updates the text
  node's data instead of rebuilding.
- **Keyed lists** keep a persistent key table with per-pass stamps; surviving
  rows that keep their order (a longest increasing subsequence of old
  positions) do not move; new rows are built in order into one
  `DocumentFragment` per run of consecutive new rows; clearing a list that
  owns its whole parent is one `textContent` write; rows render untracked.
- **Templates** (`View.template`): an HTML skeleton parsed once through an
  inert `<template>` (separately for SVG contexts), deep-cloned per instance;
  holes are child-index paths, all resolved before any is filled.
- **SVG**: `in_svg` is set under `<svg>` and cleared under `<foreignObject>`;
  regions capture it at creation and restore it on re-runs.
- **`on_mount`** callbacks queue until the outermost insertion
  (`insertion`) finishes.

### The mlx ppx (`ppx/reativa_mlx_ppx.ml`)

mlx lowers `<div className="a">...</div>` to `div ~className:"a" ~children:[...] () [@JSX]`
and `<Card title="x" />` to `Card.createElement ~title:"x" ~children:[] () [@JSX]`. The ppx:

1. **Infers values**: literals are `static`, explicit thunks `dynamic`, and
   expressions with an *eager* signal read (a `Signal.get` outside a `fun`, a
   call to an alias of `Signal.get`, or a call to a local helper whose body
   reads one — collected per file, to a fixpoint) are thunked into `dynamic`.
   Bare children become `View.text`/`View.child`.
2. **Generates `createElement`** for any module with a `component` binding,
   wrapping the body in `View.component` (lazy, own owner, untracked) and
   forwarding every prop explicitly, `()` last so optional props erase.
3. **Compiles element trees to templates**: static parts become a hoisted
   `Reativa.View.Template.make` skeleton, dynamic parts typed holes. Props are
   resolved from `ppx/mlx_prop_table.ml` (generated from
   `scripts/generate-mlx-props.mjs`). An element falls back to `View.Mlx`
   (becoming a child hole) when it has an unknown prop or markup the HTML
   parser would restructure (text in table sections, `tr` in `table`, block in
   `p`, `a` in `a`, `select`/`textarea`). `-no-templates` disables it.
4. Marks `open ... Mlx` with `[@warning "-33"]` (templates can leave it unused).

The ppx targets ppxlib's OCaml 5.2 AST (`Pexp_function (params, constraint, body)`,
`Pfunction_cases (cases, loc, attrs)`). It cannot be built with older ppxlib.

### Devtools and reativa-inspect

`src/signals/trace.ml` holds hooks the core and renderer call behind one
`!Trace.enabled` test. `Devtools.install` sets them; `Devtools.expose` puts a
JSON API on `globalThis.__reativaDevtools`, which `inspect/` (a Node CLI and MCP
server) drives under jsdom.

## Common pitfalls

- **Structural equality on DOM nodes, owners or closures** (`=`, `<>`,
  `compare`) recurses into JS objects or raises on functional values. Use
  `==`, `Dom.is_same_node`, `Option.is_none`, or a `match`.
- **Stack depth**: js_of_ocaml runs on the browser stack. On paths that see a
  whole list, use tail-recursive folds (`map_list` in view.ml), not
  `List.map`/`List.fold_right`/`@`.
- **Closure retention under js_of_ocaml**: V8 shares one context per function
  call among its closures, and the release build inlines helpers. A
  long-lived closure (an effect) created in a function that also captures a
  big value (a view description) keeps that value alive. Keep persistent
  closures out of scopes that capture view descriptions (see
  `insert_element`); check with the heap-snapshot approach in the benchmark
  notes if memory regresses.
- **Generated code**: edit the table in `scripts/generate-mlx-props.mjs`, not
  the generated blocks in `view.ml`/`view.mli` or `ppx/mlx_prop_table.ml`.
- **Adding to `Dom`/`History`/`Promise`** obliges both backends; keep the
  surface to what the library needs.
- **Public API changes** need `.mli` updates, the API snapshot, and usually
  the consumer test (`test/consumer`).

## Testing

- Native: `dune test` (signals, router, ppx rewrite).
- DOM: `test/dom/*.ml` are plain OCaml; `Probe` (one implementation per
  backend under `test/dom/probe/`) reads the DOM, fires events, counts DOM
  calls (`Probe.ops`, wrapped by `test/dom/run.mjs`) and builds deferred
  promises. Add a suite by registering it in `test/dom/main.ml` and the module
  list in `test/dom/dune`. `test/dom_mlx` is the same harness for mlx code.
- Every behaviour change gets a test; perf changes get a DOM-op count test
  where possible (they are deterministic), and a benchmark run.

## Conventions

- Conventional Commits (commitlint enforces them); semantic-release cuts
  releases (`docs/RELEASING.md`). Breaking changes carry a
  `BREAKING CHANGE:` footer with migration notes.
- Comments explain *why*; code is OCaml formatted like its surroundings
  (2-space indent, 100 columns).

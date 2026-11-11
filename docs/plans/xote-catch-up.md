# Plan: catch reativa up with xote 7.x

Status: proposal · Baseline: reativa 1.2.0, xote 7.2.0

reativa started from xote's model around the 7.0 line: signals derived from
rescript-signals, a DOM-building `View`, Show/Maybe/ForEach, keyed lists and
a router. Since then xote shipped 7.1 and 7.2. This plan lists what reativa
should take from them, in three tracks (features, performance, tooling), in
the order the work depends on.

Out of scope for now: SSR, hydration, SSRState and MDX (reativa has none of
them, and they are a separate project), and xote's prebuilt ppx binaries
(opam builds reativa's ppx natively, so the problem they solve does not exist
here). The ownership work in phase 1 should still leave room for SSR later.

---

## The one prerequisite: an owner tree

Almost every 7.2 feature depends on something reativa doesn't have yet: a
scope (owner) tree.

Today `View.insert` passes a `register` callback down the tree and collects
disposers into `ref` lists. That works for effects the renderer creates
itself, but:

- An `Effect.run` or `Computed.make` called in a component body is never
  disposed. A component is a plain function that runs when the view is built,
  so nothing owns what it creates. xote fixed the same bug in 7.1 ("own
  effects created while a component renders", "make a component body its own
  reactive scope").
- There is nowhere to hang a context value, an error handler, a mount or
  cleanup callback, or a suspense counter.

So step 1 of the feature track is `Owner`: a current-owner pointer, child
owners per region (Dynamic pass, keyed row, root), `Effect` and `Computed`
registering with the current owner, and disposal that runs cleanups
child-first. Build it the way xote 7.2 does from the start, which saves
porting perf fixes later (see P4 and P5): one owner per *region*, not per DOM
node; allocate it lazily, only when something registers; keep disposers in a
flat array; dispose with an explicit stack, not recursion over snapshots.

---

## Track A: Features

| # | Item | xote source | Depends on | Size |
|---|------|-------------|------------|------|
| A0 | Signal correctness fixes (see below) | rescript-signals 3.1.2 / 3.1.3 | — | S |
| A1 | Owner tree; component bodies get their own scope and run untracked | 7.1 fixes `ef49150`, `3bab9b7`, `291d8e9`; `RuntimeOwner.res` | A0 | L |
| A2 | `View.on_cleanup`, `View.on_mount`, element refs (`View.Ref.make`, `Ref.from_callback`, a `ref` prop in mlx) | 7.2 `80e91d1` | A1 | M |
| A3 | `Context`: `make`, `use`, `provide`, `provider`, `<Context.Provider>` | 7.2 `edd5192`, plus the fix `cf2cec7` | A1 | M |
| A4 | `View.ErrorBoundary`: catch errors thrown while rendering or in owned effects, with fallback and reset | 7.2 `689bf18` | A1 (+A3 lookup) | M |
| A5 | `View.Portal`: render into another container, owned by the portal's own scope | 7.2 `49979eb` | A1 | S |
| A6 | `Resource` (`make`, `refetch`, `mutate`, `value`, `is_loading`) and `View.Suspense` | 7.2 `32ce93e` | A1, A3, A4 | L |
| A7 | Devtools runtime: named nodes, scope snapshot, event stream, `why`, `leaks`, `writers_of` | 7.2 `8fc5cd1` (`Devtools.res`) | A1 | L |
| A8 | Leftover 7.1 parity items (see below) | 7.0/7.1 | — | M |

**A0, signal fixes.** These are small, but they come first because the owner
tree relies on them.
- *Disposed effects must not run.* In `scheduler.ml`, `retrack_effect` runs any
  queued node. An effect disposed while it sits in `pending_effects` still
  runs its body once more and leaves a cleanup armed. Mark disposal on the
  node, skip disposed nodes in `flush`, and run the cleanup exactly once
  (rescript-signals 3.1.3).
- *Unobserved computeds should detach.* A computed stays linked to its sources
  after its last subscriber goes away. Unlink it then, and recompute on the
  next read (3.1.2). Without this, a `Computed` built for a region that is
  thrown away keeps a reference from every signal it read.
- *Restore the active owner and tracking target when a component throws.*
  `Effect.run_with_disposer` already restores the target. `Computed.make`
  does not.

**A1 notes.** Wrap component calls so their bodies run under a fresh owner
and inside `Signal.untrack`. In mlx, this means the ppx's lowering for
uppercase component modules (`createElement`) goes through a
`View.component` thunk instead of calling the function eagerly. This is the
analogue of xote's `LazyComponent`.

**A3 notes.** Port the 7.2 *fixed* semantics, not the first version: lookups
walk the owner chain, and an effect or boundary only sees providers above it
in its own subtree (`cf2cec7`).

**A6 notes.** There is no shared promise type across backends. Define
`Resource` over a minimal backend-provided `Async` interface (Melange:
`Js.Promise`; jsoo: `Promise` via `Js_of_ocaml`), or over a callback-style
fetcher `(('a, exn) result -> unit) -> unit` that both backends can satisfy.
Decide this before starting. Dependencies are tracked before the first await,
the same as xote.

**A7 notes.** Keep the instrumentation behind a flag that dead-code
elimination can remove, and that adds nothing to a production Melange bundle
(xote: "only the guarded instrumentation points ship in client bundles").
Put the panel UI (`DevtoolsPanel`) in a separate `reativa.devtools` library
so the core stays small.

**A8, 7.0/7.1 parity items still missing.**
- `attrs` escape hatch on mlx elements, and removable attributes (a reactive
  attribute returning `option` removes the attribute on `None`). `Mlx.create`
  knows 10 attributes and 5 events today. xote has around 120 props and 30
  handlers.
- SVG elements via `createElementNS` (xote 6.4).
- More element helpers and events (pointer events, xote 6.3).
- `.mli` files for `View`, `Router`, `Signal`, `Computed`, `Effect`, `Reativa`.
  This enforces the public API boundary, as xote 7.1 `b1d6ded` did. It is
  listed here because it changes what users can reach, and the tooling
  guardrail (T3) builds on it.
- Audit the mlx ppx against the 7.2 `@xote.component` hardening:
  control-flow branches, fragment bodies, render callbacks, local reactive
  helpers, namespaced value components, no double-thunking of values already
  written as functions. Each fixed xote case becomes a `test_ppx_rewrite` case
  here. Port only the cases that apply to mlx.

---

## Track B: Performance

Every item is measured against the benchmark from T1 before it lands.

| # | Item | xote source | Expected win | Depends on |
|---|------|-------------|--------------|------------|
| P1 | Keyed reorder moves only displaced rows (LIS) | 7.1 `0992cc4` | High. `move_block_before` cascades today, so swapping 2 of 1,000 rows moves about 997 blocks (xote: 997 → 2 DOM ops, 66.8 → 6.0 ms) | T1 |
| P2 | Skip DOM writes when the value equals the last one written (attrs, text, `value`, `checked`) | 7.2 `9622940` | Medium. Selecting a row writes 2 attributes, not 1,000 | — |
| P3 | Update reactive text in place: a `child` thunk or tracked region that returns a scalar updates its text node's `data` and no longer rebuilds the region | 7.2 `19ceee2` | Medium. No allocation on each text update | — |
| P4 | State owned per region, lazy owner allocation, flat disposer arrays, stack-based disposal | 7.1 `89a120b`, `046e51f`; 7.2 `9622940` | High for memory and clear times (xote heap at 10k rows: 40 → 15 MB) | A1 |
| P5 | Keyed reconciler rewrite: `Hashtbl` reused across passes, per-pass stamps instead of a `seen_keys` table, no move for in-order updates (append, remove, create from empty), new rows batched into a `DocumentFragment`, arrays instead of lists on the hot path | 7.2 `9622940` | High on create, append and clear | P1 |
| P6 | Clone repeated shapes: record a static skeleton of a row's first tree, then `cloneNode` it and walk the shape to attach effects and handlers | 7.2 `9622940` | High. About 10× fewer DOM calls per row | P4, P5 |
| P7 | Lower mlx props straight to an attribute and event list at compile time, so `Mlx.create` stops probing every optional argument | 7.2 `d956450` | Low to medium. Cheaper per element, and attributes render in source order | A8 (prop table) |

P6 has an OCaml-specific option worth prototyping: the mlx ppx can see the
static skeleton of an element tree at compile time, so it could emit the
template directly (Solid-style). That avoids recording skeletons at runtime.
Start with xote's runtime approach, because it also covers trees that aren't
written in mlx. Revisit the ppx version once the benchmark exists.

Check that every perf change works on both backends. js_of_ocaml lists,
closures and `Hashtbl` cost differently than in Melange, so the benchmark
should run both.

---

## Track C: Tooling

| # | Item | xote counterpart | Why |
|---|------|------------------|-----|
| T1 | Keyed-list benchmark: the same app in reativa (Melange and jsoo), xote and SolidJS. Measures latency, startup, memory, payload and DOM-op counts. A `benchmark`-labelled CI workflow posts a main-vs-PR comment, with runs interleaved in one browser | `benchmarks/`, `benchmark.yml`, `scripts/benchmark-report.mjs` | Track B needs it before anything lands |
| T2 | DOM test harness. reativa has no view tests today, only signals, router and ppx. Add a fake `Dom` backend (the virtual-module split already allows this) so view, owner, keyed-list and lifecycle tests run natively under `dune test`. Add a small jsdom smoke suite that runs the same scenarios on the Melange and jsoo outputs | `tests/*_test.res` + jsdom `setup.mjs` | Track A can't be done safely without it. Port xote's Ownership, Lifecycle, Context, ErrorBoundary, Portal, Resource and KeyedList tests as specifications |
| T3 | Public API guardrails: an exported-surface snapshot per module, and a consumer test that builds an out-of-tree project against the installed opam package | `test:exports`, `scripts/consumer-boundary-test.mjs` | Keeps the `.mli` boundary from A8 honest |
| T4 | `AGENTS.md` as the single source of truth (architecture, reactivity model, patterns, pitfalls), a one-line `CLAUDE.md` pointer, and both shipped in the opam package | xote `AGENTS.md`, 7.1 `450e210` | Agents and contributors work from the same reference |
| T5 | Docs site: one page registry that drives routes, sidebar and search; a human and an agent layer per page; Markdown copies and `/llms.txt`; "New in 1.x" badges | 7.2 `1524427` | Same docs model as xote. Agent pages follow xote's fixed outline |
| T6 | `reativa-lens`: a CLI and MCP server over the devtools runtime (render headlessly, `--act`, `--why`) | `lens/` | Comes after A7. Can run on the jsoo or Melange output under jsdom |
| T7 | Release channels: an `rc` prerelease branch in `.releaserc.json`, so phases ship as `1.3.0-rc.N` the way 7.2 went through betas | xote `314ad34` | Lets large features ship early without blocking the main branch |
| T8 | Repo hygiene: `.gitattributes` (linguist rules for `_build`, benchmarks and the website; LF for `*.sh`), Dependabot for npm and GitHub Actions | xote `.gitattributes`, dependabot PRs | Small and independent |

---

## Sequencing

```
Phase 0 (tooling first)   T2 DOM harness · T1 benchmark · T8 hygiene · T4 AGENTS.md
Phase 1 (foundation)      A0 signal fixes → A1 owner tree (built as P4) → A8 .mli files + T3 guardrails
Phase 2 (quick perf)      P1 LIS · P2 skip-equal writes · P3 text in place        (parallel with phase 3)
Phase 3 (7.2 features)    A2 lifecycle/refs → A3 Context → A4 ErrorBoundary → A5 Portal → A6 Resource/Suspense
Phase 4 (deep perf)       P5 reconciler rewrite → P6 shape cloning → P7 compile-time props
Phase 5 (observability)   A7 devtools runtime → T6 lens → T5 docs layers for everything above
```

Suggested releases, through the `rc` channel (T7):
- **1.3.0**: phases 0–2 and A2/A3. Lifecycle, refs and Context, plus the
  correctness fixes and quick perf wins.
- **1.4.0**: A4–A6 and phase 4. Boundaries, Resource/Suspense and the
  rendering rewrite.
- **1.5.0**: devtools and lens.

A1 changes when component bodies run: lazily, under their own scope. Code
that relied on a component body running at construction time will notice.
Call this out in the 1.3.0 notes. If it turns out to be observable in
practice, ship it as a `feat!` and make it 2.0.0.

## Decisions needed before starting

1. **Resource's async type** (A6): backend promise module or callback-style
   fetcher.
2. **Component laziness in mlx** (A1): change the ppx lowering for all
   uppercase components, or only for components that opt in.
3. **Template cloning** (P6): runtime skeleton recording as in xote, or
   ppx-emitted templates.
4. **Fake-DOM fidelity** (T2): how much of `Dom` the native fake needs to
   model (comments, siblings, `cloneNode`) before jsdom is the better tool.

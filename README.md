# reativa

Reactive **Signals** for **OCaml + [Melange](https://melange.re/)**, targeting the
browser. It implements three primitives — `Signal`, `Computed`, `Effect` —
backed by a push/pull, level-ordered reactive scheduler, written in idiomatic
OCaml with no unsafe casts.

```ocaml
open Reativa

let count   = Signal.make 0
let doubled = Computed.make (fun () -> Signal.get count * 2)

let () =
  Effect.run (fun () ->
    Printf.printf "doubled = %d\n" (Signal.get doubled);
    None)

let () = Signal.set count 5   (* prints: doubled = 10 *)
```

## API

- **`Signal`** — `make` (with optional `~name` / `~equals`), `get`, `peek`,
  `set`, `update`, plus `batch` and `untrack`.
- **`Computed`** — `make` (with optional `~name` / `~equals`), lazily evaluated;
  recomputes only when read after a dependency changed; `dispose`.
- **`Effect`** — `run` and `run_with_disposer`, with optional cleanup functions
  that run before each re-run and on dispose.

## How it works

The reactive graph is a doubly linked structure. Every reactive thing — a plain
signal, a computed, or an effect — is one `Core.node`. A `Core.link` is an edge
between a **source** node (value being read) and a **target** node (the observer
reading it). Each link lives in two intrusive linked lists at once:

- the source's **subscriber** list (`next_sub` / `prev_sub`)
- the target's **dependency** list (`next_dep` / `prev_dep`)

| role     | shape                                          |
| -------- | ---------------------------------------------- |
| signal   | node with neither `compute` nor `run`          |
| computed | node with `compute = Some _` (source + target) |
| effect   | node with `run = Some _` (target only)         |

Reads inside a running effect/computed are recorded as dependencies; writes walk
the subscriber lists to mark computeds dirty (lazily) and queue effects. The
scheduler processes pending work in **level** order — a node's level is one more
than the deepest computed it depends on — which gives glitch-free updates in
diamond-shaped graphs. Other properties carried over from the design:

- **batching** (`Signal.batch`) coalesces multiple writes into one flush,
- **lazy computeds** recompute only when actually read,
- **version-based de-duplication** keeps dependency tracking allocation-free in
  steady state,
- a **custom-equality computed** defers its downstream effects until it
  recomputes, so an unchanged result cancels the effect run.

## Build, test, demo

The core depends only on the OCaml stdlib, so the behavioral suite runs
**natively** — no Melange toolchain required:

```sh
dune test          # runs test/test_signals.ml natively (33 behavioral checks)
```

To compile to JavaScript you need Melange (`opam install melange`):

```sh
dune build @melange    # emits the library + demo to JS
npm run demo           # builds and bundles demo/app.ml, then open demo/index.html
```

The demo (`demo/app.ml` + `demo/index.html`) is a counter wired entirely through
Signals: a writable `count`, a `doubled` computed, a custom-equality `parity`
computed (so the even/odd label only re-renders when parity flips), and three
effects that keep the DOM text in sync.

## License

MIT © Bernardo Gurgel

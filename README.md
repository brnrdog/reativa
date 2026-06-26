# reativa

A lightweight, high-performance reactive **signals** library for **OCaml +
[Melange](https://melange.re/)**.

reativa is a complete port of
[rescript-signals](https://github.com/brnrdog/rescript-signals), rewritten in
idiomatic OCaml. It implements the same three primitives — `Signal`, `Computed`,
`Effect` — backed by a push/pull, level-ordered reactive scheduler.

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

## Primitives

- **`Signal`** — a reactive state container. Read with `get`, read without
  tracking with `peek`, write with `set` / `update`. Includes `batch` and
  `untrack`.
- **`Computed`** — derived values that update automatically. Lazily evaluated and
  cached until their dependencies change. Supports `dispose`.
- **`Effect`** — side effects that re-run when their dependencies change, via
  `run` and `run_with_disposer`, with optional cleanup functions.

`make` for `Signal` and `Computed` accepts optional `~name` and `~equals`.

## Build, test, demo

The core depends only on the OCaml stdlib, so the test suite runs natively — no
Melange toolchain required:

```sh
dune test          # runs the behavioral suite natively
```

To compile to JavaScript you need Melange (`opam install melange`):

```sh
dune build @melange    # emits the library + demo to JS
npm run demo           # builds and bundles demo/app.ml, then open demo/index.html
```

## License

MIT © Bernardo Gurgel

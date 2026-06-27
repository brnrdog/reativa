# reativa

(Experimental) A lightweight, high-performance reactive **signals** library for **OCaml**.

reativa is a port of
[rescript-signals](https://github.com/brnrdog/rescript-signals), rewritten in
idiomatic OCaml. It implements the same three reactive primitives: `Signal`, `Computed`, 
and `Effect`.

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

## UI layer (experimental)

`reativa_ui` is a small, fine-grained reactive UI layer on top of the signals —
inspired by [xote](https://github.com/brnrdog/xote), which builds the same kind
of UI on `rescript-signals`. There is **no virtual DOM**: a view describes real
DOM nodes once, and afterwards only the reactive regions update, driven straight
from the signals via `Effect`.

JSX would be the nicest surface here, but Melange's JSX transform is currently
geared towards React; rather than pull in that dependency for a proof of
concept, this first cut ships the plain **function API** that JSX would desugar
to anyway. A custom JSX ppx is a natural follow-up.

```ocaml
open Reativa
open Reativa_ui
open View

let () =
  let count = Signal.make 0 in
  mount_by_id "app"
    (div
       [ span [ dyn_int (fun () -> Signal.get count) ]
       ; button
           ~events:[ On.click (fun _ -> Signal.update count (fun n -> n + 1)) ]
           [ text "+1" ]
       ])
```

Building blocks: `text` / `int`, `dyn_text` / `dyn_int` (reactive text),
`element` and HTML helpers (`div`, `span`, `button`, `ul`, `li`, …), the `Attr`
and `On` modules for (reactive) attributes and events, and the control-flow
combinators `dyn`, `show`, `maybe` and `for_`. Render with `mount` /
`mount_by_id`. See `demo/ui/` for a worked counter-and-list example.

## Build, test, demo

The core depends only on the OCaml stdlib, so the test suite runs natively:

```sh
dune build            # build the library
dune test             # run the behavioral suite
npm run demo          # build and bundle demo/app.ml
npm run demo:serve    # build and serve the demo at http://127.0.0.1:8080/
npm run demo:ui       # build and bundle the reativa_ui demo
npm run demo:ui:serve # build and serve the UI demo at http://127.0.0.1:8080/
```

## License

MIT © Bernardo Gurgel

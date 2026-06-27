# reativa

(Experimental) A lightweight library for building fine-grained reactive web
interfaces with **OCaml** and **Melange**.

reativa is a port of
[rescript-signals](https://github.com/brnrdog/rescript-signals), rewritten and
extended for idiomatic OCaml. The package provides `Signal`, `Computed`,
`Effect`, and `View`; the view layer uses the reactive primitives to mount real
DOM nodes and update only the parts of the interface that depend on changing state.

The goal is to make browser UI feel like OCaml: explicit data flow, ordinary
functions, and reactive views without a virtual DOM.

## Reactive views

```ocaml
open Reativa

let count   = Signal.make 0
let doubled = Computed.make (fun () -> Signal.get count * 2)

let () =
  View.mount_by_id "app"
    [%reativa.jsx
      {|
      <main>
        <p>{View.dyn_int (fun () -> Signal.get doubled)}</p>
        <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>
          +1
        </button>
      </main>
      |}]
```

`count` is mutable reactive state. `doubled` is cached derived state. The text
node is patched whenever `count` changes; the surrounding DOM is created once.

## What it includes

- **`Signal`** — mutable reactive state. Read with `get`, read without tracking
  with `peek`, write with `set` / `update`, and coordinate changes with `batch`
  and `untrack`.
- **`Computed`** — lazily evaluated derived values that cache until their
  dependencies change. Supports `dispose`.
- **`Effect`** — side effects that re-run when tracked reads change, via `run`
  and `run_with_disposer`, with optional cleanup functions.
- **`Reativa.View`** — a small DOM view layer. It creates real browser nodes,
  then updates reactive text, attributes and dynamic regions in place.
- **`[%reativa.jsx]`** — an experimental PPX for JSX-like markup embedded in an
  OCaml extension.

`make` for `Signal` and `Computed` accepts optional `~name` and `~equals`.

## View layer

`Reativa.View` is inspired by [xote](https://github.com/brnrdog/xote), which
builds the same kind of UI on `rescript-signals`. There is **no virtual DOM**:
a view describes real DOM nodes once, and afterwards only the reactive regions
update, driven straight from signals through `Effect`.

You can write views with the plain function API:

```ocaml
open Reativa

let () =
  let count = Signal.make 0 in
  View.mount_by_id "app"
    (View.div
       [ View.span [ View.dyn_int (fun () -> Signal.get count) ]
       ; View.button
           ~events:
             [ View.On.click
                 (fun _ -> Signal.update count (fun n -> n + 1))
             ]
           [ View.text "+1" ]
       ])
```

Or with the JSX-like PPX:

```ocaml
[%reativa.jsx
  {|
  <button onClick={fun _ -> Signal.set count 0}>
    reset
  </button>
  |}]
```

The PPX lowers static attributes, reactive attributes, children and event
handlers to the same `Reativa.View` constructors. Because raw `<div />`
syntax is not valid OCaml before preprocessing, markup currently lives inside
the `[%reativa.jsx {| ... |}]` extension.

```ocaml
open Reativa

let () =
  let count = Signal.make 0 in
  View.mount_by_id "app"
    [%reativa.jsx
      {|
      <section>
        <strong>{View.dyn_int (fun () -> Signal.get count)}</strong>
        <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>
          increment
        </button>
      </section>
      |}]
```

Building blocks: `text` / `int`, `dyn_text` / `dyn_int` (reactive text),
`element` and HTML helpers (`div`, `span`, `button`, `ul`, `li`, …), the `Attr`
and `On` modules for (reactive) attributes and events, and the control-flow
combinators `dyn`, `show`, `maybe` and `for_`. Render with `mount` /
`mount_by_id`. See `demo/ui/` for the JSX-backed browser demo.

## Build, test, demo

The signal graph and scheduler are plain OCaml, so the behavioral suite runs
natively. The DOM view layer is intended for Melange/browser targets:

```sh
dune build         # build the library
dune test          # run the behavioral suite
npm run demo       # build and bundle the JSX-backed demo
npm run demo:serve # build and serve the demo at http://127.0.0.1:8080/
```

## License

MIT © Bernardo Gurgel

# Prototype: Reativa on js_of_ocaml instead of Melange

This directory rebuilds Reativa's demos with **js_of_ocaml** instead of
**Melange**, reusing the reactive core, the `View` layer, the `Router` logic and
the demo apps *unmodified*. It exists to show how much of Reativa is actually
tied to Melange (almost nothing) and what a second OCaml-to-JS engine costs.

## The short answer

The engine coupling lives entirely in the FFI modules. After the small
refactor on the `src/` side, those are exactly two files:

- `src/dom.ml` — the browser DOM (+ a few event-modifier accessors)
- `src/history.ml` — the browser history/location API used by the router

Everything else — the whole `signals/` core, `view.ml`, `router.ml`,
`router_match.ml` and the `reativa.mlx_ppx` JSX transform — is engine-agnostic
OCaml that already compiles to native today. `router.ml` used to carry its own
`external`s inline; those were extracted into `src/history.ml` so the routing
*logic* is now FFI-free and portable.

This prototype reuses those engine-agnostic sources **verbatim** (via dune
`copy_files`) and swaps in two new files:

| File | Role |
|------|------|
| `dom.ml` | js_of_ocaml implementation of the `Dom` FFI (mirrors `src/dom.ml`) |
| `history.ml` | js_of_ocaml implementation of the `History` FFI (mirrors `src/history.ml`) |
| `reativa.ml` | API aggregator so `open Reativa` resolves (mirrors `src/reativa.ml`) |
| `router_demo.ml` | small SPA exercising the ported router |
| `todo.mlx`, `view.ml`, `router.ml`, `router_match.ml`, `signals/*.ml` | *copied unmodified* from `src/` and `demo/ui/` |

Both `dom.ml` and `history.ml` expose the same value signatures as their Melange
counterparts, so `view.ml` and `router.ml` compile against them with zero
changes. Where Melange writes:

```ocaml
external push_state : history -> state nullable -> string -> string -> unit
  = "pushState" [@@mel.send]
```

the js_of_ocaml version writes:

```ocaml
let push_state h st title url =
  ignore (Js.Unsafe.meth_call h "pushState"
    [| Js.Unsafe.inject st; Js.Unsafe.inject (Js.string title); Js.Unsafe.inject (Js.string url) |])
```

Same signature, different engine. That is the entire migration surface.

## The two demos

- **todo** — `demo/ui/todo.mlx`, reused verbatim (same JSX, same ppx), driving
  the DOM through the js_of_ocaml `Dom`.
- **router_demo** — a small SPA (`router_demo.ml`) that drives the *unmodified*
  `src/router.ml` through the js_of_ocaml `History` + `Dom`. Links, `pushState`
  navigation, `popstate` and `<Redirect>` all run on js_of_ocaml.

## Running them

Requires `js_of_ocaml` and `js_of_ocaml-compiler` (plus the usual `mlx`):

```sh
opam install js_of_ocaml js_of_ocaml-compiler
npm run demo:jsoo               # builds both self-contained bundles

npm run demo:jsoo:serve         # todo demo   -> http://localhost:8080/
npm run demo:jsoo:router:serve  # router demo -> http://localhost:8080/
```

Note there is **no bundler step**: js_of_ocaml links the OCaml runtime and every
module — including the router — into one self-contained `*.bc.js`. The Melange
demo, by contrast, emits per-module ES modules that esbuild then bundles.

The example is gated behind `REATIVA_JSOO=enabled` so the default `dune build`,
`dune test` and the existing Melange build never require js_of_ocaml to be
installed. CI verifies both demos in a dedicated `jsoo-build` job.

## The one genuinely representation-sensitive spot: `View.child`

`view.ml`'s runtime child coercion (`View.child`, behind bare JSX children)
inspects the *JavaScript representation* of an OCaml value via `Dom.typeof` /
`Dom.display_string`. That is inherently engine-dependent, because Melange and
js_of_ocaml map OCaml values to JS differently:

| OCaml bare child | Melange `typeof` | js_of_ocaml `typeof` |
|------------------|------------------|----------------------|
| `string` | `"string"` | `"string"` ✓ (js-string runtime, the default) |
| `int` | `"number"` | `"number"` ✓ |
| already-built `View.t` | `"object"` | `"object"` ✓ |
| a thunk (`unit -> _`) | `"function"` | `"function"` ✓ |
| `None` | `"undefined"` → renders nothing | `"number"` (0) → renders `"0"` |
| `bool` | `"boolean"` | `"number"` (0/1) |

So the demos — which only ever pass strings, ints and views as bare children —
behave identically on both engines. But `None`/`bool` bare children differ, and
js_of_ocaml *cannot* recover them at runtime (an OCaml `false`, `0` and `None`
are the same JS value under js_of_ocaml). The portable fix is to not depend on
JS representation there: use the explicit `View.text` / `View.int` / `View.show`
/ `View.maybe` constructors, which carry the OCaml type through and render the
same under any engine. This is the one place a production multi-engine build
would tighten; it is called out here rather than papered over.

## Prototype shortcut vs. production shape

`copy_files` is used here purely so the prototype stays **additive** — it does
not change how `src/` is compiled, so the Melange build is unchanged. In
production you would instead make `Dom` and `History` dune **virtual modules**:
the `reativa` library declares `(virtual_modules dom history)`, and two
implementation libraries (`reativa.melange`, `reativa.jsoo`) provide them, with
`(default_implementation reativa.melange)` keeping every existing consumer
working unchanged. That removes the source copying and lets both engines share
one compiled library definition.

## Engine trade-offs

| | Melange | js_of_ocaml |
|---|---|---|
| Output | per-module idiomatic ES, tree-shakeable | one linked script incl. OCaml runtime |
| Baseline size | tiny (no runtime shipped) | ships the OCaml runtime |
| DOM/history interop | zero-cost `[@mel.*]` externals | via `Js.Unsafe` |
| Bundler | needs esbuild/vite | none required |
| OCaml ecosystem | melange-compatible libs only | full opam ecosystem, effects, exceptions |

For a fine-grained reactive DOM library, Melange remains the natural primary
target (small output, zero-cost interop). js_of_ocaml is valuable as a *second*
backend — letting full-OCaml/js_of_ocaml apps use Reativa and reach the wider
opam ecosystem.

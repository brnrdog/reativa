# Prototype: Reativa on js_of_ocaml instead of Melange

This directory builds the exact same todo demo as `demo/ui/` — the same
`todo.mlx` source, the same JSX ppx, the same reactive core and `View` layer —
but compiles it to JavaScript with **js_of_ocaml** rather than **Melange**.

It exists to answer one question: *how much of Reativa is actually tied to
Melange, and how hard is it to target a different OCaml-to-JS engine?*

## The short answer

Almost none of it is tied to Melange. The engine coupling lives entirely in the
FFI modules (`src/dom.ml` and `src/router.ml`). Everything else — the whole
`signals/` core, `view.ml`, `router_match.ml`, and the `reativa.mlx_ppx` JSX
transform — is engine-agnostic OCaml that already compiles to native today.

This prototype reuses those engine-agnostic sources **verbatim** (via dune
`copy_files`, see `dune`) and swaps in a single new file:

| File | Role |
|------|------|
| `dom.ml` | js_of_ocaml implementation of the `Dom` FFI — the **only** new logic |
| `reativa.ml` | trimmed API aggregator so `open Reativa` resolves (mirrors `src/reativa.ml`) |
| `todo.mlx` | *copied unmodified* from `demo/ui/todo.mlx` |
| `view.ml`, `signals/*.ml` | *copied unmodified* from `src/` |

`dom.ml` exposes the same value signature as the Melange `src/dom.ml`, so
`view.ml` compiles against it with zero changes. Where Melange writes:

```ocaml
external create_element : string -> t = "createElement" [@@mel.scope "document"]
external append_child : t -> t -> unit = "appendChild" [@@mel.send]
```

the js_of_ocaml version writes:

```ocaml
let create_element tag =
  Js.Unsafe.meth_call document "createElement" [| Js.Unsafe.inject (Js.string tag) |]
let append_child parent child =
  ignore (Js.Unsafe.meth_call parent "appendChild" [| Js.Unsafe.inject child |])
```

Same signature, different engine. That is the entire migration surface for the
DOM layer.

## Running it

Requires `js_of_ocaml` and `js_of_ocaml-compiler` (plus the usual `mlx`):

```sh
opam install js_of_ocaml js_of_ocaml-compiler
npm run demo:jsoo         # builds examples/jsoo/bundle.js
npm run demo:jsoo:serve   # serves this directory at http://localhost:8080
```

Note there is **no bundler step**: js_of_ocaml links the OCaml runtime and every
module into one self-contained `todo.bc.js`. The Melange demo, by contrast,
emits per-module ES modules that esbuild then bundles — a real trade-off (see
below).

The example is gated behind `REATIVA_JSOO=enabled` so the default `dune build`,
`dune test` and the existing Melange build never require js_of_ocaml to be
installed. CI verifies it in a dedicated `jsoo-build` job.

## What this prototype does and does not cover

**Covered:** the full reactive stack — Signal / Computed / Effect / scheduler —
and the `View` layer (reactive text, attributes, `Dynamic` regions, keyed lists,
event handlers) running end to end on js_of_ocaml, driving the real DOM.

**Not covered (deliberately, to keep the prototype small):**

- **Router.** `src/router.ml` is the other Melange-FFI module. The todo demo
  doesn't use it, so it isn't ported here. It would be virtualised exactly the
  same way as `Dom` — extract the signature, provide a js_of_ocaml
  implementation of the `window`/`history`/`location` bindings.
- **`View.child` value representation.** `view.ml`'s runtime child coercion
  inspects the *JavaScript representation* of an OCaml value (`typeof`). Strings,
  numbers and already-built views — everything the demo passes as a bare JSX
  child — map the same way under js_of_ocaml's default (JS-string) runtime as
  under Melange, so the demo behaves identically. But this is the one spot that
  is genuinely representation-sensitive: e.g. an OCaml `bool` used as a bare
  child is a JS `boolean` under Melange but a number under js_of_ocaml. A
  production port would make this explicit rather than relying on `typeof`.

## Prototype shortcut vs. production shape

`copy_files` is used here purely so the prototype is **additive** — it does not
modify `src/` at all, so the Melange build is provably unchanged. In production
you would instead make `Dom` a dune **virtual module**: the `reativa` library
declares `(virtual_modules dom)`, and two implementation libraries
(`reativa.melange`, `reativa.jsoo`) provide `dom.ml`, with
`(default_implementation reativa.melange)` keeping every existing consumer
working unchanged. That removes the source copying and lets both engines share
one compiled library definition.

## Engine trade-offs

| | Melange | js_of_ocaml |
|---|---|---|
| Output | per-module idiomatic ES, tree-shakeable | one linked script incl. OCaml runtime |
| Baseline size | tiny (no runtime shipped) | ships the OCaml runtime |
| DOM interop | zero-cost `[@mel.*]` externals | via `Js.Unsafe` / `Dom_html` |
| Bundler | needs esbuild/vite | none required |
| OCaml ecosystem | melange-compatible libs only | full opam ecosystem, effects, exceptions |

For a fine-grained reactive DOM library, Melange remains the natural primary
target (small output, zero-cost interop). js_of_ocaml is valuable as a *second*
backend — letting full-OCaml/js_of_ocaml apps use Reativa and reach the wider
opam ecosystem.

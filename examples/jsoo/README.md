# Reativa on js_of_ocaml

This directory builds Reativa's demos with the **js_of_ocaml** backend instead
of **Melange**, reusing the reactive core, the `View` layer, the `Router` logic
and the demo apps *unmodified*. It exists to show how much of Reativa is
actually tied to Melange (almost nothing) and what a second OCaml-to-JS backend
costs.

## The short answer

The backend coupling lives entirely in the FFI modules, and there are exactly
two of them. They are dune **virtual modules**: `src/` declares only their
signatures, and each backend ships an implementation.

| Virtual module | Signature | Melange | js_of_ocaml |
|---|---|---|---|
| `Dom` | `src/dom.mli` | `backends/melange/dom.ml` | `backends/jsoo/dom.ml` |
| `History` | `src/history.mli` | `backends/melange/history.ml` | `backends/jsoo/history.ml` |

Everything else — the whole `signals/` core, `view.ml`, `router.ml`,
`router_match.ml` and the `reativa.mlx_ppx` JSX transform — is backend-agnostic
OCaml, compiled **once** into the `reativa` library and shared by both
backends. It already compiles to native today, which is how the test suite
exercises it without a browser.

Selecting a backend is one line in `dune`:

```lisp
(libraries reativa)               ; Melange — the default_implementation
(libraries reativa reativa-jsoo)  ; js_of_ocaml
```

Melange is the `default_implementation`, so every existing consumer keeps
working unmodified; only a build that *wants* js_of_ocaml has to name it.

The Melange backend lives in the `reativa` package while js_of_ocaml gets its
own. That asymmetry is forced by dune: an implementation links against the
virtual library's melange-mode artifacts rather than producing them (dropping
the mode from the core fails with `No rule found for
src/.reativa.objs/melange/reativa__View.cmj`), so the core must be built in
melange mode and therefore needs the Melange compiler regardless. Given that,
keeping Melange in-package costs nothing and buys the default. js_of_ocaml has
no such constraint, so it splits out cleanly and only a js_of_ocaml build pulls
it in.

The consequence is real and worth naming: a js_of_ocaml-only app still installs
Melange, because `reativa-jsoo` depends on `reativa`. The alternative that would
avoid it is an OCaml **functor** — `View.Make (Dom) (History)` — instead of dune
virtual modules. That would drop the Melange dependency entirely and let both
backends coexist in a single build (which would make a cross-backend runtime
test trivial to write). It loses on ergonomics: the mlx ppx emits plain `View.*`
calls, so every consumer would need a pre-applied module alias per backend, and
the JSX would stop working out of the box. Virtual modules keep the call sites
identical across backends, which is the property this library is built around,
so the extra dependency is the price paid for it.

## What an implementation looks like

Both implementations satisfy the same `.mli`, so `view.ml` and `router.ml`
compile against either with zero changes. Where Melange writes:

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

Same signature, different backend. That is the entire porting surface.

## The two demos

- **todo** — `demo/ui/todo.mlx`, reused verbatim (same JSX, same ppx), driving
  the DOM through the js_of_ocaml `Dom`.
- **router_demo** — a small SPA (`router_demo.ml`) driving the *same compiled*
  `Router` through the js_of_ocaml `History` + `Dom`. Links, `pushState`
  navigation, `popstate` and `Redirect` all run on js_of_ocaml.

`todo.mlx` is the only file still copied into this directory, because it lives
in a `melange.emit` directory rather than a library — there is nothing to
depend on. The library code is depended on, not copied.

## Running them

Requires `js_of_ocaml` and `js_of_ocaml-compiler` (plus the usual `mlx`):

```sh
opam install js_of_ocaml js_of_ocaml-compiler
npm run demo:jsoo               # builds both self-contained bundles

npm run demo:jsoo:serve         # todo demo   -> http://localhost:8080/
npm run demo:jsoo:router:serve  # router demo -> http://localhost:8080/

npm run demo:jsoo:watch         # rebuild + re-copy on every source change
```

The demos load `todo.bundle.js` / `router/router_demo.bundle.js` as plain
scripts, and dune writes `*.bc.js` into `_build`, so both `demo:jsoo` and
`demo:jsoo:watch` copy the built bundle across (`scripts/copy-jsoo-bundles.mjs`).
Pair `demo:jsoo:watch` with one of the serve scripts and the page live-reloads.

Note there is **no bundler step**: js_of_ocaml links the OCaml runtime and every
module — including the router — into one self-contained `*.bc.js`. The Melange
demo, by contrast, emits per-module ES modules that esbuild then bundles.

The demos are gated behind `REATIVA_JSOO=enabled` so the default `dune build`,
`dune test` and the Melange build never require js_of_ocaml to be installed. CI
verifies both demos in a dedicated job.

## The one representation-sensitive spot: `View.child`

`view.ml`'s runtime child coercion (`View.child`, behind bare JSX children)
inspects the *JavaScript representation* of an OCaml value via `Dom.classify`.
That is inherently backend-dependent, because Melange and js_of_ocaml map OCaml
values to JS differently:

| OCaml bare child | Melange | js_of_ocaml |
|------------------|------------------|----------------------|
| `string` | `"string"` | `"string"` ✓ (js-string runtime, the default) |
| `int` | `"number"` | `"number"` ✓ |
| already-built `View.t` | `"object"` | `"object"` ✓ |
| a thunk (`unit -> _`) | `"function"` | `"function"` ✓ |
| `None` | `"undefined"` → renders nothing | `"number"` (0) → renders `"0"` |
| `bool` | `"boolean"` | `"number"` (0/1) |

js_of_ocaml *cannot* recover the last two rows at runtime: an OCaml `false`,
`0` and `None` are all the same JS value under js_of_ocaml, so no
implementation of `Dom.classify` can tell them apart. The supported set of bare
children is therefore the intersection — **string, int, float, an already-built
view, or a thunk** — and that is what `View.child` documents and both backends
guarantee.

For options and booleans, use the constructors that carry the OCaml type
through and render identically on any backend:

```ocaml
View.maybe (fun () -> current_user ()) render   (* instead of a bare option *)
View.show  (fun () -> is_open ()) content        (* instead of a bare bool   *)
```

## Backend trade-offs

| | Melange | js_of_ocaml |
|---|---|---|
| Output | per-module idiomatic ES, tree-shakeable | one linked script incl. OCaml runtime |
| Todo demo, minified | ~23 KB gzipped | several times that — see below |
| DOM/history interop | zero-cost `[@mel.*]` externals | via `Js.Unsafe` |
| Bundler | needs esbuild/vite | none required |
| OCaml ecosystem | melange-compatible libs only | full opam ecosystem, effects, exceptions |

Both demos are measured by CI on every run — minified, and built with
`--profile release` so js_of_ocaml links whole-program and runs its dead-code
elimination. (Dune's `compilation_mode` defaults to `separate` in the dev
profile, which links the whole stdlib; a dev-profile bundle is not a meaningful
size measurement.) The job summary table is the number to trust.

For a fine-grained reactive DOM library, Melange remains the natural primary
target: small output and zero-cost interop. js_of_ocaml is valuable as a
*second* backend — letting full-OCaml apps use Reativa and reach the wider
opam ecosystem.

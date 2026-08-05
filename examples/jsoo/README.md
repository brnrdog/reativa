# js_of_ocaml examples

Two demos built with the **js_of_ocaml** backend instead of the default
Melange one. They reuse the same compiled `reativa` library — the reactive
core, `View`, `Router` and the mlx ppx are backend-agnostic OCaml.

- **todo** — `demo/ui/todo.mlx`, reused verbatim (same markup, same ppx).
- **router_demo** — a small SPA exercising `Router`: links, `pushState`
  navigation, `popstate` and a redirect.

## Run them

```sh
opam install js_of_ocaml js_of_ocaml-compiler   # plus the usual mlx

npm run demo:jsoo               # build both bundles
npm run demo:jsoo:serve         # todo demo   -> http://localhost:8080/
npm run demo:jsoo:router:serve  # router demo -> http://localhost:8080/
npm run demo:jsoo:watch         # rebuild on change; pair with a serve script
```

dune writes `*.bc.js` into `_build`, and the pages load `./todo.bundle.js` /
`./router/router_demo.bundle.js`, so `scripts/copy-jsoo-bundles.mjs` copies the
bundles next to their `index.html`.

The demos are gated behind `REATIVA_JSOO=enabled`, so a plain `dune build` or
`dune test` never requires js_of_ocaml to be installed. CI builds them in a
dedicated job.

## Choosing the backend

One line in `dune`:

```lisp
(libraries reativa)               ; Melange (the default implementation)
(libraries reativa reativa-jsoo)  ; js_of_ocaml
```

An application picking js_of_ocaml installs that second package
(`opam pin add reativa-jsoo https://github.com/brnrdog/reativa.git`); inside
this repo it is built from source.

Everything the backend has to provide lives in two dune *virtual modules*:
`src/` declares the signatures and each backend ships an implementation.

| Virtual module | Signature | Melange | js_of_ocaml |
|---|---|---|---|
| `Dom` | `src/dom.mli` | `backends/melange/dom.ml` | `backends/jsoo/dom.ml` |
| `History` | `src/history.mli` | `backends/melange/history.ml` | `backends/jsoo/history.ml` |

They satisfy the same `.mli`, so `view.ml` and `router.ml` compile against
either one unchanged. Where Melange uses a zero-cost external:

```ocaml
external push_state : history -> state nullable -> string -> string -> unit
  = "pushState" [@@mel.send]
```

js_of_ocaml goes through `Js.Unsafe`:

```ocaml
let push_state h st title url =
  ignore (Js.Unsafe.meth_call h "pushState" [| ... |])
```

That is the whole porting surface.

## One behavioural difference: bare children

`View.child` — what a bare JSX child goes through — inspects the *JavaScript
representation* of an OCaml value, and the two backends map OCaml to JS
differently:

| Bare child | Melange | js_of_ocaml |
|---|---|---|
| `string`, `int`, `float` | ✓ | ✓ |
| already-built `View.t` | ✓ | ✓ |
| a thunk (`unit -> _`) | ✓ | ✓ |
| `None` | renders nothing | indistinguishable from `0` |
| `bool` | `"boolean"` | indistinguishable from `0` / `1` |

Under js_of_ocaml, `None`, `false` and `0` are the same JavaScript value, so no
runtime check can tell them apart. The supported set of bare children is the
intersection — string, int, float, a view, or a thunk. For options and
booleans, use the constructors that keep the OCaml type:

```ocaml
View.maybe (fun () -> current_user ()) render   (* instead of a bare option *)
View.show  (fun () -> is_open ()) content       (* instead of a bare bool   *)
```

## Trade-offs

| | Melange | js_of_ocaml |
|---|---|---|
| Output | per-module ES, tree-shakeable | one linked script, incl. OCaml runtime |
| Bundler | esbuild or Vite | none |
| DOM interop | zero-cost `[@mel.*]` externals | via `Js.Unsafe` |
| Ecosystem | Melange-compatible libraries | full opam ecosystem |

CI measures both todo bundles on every run, minified and with
`--profile release` so js_of_ocaml links whole-program and eliminates dead
code. Those numbers, in the job summary, are the ones to trust.

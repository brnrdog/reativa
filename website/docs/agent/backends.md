# Backends

## Summary

Reativa compiles with **Melange** (default; ES modules, tree-shaken by a bundler) or **js_of_ocaml** (one self-contained script). Only `Dom`, `History` and `Promise` differ; everything else is shared.

## Rules

1. `(libraries reativa)` selects Melange; `(libraries reativa reativa-jsoo)` selects js_of_ocaml.
2. js_of_ocaml represents `None`, `false` and `0` as the same JS value: bare `bool`/`option` JSX children are unsupported on both backends for that reason.
3. The browser stack limits recursion under js_of_ocaml; the library avoids non-tail-recursive list functions on hot paths.
4. Devtools value previews of booleans read `1`/`0` under js_of_ocaml.

## Patterns

```lisp
; Melange
(melange.emit (target output) (libraries reativa)
 (preprocess (pps reativa.mlx_ppx melange.ppx)) (module_systems es6))
; js_of_ocaml
(executable (name app) (modes js) (libraries reativa reativa-jsoo)
 (preprocess (pps reativa.mlx_ppx)))
```

## Related

resources.md (promises), devtools.md

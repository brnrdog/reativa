# mlx markup and the ppx

## Summary

`.mlx` files hold JSX-like markup. The `reativa.mlx_ppx` ppx infers which values are reactive, generates `createElement` for components, and compiles element trees to templates.

## Availability

All releases; component laziness, templates and helper tracking are new in 2.0.

## Rules

1. Value inference for props and children: a literal is static; an explicit `(fun () -> ...)` is dynamic; an expression with an **eager** read — `Signal.get`, an alias of it (`let get = Signal.get`), or a call to a local helper whose body reads one (`let label () = ... Signal.get x ...`) — is wrapped in a thunk and tracked; reads inside a nested `fun` (handlers, callbacks) are not.
2. Bare children: string/int literals become text; other expressions go through `View.child` (strings, ints, floats, views, thunks).
3. A module with `let component ~a ?b ~children = ...` gets `createElement` generated; the tag runs the body lazily (see ownership.md). Props are type-checked; optional props may be omitted.
4. Element trees compile to templates: one HTML skeleton per distinct tree, cloned per instance; dynamic parts become holes. Attributes render in source order.
5. An element stays on the plain `View.Mlx` path (and becomes a hole) when it has a prop the ppx does not know, or markup the HTML parser would restructure (text in table sections, `<tr>` directly in `<table>`, block elements in `<p>`, `<a>` in `<a>`, `<select>`, `<textarea>`).
6. Every element accepts the typed props of `View.Mlx` (about 110 attributes, 55 events), `attrs=[...]` for anything else, and `ref=`.
7. `-no-templates` (ppx flag) compiles with `View.Mlx` only.

## Patterns

```ocaml
open Reativa
open Reativa.View.Mlx

module Card = struct
  let component ~title ?(tone = "plain") ~children =
    <section className=("card " ^ tone)>
      <h3>(title)</h3>
      (View.fragment children)
    </section>
end

let app =
  <Card title="Tasks" tone="info">
    <p>("Remaining: ") (List.length (Signal.get todos))</p>
    <button disabled=(Signal.get busy) onClick=(fun _ -> save ())>("Save")</button>
  </Card>
```

## Anti-patterns

- `Signal.peek` where an update is expected: peeks stay static.
- A reactive read hidden in a function defined in another module: the ppx only sees helpers in the same file; wrap the call in `(fun () -> ...)`.
- Bare `bool`/`option` children: use `View.show`/`View.maybe`.

## Edge cases

- Shadowed helper names are over-approximated (an extra tracked region, never a missed update).
- Data attributes: `attrs=[View.Attr.data "id" (View.static "x")]`.

## Verify

Compile with `-no-templates` to compare behaviour. reativa-lens shows which DOM nodes each interaction changes.

## Related

views.md, ownership.md, lists.md

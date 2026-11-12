# Views

## Summary

A `View.t` describes DOM nodes. Mounting builds them once; afterwards only **leaves** (reactive text, attributes) and **regions** (parts rebuilt when their reads change) update.

## Availability

All releases. Templates, refs, boundaries, portals and suspense are new in 2.0.

## Rules

1. Values are `'a View.value`: `View.static v` (set once), `View.dynamic f` / `View.signal s` (update in place).
2. Leaves skip DOM writes equal to the last value written.
3. A region (`View.dyn f`, `View.show`, `View.maybe`, `View.for_`, a `View.child` thunk) rebuilds its content wholesale when a read changes; local DOM state inside (focus, scroll) does not survive. Keep regions small; prefer leaves.
4. A region whose old and new content are one text node updates that node in place.
5. `View.child x` accepts strings, ints, floats, views and thunks of those — not options or booleans (js_of_ocaml cannot tell them apart); use `View.maybe`/`View.show`.
6. Elements inside `<svg>` are created in the SVG namespace, `<foreignObject>` switches back.

## API

```ocaml
View.text / int / float : _ View.value -> View.t
View.element : ?attrs:attr list -> ?events:handler list -> string -> View.t list -> View.t
View.fragment : View.t list -> View.t        View.empty : View.t
View.dyn / tracked : (unit -> View.t) -> View.t
View.show : ?fallback:View.t -> (unit -> bool) -> View.t -> View.t
View.maybe : ?fallback:View.t -> (unit -> 'a option) -> ('a -> View.t) -> View.t
View.for_ : (unit -> 'a list) -> ('a -> View.t) -> View.t
View.for_with_key : (unit -> 'a list) -> key:('a -> string) -> ('a Signal.t -> View.t) -> View.t
View.Attr.make / optional / data / toggle / bool_property / ref_ ...
View.On.click / input / change / keydown / submit / on
View.template : View.Template.t -> View.Template.hole list -> View.t
View.mount / mount_by_id / mount_disposable
```

## Patterns

Constructor style (what mlx compiles to, minus templates):

```ocaml
let counter =
  View.button
    ~events:[ View.On.click (fun _ -> Signal.update count succ) ]
    [ View.int (View.signal count) ]
```

## Anti-patterns

- `View.dyn` around a large tree to update one text: use an inline read (a leaf).
- `View.Attr.make "class" (View.static (Signal.get c))`: the read is not tracked; use `View.signal c` or `View.dynamic`.

## Edge cases

- `View.Attr.optional name f` removes the attribute while `f ()` is `None`.
- `value` and `checked` are set as DOM properties (live state), not attributes.

## Verify

Count DOM work with Devtools or reativa-lens: an update should touch only the nodes that display the changed state.

## Related

mlx.md, lists.md, ownership.md

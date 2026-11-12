# Ownership and lifecycle

## Summary

Every reactive thing is created under an **owner** and disposed with it. Components, effect runs, keyed rows, regions, error boundaries, portals and mount roots are owners. `View.on_mount`, `View.on_cleanup` and refs hook into this lifecycle.

## Availability

New in 2.0.

## Rules

1. A component body (`<Card />`, or `View.component f`) runs at mount, untracked, under a new owner disposed with the region that holds it.
2. An effect is an owner for its body; before each re-run, everything the previous run created is disposed.
3. `View.on_cleanup f` runs `f` when the current owner is disposed.
4. `View.on_mount f` runs `f` after the current insertion finished (the nodes are in the document if the mount container is), untracked, under the current owner; not at all if the owner was disposed first. Outside an insertion it runs immediately.
5. A ref (`View.Ref.make ()`) is filled when its element is created and cleared when the element's owner is disposed.
6. `View.mount` lives for the page; `View.mount_disposable c v` returns a function that disposes everything and removes the nodes.

## API

```ocaml
View.component : (unit -> View.t) -> View.t
View.on_mount : (unit -> unit) -> unit
View.on_cleanup : (unit -> unit) -> unit
View.Ref.make : unit -> View.Ref.t
View.Ref.from_callback : (Dom.t -> unit) -> View.Ref.t
View.Ref.current : View.Ref.t -> Dom.t option
View.Attr.ref_ : View.Ref.t -> View.attr      (* or the ref prop in mlx *)
View.mount_disposable : Dom.t -> View.t -> unit -> unit
Owner.active / make / make_child / run / run_in / on_cleanup / dispose / reset
```

## Patterns

```ocaml
module Search = struct
  let component ~query =
    let input = View.Ref.make () in
    View.on_mount (fun () -> Option.iter focus (View.Ref.current input));
    let timer = start_polling query in
    View.on_cleanup (fun () -> stop_polling timer);
    <input ref=input value=(Signal.get query) />
end
```

## Anti-patterns

- Reading the DOM in a component body: nodes do not exist yet; use `on_mount`.
- Creating effects at module top level for things that belong to a component: nothing disposes them.
- Holding a `View.Ref.current` value after its component is gone: it is cleared on dispose.

## Edge cases

- Keyed rows render untracked under their own owner; a row's effects die with the row.
- Owners do not register with their parent; only whoever created one disposes it (`Owner.make_child` is the attached variant).

## Verify

Devtools `leaks ()` lists effects that read nothing; `Signal.subscriber_count` drops to 0 once readers are disposed.

## Related

signals.md, views.md, context.md

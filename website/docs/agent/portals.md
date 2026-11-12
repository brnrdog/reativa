# Portals

## Summary

`View.portal ?target child` renders `child` into `target` (default `<body>`) while it stays owned — and sees context — at the place it was written.

## Availability

New in 2.0.

## Rules

1. The portal's nodes are removed when its owner is disposed (the region containing the portal re-renders or goes away).
2. `Context.use` inside the portal sees the providers around the portal.
3. DOM events bubble through the target's ancestors, not the logical parent.
4. A comment marks the portal's place in the original tree.

## API

```ocaml
View.portal : ?target:Dom.t -> View.t -> View.t
<View.Portal target=el> ... </View.Portal>
```

## Patterns

```ocaml
View.show (fun () -> Signal.get open_) (View.portal <div className="modal">(content)</div>)
```

## Related

context.md, ownership.md

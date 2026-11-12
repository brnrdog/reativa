# Error boundaries

## Summary

`View.error_boundary ~fallback child` renders `child`; if rendering it raises, or an effect below it raises later, the child is replaced by `fallback err reset`.

## Availability

New in 2.0.

## Rules

1. Caught: exceptions while rendering the child (component bodies, nested inserts) and exceptions from effects owned below the boundary.
2. Not caught: exceptions in event handlers (they are not effects), and errors raised by the fallback itself (they go to the next boundary up).
3. `reset ()` disposes the fallback and renders the child again from scratch.
4. With no boundary above, the exception propagates (from `mount` or from the `Signal.set` that triggered it).

## API

```ocaml
View.error_boundary : fallback:(exn -> (unit -> unit) -> View.t) -> View.t -> View.t
<View.ErrorBoundary fallback=(fun err reset -> ...)> child </View.ErrorBoundary>
```

## Patterns

```ocaml
<View.ErrorBoundary fallback=(fun err reset ->
   <div role="alert">
     <p>("Something went wrong: ") (Printexc.to_string err)</p>
     <button onClick=(fun _ -> reset ())>("Retry")</button>
   </div>)>
  <Dashboard />
</View.ErrorBoundary>
```

## Edge cases

- A failing render leaves no partial nodes: what was inserted is removed before the fallback renders.

## Related

ownership.md, resources.md

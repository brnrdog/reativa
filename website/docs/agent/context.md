# Context

## Summary

`Context` passes a value to everything a component renders, without threading it through props. Values live on owners; lookups walk up the owner tree.

## Availability

New in 2.0.

## Rules

1. `Context.make default` creates a context; `Context.use c` returns the nearest provided value, else the default.
2. `Context.provide c v` provides on the active owner (call it in a component body); outside a component it raises `Invalid_argument`.
3. A provider reaches everything its component renders — regions, keyed rows, portals, effects — and never its siblings.
4. Call `Context.use` while rendering (or in an effect created there), not in event handlers: handlers run with no owner and see the default.
5. To share changing state, provide a signal: `Context.make (Signal.make 0)`.

## API

```ocaml
Context.make : 'a -> 'a Context.t
Context.use : 'a Context.t -> 'a
Context.provide : 'a Context.t -> 'a -> unit
Context.provider : 'a Context.t -> 'a -> View.t -> View.t
<Context.Provider context=c value=v> ... </Context.Provider>   (* value is read once *)
```

## Patterns

```ocaml
let theme = Context.make (Signal.make "light")

module ThemeToggle = struct
  let component () =
    let t = Context.use theme in
    <button onClick=(fun _ -> Signal.update t (fun s -> if s = "light" then "dark" else "light"))>
      (Signal.get t)
    </button>
end

let app = Context.provider theme (Signal.make "dark") <ThemeToggle />
```

## Anti-patterns

- `Context.use` in a handler: capture the value in the component body instead.

## Edge cases

- Nested providers of the same context: the nearest wins.

## Related

ownership.md, portals.md

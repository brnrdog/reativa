# Signals, computeds and effects

## Summary

`Signal` holds state, `Computed` derives from it, `Effect` reacts to it. Dependencies are discovered at run time: whatever a computed or effect reads with `Signal.get` during its last run is what it depends on.

## Availability

All releases. 2.0 changed disposal semantics (see Rules 5-6).

## Rules

1. Read with `Signal.get` to depend, `Signal.peek` (or `Signal.untrack f`) not to.
2. A write notifies only if `equals old new` is false (default: physical equality `==`). Pass `~equals:( = )` for structural values that are rebuilt.
3. Effects run synchronously after a write, in dependency-level order: a diamond (`a -> b, a -> c, b+c -> effect`) runs the effect once, never with a stale `b` or `c`.
4. `Signal.batch f` delays notifications until `f` returns; effects run once for all its writes.
5. An effect created while an owner is active is disposed with it; an effect's own body is an owner, reset before each re-run (nested effects from the previous run are gone).
6. An effect disposed while queued never runs again; its cleanup runs exactly once.
7. A computed with no subscribers detaches from its sources and recomputes on its next read.

## API

```ocaml
Signal.make : ?name:string -> ?equals:('a -> 'a -> bool) -> 'a -> 'a Signal.t
Signal.get / peek : 'a Signal.t -> 'a
Signal.set : 'a Signal.t -> 'a -> unit
Signal.update : 'a Signal.t -> ('a -> 'a) -> unit
Signal.batch : (unit -> 'a) -> 'a
Signal.untrack : (unit -> 'a) -> 'a
Signal.subscriber_count : 'a Signal.t -> int
Computed.make : ?name:string -> ?equals:('a -> 'a -> bool) -> (unit -> 'a) -> 'a Signal.t
Computed.dispose : 'a Signal.t -> unit
Effect.run : ?name:string -> (unit -> (unit -> unit) option) -> unit
Effect.run_with_disposer : ?name:string -> (unit -> (unit -> unit) option) -> Effect.disposer   (* { dispose } *)
```

## Patterns

```ocaml
open Reativa

let first = Signal.make "Ada"
let last = Signal.make "Lovelace"
let full = Computed.make (fun () -> Signal.get first ^ " " ^ Signal.get last)

let () =
  Effect.run (fun () ->
    print_endline (Signal.get full);
    None);
  Signal.batch (fun () ->
    Signal.set first "Grace";
    Signal.set last "Hopper")  (* prints once *)
```

A cleanup for resources an effect acquires:

```ocaml
let () =
  Effect.run (fun () ->
    let id = start_timer (Signal.get interval) in
    Some (fun () -> stop_timer id))
```

## Anti-patterns

- Writing a signal inside an effect that reads the same signal: an infinite loop unless `equals` stops it.
- `Signal.get` inside an event handler to "subscribe": handlers are not tracked; read with `get` where you render.
- Rebuilding a record and writing it with default equality when nothing changed: every write notifies. Use `~equals`.

## Edge cases

- A computed read outside any effect still caches: it recomputes only if a dependency changed since.
- `Computed.make` whose function raises: the exception propagates; the enclosing effect's tracking is intact.
- Names (`~name`) only matter to Devtools.

## Verify

`Signal.subscriber_count s` tells whether something still depends on `s` (0 after its readers are disposed). Devtools shows each write, recompute and run (see devtools.md).

## Related

ownership.md, views.md, devtools.md

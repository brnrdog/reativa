# Resources and suspense

## Summary

`Resource.make fetcher` turns a promise-returning function into a signal of `Loading | Ready | Failed`. `View.suspense ~fallback child` shows `fallback` while resources created below are loading.

## Availability

New in 2.0.

## Rules

1. The fetcher runs in an effect: signals it reads **before returning the promise** are dependencies; a change starts a new fetch. Reads after an await (in a `then` callback) are not tracked.
2. A result arriving after a newer fetch started, or after the resource's owner was disposed, is dropped.
3. `Loading (Some v)` carries the previous value while refetching.
4. A rejection that is not an OCaml exception becomes `Promise.Rejected message`.
5. Promises are the backend's own: Melange `Js.Promise.t` values and js_of_ocaml JS promises are both `'a Promise.t` (pass them with the backend's FFI; `Promise.resolve`/`reject` build them in OCaml).
6. Suspense renders the child immediately (out of the document) and moves it into place when nothing is pending; effects and on_mount run as usual.

## API

```ocaml
type 'a Resource.state = Loading of 'a option | Ready of 'a | Failed of exn
Resource.make : (unit -> 'a Promise.t) -> 'a Resource.t
Resource.state / peek : 'a Resource.t -> 'a Resource.state
Resource.refetch : 'a Resource.t -> unit
Resource.mutate : 'a Resource.t -> 'a -> unit
Resource.value : 'a state -> 'a option
Resource.is_loading : 'a state -> bool
Resource.error : 'a state -> exn option
View.suspense : fallback:View.t -> View.t -> View.t
<View.Suspense fallback=(...)> ... </View.Suspense>
```

## Patterns

```ocaml
let user_id = Signal.make 1
let user = Resource.make (fun () -> fetch_user (Signal.get user_id))

let profile =
  <View.Suspense fallback=(<p>("Loading…")</p>)>
    (match Resource.state user with
     | Resource.Ready u -> <h2>(u.name)</h2>
     | Failed e -> <p>("Error: ") (Printexc.to_string e)</p>
     | Loading _ -> View.empty)
  </View.Suspense>
```

## Anti-patterns

- Reading a dependency inside the promise chain: it is not tracked; read it first.
- Creating a resource in a frequently re-rendered region: each render starts a fetch; create it in a component body or at top level.

## Related

error-boundaries.md, backends.md

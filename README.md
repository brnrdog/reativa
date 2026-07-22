# reativa

Experimental UI library for building reactive user interfaces for the web with
**OCaml** and **Melange**.

reativa is powered by fine-grained signals and inspired by
[xote](https://github.com/brnrdog/xote) and
[rescript-signals](https://github.com/brnrdog/rescript-signals). Views mount
real DOM nodes once, then update only the text, attributes and regions that
depend on changing signals. There is no virtual DOM.

```ocaml
open Reativa
open Reativa.View.Mlx

let count = Signal.make 0
let doubled = Computed.make (fun () -> Signal.get count * 2)

let () =
  View.mount_by_id "app"
    <section>
      <p>(Signal.get doubled)</p>
      <button onClick=(fun _ -> Signal.update count (fun n -> n + 1))>
        ("+1")
      </button>
    </section>
```

## Core APIs

The signal graph is plain OCaml. The view layer targets the browser through
Melange and can be written with constructors or `.mlx` JSX-like syntax.

### Signal

`Signal.t` is mutable reactive state. Use `get` inside computeds, effects and
dynamic views to track reads. Use `peek` when you need the current value without
creating a dependency.

```ocaml
open Reativa

let count = Signal.make 0

let current = Signal.peek count

let () =
  Signal.set count 1;
  Signal.update count (fun n -> n + 1)
```

Batch multiple writes into one flush:

```ocaml
let first_name = Signal.make ""
let last_name = Signal.make ""

Signal.batch (fun () ->
  Signal.set first_name "Ada";
  Signal.set last_name "Lovelace")
```

### Computed

`Computed.make` creates a lazy derived signal. It tracks every `Signal.get`
called while computing and refreshes when one of those dependencies changes.

```ocaml
let count = Signal.make 2

let doubled =
  Computed.make (fun () -> Signal.get count * 2)

let label =
  Computed.make (fun () ->
    "Count: " ^ string_of_int (Signal.get count))

let () =
  Signal.set count 10;
  assert (Signal.peek doubled = 20)
```

Use `~equals` to prevent downstream work when the derived value is unchanged:

```ocaml
let parity =
  Computed.make ~equals:( = ) (fun () -> Signal.get count mod 2)
```

### Effect

`Effect.run` runs immediately and then re-runs whenever a tracked read changes.
Return `Some cleanup` when work needs to be cleaned up before the next run.

```ocaml
let count = Signal.make 0

let () =
  Effect.run (fun () ->
    Printf.printf "count changed: %d\n" (Signal.get count);
    None)
```

Use `run_with_disposer` when you need to stop an effect manually:

```ocaml
let disposer =
  Effect.run_with_disposer (fun () ->
    ignore (Signal.get count);
    Some (fun () -> print_endline "cleanup"))

let () = disposer.dispose ()
```

### View

The view layer mounts real DOM nodes once. Static values are created once;
dynamic text, attributes and regions update through effects.

Constructor-style views use explicit value wrappers:

```ocaml
let counter count =
  View.button
    ~attrs:[ View.Attr.className (View.static "counter-button") ]
    ~events:[ View.On.click (fun _ -> Signal.update count (fun n -> n + 1)) ]
    [ View.text (View.dynamic (fun () -> "Count " ^ string_of_int (Signal.get count))) ]
```

In `.mlx` files, JSX props and `View.text`, `View.int` and `View.float` infer
their wrapper — including automatic tracking of signal reads. Write
`Signal.get` inline and the text or attribute updates in place; no manual
thunking needed:

```ocaml
open Reativa
open Reativa.View.Mlx

let count = Signal.make 0

let counter =
  <button
    className=(if Signal.get count > 0 then "counter-button on" else "counter-button")
    onClick=(fun _ -> Signal.update count (fun n -> n + 1))
  >
    ("Count " ^ string_of_int (Signal.get count))
  </button>
```

The inference rules are:

- An expression that reads a signal eagerly (`Signal.get` outside a `fun`) is
  auto-thunked into a `dynamic` value, so it tracks its reads and updates in
  place.
- An explicit thunk `(fun () -> ...)` stays a `dynamic` value, as before.
- `Signal.peek` does not count as a read — peek-only expressions stay static,
  matching peek's untracked semantics.
- Reads inside a nested `fun` (an event handler, a callback passed to a
  helper) are not eager and are left alone.
- Anything else becomes a `static` value, created once.

Children need no value components at all — `View.text`, `View.int` and
`View.float` are optional. Literals, plain values, inline signal reads and
thunks all render directly:

```ocaml
let hello user =
  <p>
    ("Hello, ")           (* literal: a static text leaf *)
    (user.name)           (* plain value: rendered via View.child *)
    (" — count ")
    (Signal.get count)    (* signal read: a tracked leaf, updates in place *)
  </p>
```

Literals are wrapped at compile time. Everything else goes through
`View.child`, xote-style runtime coercion on the Melange representation:
strings render as text, numbers and booleans render via JS `String`, a
function is treated as a tracked thunk whose result is re-coerced when its
signal reads change, `None` renders nothing, and already-built views pass
through untouched. Nested elements and explicit `View.*` calls skip the
coercion and stay fully typed.

The runtime coercion applies inside HTML element tags. Component tags
(`<Router>`, `<View.Show>`, ...) only auto-wrap literals — their children are
not necessarily views (a `<Router>`'s children are routes), so non-literal
children keep their own types there.

For a whole region whose *structure* depends on signals, `View.tracked`
rebuilds its children whenever any signal read while building them changes
(the runtime equivalent of xote's `View.tracked`):

```ocaml
let panel =
  View.tracked (fun () ->
    if Signal.get logged_in then <p>("Welcome back")</p> else <p>("Sign in")</p>)
```

Prefer inline reads for text and attributes — they update the exact DOM node —
and reach for `View.tracked` (or `View.Show`/`View.Maybe`) only when the
subtree shape itself changes.

Use `View.Show` for conditional rendering:

```ocaml
<section>
  <View.Show
    condition=(Signal.get count > 0)
    fallback=(<p>("Hidden")</p>)
  >
    <p>("Visible")</p>
  </View.Show>
</section>
```

Use `View.Maybe` to render the `Some` branch of an option:

```ocaml
let selected : string option Signal.t = Signal.make None

let selected_view =
  <View.Maybe
    value=(Signal.get selected)
    fallback=(<p>("Nothing selected")</p>)
    render=(fun value ->
      <p>(value)</p>)
  />
```

Use `View.ForEach` for JSX list rendering. Add `key` to reconcile rows by
identity while keeping DOM order tied to the source list order:

```ocaml
type todo = { id : int; title : string; completed : bool }

let todos : todo list Signal.t = Signal.make []

let list =
  <ul>
    <View.ForEach
      items=(Signal.get todos)
      key=(fun todo -> string_of_int todo.id)
      render=(fun todo ->
        <li className="todo-row">
          (todo.title)
        </li>)
    />
  </ul>
```

Capitalized MLX tags can reference module components. Define `component` inside
a module, then use the module name as a tag:

```ocaml
module Greeting = struct
  let component = fun ~name ->
    <h2>
      ("Greetings ")
      (name)
    </h2>
end

let main = fun () ->
  <Greeting name="OCaml" />
```

For reactive values stored in variables before passing them to JSX, keep using
`static`, `dynamic` or `signal` explicitly; inference is syntax-based, so a
read hidden behind a variable or a cross-module helper is not detected.

### Router

`Router` provides the small pieces needed for browser SPA navigation:
a reactive location signal, `history.pushState` / `replaceState` wrappers,
back/forward helpers, link interception, redirects and route matching. In MLX,
open `Reativa` and use the `Router`, `Route`, `Link` and `Redirect` primitives:

```ocaml
open Reativa
open Reativa.View.Mlx

let app =
  <main>
    <nav>
      <Link href="/">("Home")</Link>
      <Link href="/users/42">("Ada")</Link>
    </nav>

    <Router>
      <Route path="/">
        <h1>("Home")</h1>
      </Route>

      <Route
        path="/users/:id"
        render=(fun matched ->
          <h1>
            ("User " ^ Option.value ~default:"" (Router.param matched "id"))
          </h1>)
      />

      <Route path="/old">
        <Redirect to_="/" />
      </Route>
    </Router>
  </main>
```

Constructor-style code can use the same underlying functions:
`Router.route`, `Router.outlet`, `Router.link` and `Router.redirect`.

Use `Router.location ()` when you need the current browser location as a
signal. Programmatic navigation accepts optional history state:

```ocaml
let details_state = Router.state {| opened from dashboard |}

Router.navigate ~state:details_state "/details" ();

match (Signal.peek (Router.location ())).state with
| Some state -> Router.state_value state
| None -> "no state"
```

## Build, test, demo

```sh
opam install . --deps-only --with-test
npm install

opam exec -- dune test
npm run demo
npm run demo:serve
npm run docs:dev
```

For the demo development loop, run `npm run demo:watch` in one terminal and
`npm run demo:serve` in another. The server injects a small reload client and
refreshes the browser when rebuilt demo files change.

## License

MIT © Bernardo Gurgel

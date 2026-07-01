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
      <p>(View.int (signal doubled))</p>
      <button onClick=(fun _ -> Signal.update count (fun n -> n + 1))>
        (View.text "+1")
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
their wrapper. Plain values become static values, and inline thunks become
dynamic values:

```ocaml
open Reativa
open Reativa.View.Mlx

let count = Signal.make 0

let counter =
  <button
    className="counter-button"
    onClick=(fun _ -> Signal.update count (fun n -> n + 1))
  >
    (View.text (fun () -> "Count " ^ string_of_int (Signal.get count)))
  </button>
```

Use `View.Show` for conditional rendering:

```ocaml
<section>
  <View.Show
    condition=(fun () -> Signal.get count > 0)
    fallback=(<p>(View.text "Hidden")</p>)
  >
    <p>(View.text "Visible")</p>
  </View.Show>
</section>
```

Use `View.Maybe` to render the `Some` branch of an option:

```ocaml
let selected : string option Signal.t = Signal.make None

let selected_view =
  <View.Maybe
    value=(fun () -> Signal.get selected)
    fallback=(<p>(View.text "Nothing selected")</p>)
    render=(fun value ->
      <p>(View.text value)</p>)
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
      items=(fun () -> Signal.get todos)
      key=(fun todo -> string_of_int todo.id)
      render=(fun todo ->
        <li className="todo-row">
          (View.text todo.title)
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
      (View.text "Greetings ")
      (View.text name)
    </h2>
end

let main = fun () ->
  <Greeting name="OCaml" />
```

For reactive values stored in variables before passing them to JSX, keep using
`static`, `dynamic` or `signal` explicitly; inference is syntax-based.

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

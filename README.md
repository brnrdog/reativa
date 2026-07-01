# reativa

Experimental UI library for building reactive browser interfaces with
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

## What is included

- **`Signal`**: mutable reactive state.
- **`Computed`**: lazy derived values with dependency tracking.
- **`Effect`**: tracked side effects with optional cleanup.
- **`View`**: DOM view constructors and control flow helpers.
- **`.mlx` syntax**: JSX-like syntax for `Reativa.View`, parsed by
  `ocaml-mlx/mlx`.

The signal graph and scheduler are plain OCaml. `View` and `Dom` target the
browser through Melange.

## View basics

Views can be written with constructors:

```ocaml
View.button
  ~events:[ View.On.click (fun _ -> Signal.update count (fun n -> n + 1)) ]
  [ View.text (View.static "+1") ]
```

Or with mlx syntax in a `.mlx` file:

```ocaml
open Reativa
open Reativa.View.Mlx

<button onClick=(fun _ -> Signal.update count (fun n -> n + 1))>
  (View.int (signal count))
</button>
```

In `.mlx` files, JSX props and `View.text`, `View.int` and `View.float` infer
their value wrapper. Plain values become static values, and thunks become
dynamic values:

```ocaml
<input
  className="todo-input"
  value=(fun () -> Signal.get draft)
/>
```

For constructor-style code outside `.mlx`, use `View.static`, `View.dynamic` or
`View.signal` explicitly. Useful helpers also include `dyn`, `show`, `maybe`,
`for_`, `Attr`, `On`, `mount` and `mount_by_id`.

Inference is syntax-based, so use an inline thunk for reactive JSX values. If a
thunk is stored in a variable first, keep the explicit `dynamic` wrapper.

Capitalized mlx tags can reference module components. Define `component` inside
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

Use `View.forWithKey` when rendering a list with stable, unique string keys.
Rows are reconciled by key and the row renderer receives a signal containing
the latest item for that key:

```ocaml
View.forWithKey
  (fun () -> Signal.get todos)
  ~key:(fun todo -> string_of_int todo.id)
  (fun todo ->
    <li>(View.text (fun () -> (Signal.get todo).title))</li>)
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

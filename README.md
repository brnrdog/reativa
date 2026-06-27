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

let count = Signal.make 0
let doubled = Computed.make (fun () -> Signal.get count * 2)

let () =
  View.mount_by_id "app"
    [%reativa.jsx
      {|
      <section>
        <p>{View.dyn_int (fun () -> Signal.get doubled)}</p>
        <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>
          +1
        </button>
      </section>
      |}]
```

## What is included

- **`Signal`**: mutable reactive state.
- **`Computed`**: lazy derived values with dependency tracking.
- **`Effect`**: tracked side effects with optional cleanup.
- **`View`**: DOM view constructors and control flow helpers.
- **`[%reativa.jsx]`**: experimental JSX-like syntax for `Reativa.View`.

The signal graph and scheduler are plain OCaml. `View` and `Dom` target the
browser through Melange.

## View basics

Views can be written with constructors:

```ocaml
View.button
  ~events:[ View.On.click (fun _ -> Signal.update count (fun n -> n + 1)) ]
  [ View.text "+1" ]
```

Or with the JSX-like PPX:

```ocaml
[%reativa.jsx
  {|
  <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>
    {View.dyn_int (fun () -> Signal.get count)}
  </button>
  |}]
```

Useful helpers include `dyn_text`, `dyn_int`, `dyn`, `show`, `maybe`, `for_`,
`Attr`, `On`, `mount` and `mount_by_id`.

## Build, test, demo

```sh
opam install . --deps-only --with-test
npm install

opam exec -- dune test
npm run demo
npm run demo:serve
npm run docs:dev
```

## License

MIT © Bernardo Gurgel

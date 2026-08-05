<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo.svg" alt="reativa" width="340">
  </picture>
</p>

UI library for building reactive user interfaces for the web with **OCaml** or
**ReasonML**, compiling to JavaScript through **Melange** or **js_of_ocaml**.

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

The signal graph is plain OCaml. The view layer reaches the browser through a
pluggable backend (see [Backends](#backends)) and can be written with
constructors or `.mlx` JSX-like syntax.

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
    (View.text ("Count " ^ string_of_int (Signal.get count)))
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
`View.child`, xote-style runtime coercion: strings render as text, numbers
render via JS `String`, a function is treated as a tracked thunk whose result
is re-coerced when its signal reads change, and already-built views pass
through untouched. Nested elements and explicit `View.*` calls skip the
coercion and stay fully typed.

Bare children are guaranteed on every backend for **string, int, float, an
already-built view, or a thunk**. Options and booleans are not: js_of_ocaml
represents `None`, `false` and `0` as the same JavaScript value, so no runtime
check can recover them. Use `View.Maybe` and `View.Show` (below), which carry
the OCaml type through and render identically on both backends.

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
      <Link href="/">(View.text "Home")</Link>
      <Link href="/users/42">(View.text "Ada")</Link>
    </nav>

    <Router>
      <Route path="/">
        <h1>(View.text "Home")</h1>
      </Route>

      <Route
        path="/users/:id"
        render=(fun matched ->
          <h1>
            (View.text ("User " ^ Option.value ~default:"" (Router.param matched "id")))
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

## Backends

The reactive core, `View`, `Router` and the mlx JSX ppx are plain OCaml. Only
the browser FFI is backend-specific, and it lives behind two dune *virtual
modules* — `Dom` and `History` — so Reativa compiles to JavaScript through
either of two backends:

| Backend | Select with | Output |
|---|---|---|
| [Melange](https://melange.re) (default) | `(libraries reativa)` | per-module, tree-shakeable ES modules; bundle with esbuild/vite |
| [js_of_ocaml](https://ocsigen.org/js_of_ocaml) | `(libraries reativa reativa-jsoo)` | one self-contained script, no bundler, full opam ecosystem |

Melange is the default, and the reason is size: it emits per-module ES that a
bundler tree-shakes, and it ships no OCaml runtime. js_of_ocaml links the OCaml
runtime and every reachable module into one script, so it starts from a fixed
floor Melange never pays — the Melange todo demo minifies to roughly 23 KB
gzipped, and js_of_ocaml's is several times that.

CI builds the same todo demo both ways on every run, minified and in the
release profile, and prints both numbers to the job summary — that table is the
source of truth rather than figures pasted here.

js_of_ocaml is the right choice for an app that is already js_of_ocaml, or that
needs opam packages Melange cannot consume — the runtime is a fixed cost that
stops mattering as the app grows. Nothing else changes between the two: the
same JSX, the same `View` and `Router`, the same compiled core library.

To use js_of_ocaml, install the extra package and name it in `dune`:

```sh
opam install reativa-jsoo
```

```lisp
(executables
 (names app)
 (modes js)
 (libraries reativa reativa-jsoo)
 (preprocess (pps reativa.mlx_ppx)))
```

Note that the Melange backend ships inside the `reativa` package rather than
its own, so Melange is a dependency of the core even for a js_of_ocaml build.
That is a dune constraint, not a choice: an implementation of a virtual library
links against the virtual library's Melange-mode artifacts instead of producing
them, so the core has to be built in Melange mode to be usable by the Melange
backend at all.

See [`examples/jsoo/`](examples/jsoo/) for the same demos built both ways, and
for the one place where the two backends genuinely differ (`View.child`).

## Playground

Write a component, compile it and watch it mount — without setting up a
project:

```sh
opam install . --deps-only --with-test
npm install

npm run playground
```

The dev server opens the playground at `/reativa/playground/`. Each run writes
the editor buffer to a scratch dune project and builds it with the backend
picked in the toolbar — the same source, compiled both ways, which is the point
of [Backends](#backends) made touchable: Melange emits ES modules that are
bundled and imported into the preview frame, js_of_ocaml links one
self-contained script the frame runs as a plain `<script>`. The status line
reports which backend ran and how large its output was (dev profile,
unminified — CI's release-profile table is still the number that counts). When
the build fails, the compiler's own message comes back in place of the preview.

The js_of_ocaml option needs its package, exactly as an application would:

```sh
opam install reativa-jsoo js_of_ocaml
```

Programs are complete `.mlx` modules that end in `View.mount_by_id "app"`, and
the preview frame ships a small stylesheet (`.card`, `.row`, `.list`, `.value`,
`.muted`, plus the usual form controls) so short examples look finished. Press
<kbd>⌘</kbd>/<kbd>Ctrl</kbd> + <kbd>Enter</kbd> to run, and use *Share* to copy
a link — the program and the backend travel in the URL fragment.

Compiling needs the OCaml toolchain, so the playground published with the docs
site is read-only: it shows the examples but cannot run edits.

## Build, test, demo

```sh
opam install . --deps-only --with-test
npm install

opam exec -- dune test
npm run demo
npm run demo:serve
npm run docs:dev
npm run playground
```

For the demo development loop, run `npm run demo:watch` in one terminal and
`npm run demo:serve` in another. The server injects a small reload client and
refreshes the browser when rebuilt demo files change.

## License

MIT © Bernardo Gurgel

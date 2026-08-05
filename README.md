<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img src="assets/logo.svg" alt="reativa" width="340">
  </picture>
</p>

<p align="center">
  Reactive user interfaces for the web in <b>OCaml</b> and <b>ReasonML</b>,
  powered by fine-grained signals.
</p>

<p align="center">
  <a href="https://brnrdog.github.io/reativa/">Documentation</a> ·
  <a href="https://brnrdog.github.io/reativa/playground/">Playground</a> ·
  <a href="examples/jsoo/">Examples</a>
</p>

Views mount real DOM nodes once, then update only the text, attributes and
regions that read a changed signal. There is no virtual DOM and no diffing.
The same code compiles to JavaScript through [Melange](https://melange.re) or
[js_of_ocaml](https://ocsigen.org/js_of_ocaml).

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

## Install

```sh
opam pin add reativa https://github.com/brnrdog/reativa.git
```

Then name the library in `dune`, and enable the `mlx` dialect in
`dune-project` if you want JSX-like markup:

```lisp
; dune-project
(using melange 0.1)

(dialect
 (name mlx)
 (implementation
  (extension mlx)
  (merlin_reader mlx)
  (preprocess (run mlx-pp %{input-file}))))
```

```lisp
; dune
(melange.emit
 (target output)
 (modules app)
 (libraries reativa)
 (preprocess (pps reativa.mlx_ppx melange.ppx)))
```

The [Get started](https://brnrdog.github.io/reativa/#start) section of the docs
walks through the same steps in OCaml and in ReasonML.

## Concepts

Five modules live under the `Reativa` namespace. The signal graph is plain
OCaml — it runs and tests natively — and only the `View` and `Router` layers
touch the browser. The full reference is on the
[docs site](https://brnrdog.github.io/reativa/#api).

### Signal

Mutable reactive state. `get` tracks a dependency, `peek` reads without
tracking, and `batch` groups writes into a single flush.

```ocaml
let count = Signal.make 0

let () =
  Signal.set count 1;
  Signal.update count (fun n -> n + 1);
  Signal.batch (fun () -> Signal.set count 0)
```

### Computed

Lazy derived state. It tracks every `Signal.get` made while computing and
refreshes when one of those dependencies changes. Pass `~equals` to stop
downstream work when the derived value is unchanged.

```ocaml
let doubled = Computed.make (fun () -> Signal.get count * 2)
let parity = Computed.make ~equals:( = ) (fun () -> Signal.get count mod 2)
```

### Effect

Runs immediately, then re-runs whenever a tracked read changes. Return
`Some cleanup` to undo work before the next run; use `run_with_disposer` to
stop an effect by hand.

```ocaml
let () =
  Effect.run (fun () ->
    Printf.printf "count: %d\n" (Signal.get count);
    None)
```

### View

Views build DOM nodes once. In `.mlx` files, JSX props and children infer
whether they are static or reactive, so an inline `Signal.get` updates that
exact node:

```ocaml
let counter =
  <button
    className=(if Signal.get count > 0 then "counter on" else "counter")
    onClick=(fun _ -> Signal.update count (fun n -> n + 1))
  >
    ("Count ") (Signal.get count)
  </button>
```

The inference rules are:

- An eager signal read (a `Signal.get` outside a `fun`) becomes a tracked
  `dynamic` value that updates in place.
- An explicit thunk `(fun () -> ...)` stays `dynamic`.
- `Signal.peek` is untracked, so peek-only expressions stay `static`.
- Reads inside a nested `fun` — an event handler, a callback — are left alone.
- Anything else is `static`, created once.

Bare children work for **string, int, float, an already-built view, or a
thunk**. Options and booleans are not in that set: under js_of_ocaml `None`,
`false` and `0` share one JavaScript representation, so use `View.Maybe` and
`View.Show`, which carry the OCaml type through and behave the same on both
backends.

```ocaml
<View.Show condition=(fun () -> Signal.get count > 0) fallback=(<p>("Hidden")</p>)>
  <p>("Visible")</p>
</View.Show>

<View.ForEach
  items=(fun () -> Signal.get todos)
  key=(fun todo -> string_of_int todo.id)
  render=(fun todo -> <li>(todo.title)</li>)
/>
```

When the *structure* of a region depends on a signal, wrap it in
`View.tracked`; for text and attributes, prefer inline reads, which patch the
node itself.

Constructor-style views are always available and take explicit wrappers —
`View.static` / `View.dynamic` — which is what the ppx emits:

```ocaml
View.button
  ~events:[ View.On.click (fun _ -> Signal.update count (fun n -> n + 1)) ]
  [ View.text (View.dynamic (fun () -> string_of_int (Signal.get count))) ]
```

### Router

Client-side routing: a reactive location signal, `pushState` / `replaceState`
wrappers, link interception, redirects and route matching.

```ocaml
<main>
  <nav>
    <Link href="/">("Home")</Link>
    <Link href="/users/42">("Ada")</Link>
  </nav>

  <Router>
    <Route path="/"><h1>("Home")</h1></Route>
    <Route
      path="/users/:id"
      render=(fun matched ->
        <h1>("User " ^ Option.value ~default:"" (Router.param matched "id"))</h1>)
    />
    <Route path="/old"><Redirect to_="/" /></Route>
  </Router>
</main>
```

`Router.navigate` moves programmatically and accepts optional history state;
`Router.location ()` exposes the current location as a signal. The
constructor-style equivalents are `Router.route`, `Router.outlet`,
`Router.link` and `Router.redirect`.

## Backends

The reactive core, `View`, `Router` and the mlx ppx are plain OCaml. Only the
browser FFI is backend-specific: it sits behind two dune virtual modules,
`Dom` and `History`, so picking a backend is a line in `dune`.

| Backend | Select with | Output |
|---|---|---|
| [Melange](https://melange.re) (default) | `(libraries reativa)` | per-module ES modules, tree-shakeable; bundle with esbuild or Vite |
| [js_of_ocaml](https://ocsigen.org/js_of_ocaml) | `(libraries reativa reativa-jsoo)` | one self-contained script, no bundler, full opam ecosystem |

Melange is the default because of output size: it ships no OCaml runtime, so a
bundler can tree-shake what is left. js_of_ocaml links the runtime and every
reachable module into a single script — a fixed cost that matters less as an
app grows, and the right trade for an app that is already js_of_ocaml or needs
opam packages Melange cannot consume. CI measures both bundles on every run and
prints the numbers to the job summary.

The js_of_ocaml backend ships as a second package, pinned from the same repo:

```sh
opam pin add reativa-jsoo https://github.com/brnrdog/reativa.git
```

Note that `reativa-jsoo` still depends on `reativa`, which carries the Melange
backend — dune requires the core to be built in Melange mode for the default
implementation to link against it.

See [`examples/jsoo/`](examples/jsoo/) for the same demos built both ways.

## Development

```sh
opam install . --deps-only --with-test
npm install
```

| Command | What it does |
|---|---|
| `opam exec -- dune test` | native test suite (signals, router, ppx) |
| `npm run demo` + `npm run demo:serve` | build and serve the Melange todo demo |
| `npm run demo:watch` | rebuild the demo on change (pair with `demo:serve`) |
| `npm run demo:jsoo` | build the js_of_ocaml demos — see [`examples/jsoo/`](examples/jsoo/) |
| `npm run docs:dev` | run the documentation site locally |
| `npm run playground` | open the playground and compile from the browser |

The docs site and the playground live in [`website/`](website/), which has its
own [README](website/README.md).

Commits follow [Conventional Commits](https://www.conventionalcommits.org/) —
commitlint enforces it on commit, and releases are cut by semantic-release.

## License

MIT © Bernardo Gurgel

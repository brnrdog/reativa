open Reativa

let code_block title code =
  [%reativa.jsx
    {|
    <figure class="code-block">
      <figcaption>{View.text title}</figcaption>
      <pre><code>{View.text code}</code></pre>
    </figure>
    |}]

let definition name text =
  [%reativa.jsx
    {|
    <div class="definition">
      <dt><code>{View.text name}</code></dt>
      <dd>{View.text text}</dd>
    </div>
    |}]

let metric label value =
  [%reativa.jsx
    {|
    <div class="metric">
      <span>{View.text label}</span>
      <strong>{View.dyn_text value}</strong>
    </div>
    |}]

let () =
  let count = Signal.make 2 in
  let doubled = Computed.make (fun () -> Signal.get count * 2) in
  let parity =
    Computed.make (fun () -> if Signal.get count mod 2 = 0 then "even" else "odd")
  in

  let signal_code =
    "let count = Signal.make 0\n\
     let doubled = Computed.make (fun () -> Signal.get count * 2)\n\n\
     let () = Signal.update count (fun n -> n + 1)"
  in
  let view_code =
    "View.mount_by_id \"app\"\n\
     \  [%reativa.jsx {|\n\
     \    <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>\n\
     \      {View.dyn_int (fun () -> Signal.get count)}\n\
     \    </button>\n\
     \  |}]"
  in
  let dune_code =
    "(melange.emit\n\
     \ (target output)\n\
     \ (libraries reativa)\n\
     \ (preprocess\n\
     \  (pps melange.ppx reativa_jsx_ppx))\n\
     \ (module_systems es6))"
  in

  View.mount_by_id
    "app"
    [%reativa.jsx
      {|
      <div class="page">
        <header class="topbar">
          <a class="brand" href="#top">reativa</a>
          <nav class="topnav" aria-label="Primary">
            <a href="#quickstart">Quickstart</a>
            <a href="#api">API</a>
            <a href="#views">Views</a>
            <a href="#background">Background</a>
            <a href="https://github.com/brnrdog/reativa">GitHub</a>
          </nav>
        </header>

        <div id="top" class="layout">
          <aside class="toc" aria-label="Table of contents">
            <p>On this page</p>
            <a href="#quickstart">Quickstart</a>
            <a href="#api">API overview</a>
            <a href="#views">Reactive views</a>
            <a href="#background">Background</a>
          </aside>

          <main class="content">
            <section class="intro">
              <p class="kicker">OCaml UI, powered by signals</p>
              <h1>Reativa documentation</h1>
              <p>
                Reativa is an experimental UI library for building browser
                interfaces with OCaml and Melange. It is based on xote and
                rescript-signals: views are real DOM nodes, and signals drive
                the parts that change.
              </p>
            </section>

            <section id="quickstart" class="doc-section">
              <h2>Quickstart</h2>
              <p>
                Install the opam and npm dependencies, then run the docs server
                or build the demo.
              </p>
              <pre class="command"><code>opam install . --deps-only --with-test
npm install
npm run docs:dev</code></pre>

              <div class="example">
                <div>
                  <h3>Small reactive example</h3>
                  <p>
                    The number below is a signal. The derived values are
                    computeds. Clicking a button updates only the dependent text.
                  </p>
                </div>
                <div class="example-box">
                  <p class="counter">{View.dyn_int (fun () -> Signal.get count)}</p>
                  <div class="metrics">
                    {metric "doubled" (fun () -> string_of_int (Signal.get doubled))}
                    {metric "parity" (fun () -> Signal.get parity)}
                  </div>
                  <div class="example-actions">
                    <button onClick={fun _ -> Signal.update count (fun n -> n - 1)}>-</button>
                    <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>+</button>
                    <button onClick={fun _ -> Signal.set count 2}>reset</button>
                  </div>
                </div>
              </div>
            </section>

            <section id="api" class="doc-section">
              <h2>API overview</h2>
              <p>
                The public package is <code>Reativa</code>. The signal
                primitives can be used directly, and the view layer uses them
                as its update model.
              </p>
              <dl class="definitions">
                {definition "Signal" "Mutable reactive state. Use get to track, peek to read without tracking, and set or update to write."}
                {definition "Computed" "A lazy derived value. It caches until one of the signals it read changes."}
                {definition "Effect" "A tracked side effect. It re-runs when dependencies change and can return cleanup work."}
                {definition "View" "DOM constructors, reactive text and control flow helpers such as dyn, show, maybe and for_."}
                {definition "Dom" "Small Melange bindings used by View and event handlers."}
              </dl>
              {code_block "signals" signal_code}
            </section>

            <section id="views" class="doc-section">
              <h2>Reactive views</h2>
              <p>
                <code>Reativa.View</code> creates DOM nodes directly. Reactive
                text, attributes and dynamic regions are wired to effects.
                <code>[%reativa.jsx]</code> is syntax for the same constructors.
              </p>
              {code_block "view" view_code}
              {code_block "website/src/dune" dune_code}
            </section>

            <section id="background" class="doc-section">
              <h2>Background</h2>
              <p>
                Reativa follows the fine-grained UI model used by
                <a href="https://github.com/brnrdog/xote">xote</a>, and ports the
                signal graph ideas from
                <a href="https://github.com/brnrdog/rescript-signals">rescript-signals</a>
                to idiomatic OCaml. The project is still experimental.
              </p>
            </section>
          </main>
        </div>

        <footer class="footer">
          <span>MIT © Bernardo Gurgel. Experimental API.</span>
        </footer>
      </div>
      |}]

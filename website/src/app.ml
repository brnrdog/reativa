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
            <a href="#concepts">Concepts</a>
            <a href="#views">Views</a>
            <a href="#deploy">Deploy</a>
            <a href="https://github.com/brnrdog/reativa">GitHub</a>
          </nav>
        </header>

        <div id="top" class="layout">
          <aside class="toc" aria-label="Table of contents">
            <p>On this page</p>
            <a href="#quickstart">Quickstart</a>
            <a href="#concepts">Core concepts</a>
            <a href="#views">Reactive views</a>
            <a href="#deploy">Docs site deployment</a>
          </aside>

          <main class="content">
            <section class="intro">
              <p class="kicker">OCaml, Melange, browser UI</p>
              <h1>Reativa documentation</h1>
              <p>
                Reativa is an experimental library for building reactive web
                interfaces in OCaml. The core is a small signal graph. The view
                layer mounts real DOM nodes and updates the parts that depend on
                signal reads.
              </p>
            </section>

            <section id="quickstart" class="doc-section">
              <h2>Quickstart</h2>
              <p>
                Install the opam dependencies, build the Melange target, then
                run the Vite docs server.
              </p>
              <pre class="command"><code>opam install . --deps-only --with-test
npm install
npm run docs:dev</code></pre>

              <div class="example">
                <div>
                  <h3>Small reactive example</h3>
                  <p>
                    The number below is a signal. The derived values are
                    computeds, and only their text nodes update.
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

            <section id="concepts" class="doc-section">
              <h2>Core concepts</h2>
              <p>
                The API is built around three primitives. They can be used on
                their own, or as the state model behind the view layer.
              </p>
              <dl class="definitions">
                {definition "Signal" "Mutable reactive state. Use get to track, peek to read without tracking, and set or update to write."}
                {definition "Computed" "A lazy derived value. It caches until one of the signals it read changes."}
                {definition "Effect" "A tracked side effect. It re-runs when dependencies change and can return cleanup work."}
              </dl>
              {code_block "signals" signal_code}
            </section>

            <section id="views" class="doc-section">
              <h2>Reactive views</h2>
              <p>
                <code>Reativa.View</code> creates DOM nodes directly. Reactive
                text, attributes and dynamic regions are wired to effects. The
                JSX-like PPX is a syntax layer over the same constructors.
              </p>
              {code_block "view" view_code}
              {code_block "website/src/dune" dune_code}
            </section>

            <section id="deploy" class="doc-section">
              <h2>Docs site deployment</h2>
              <p>
                The documentation site lives in <code>website/</code>. Dune emits
                JavaScript through Melange, Vite writes the static output to
                <code>_site/</code>, and GitHub Pages publishes that directory
                from the Pages workflow.
              </p>
              <pre class="command"><code>npm run docs:build</code></pre>
            </section>
          </main>
        </div>

        <footer class="footer">
          <span>MIT © Bernardo Gurgel. Experimental API.</span>
        </footer>
      </div>
      |}]

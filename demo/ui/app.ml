(* Browser demo for the JSX-like PPX surface over the [reativa_ui] View layer.

   The markup below is written with [%reativa.jsx {| ... |}] and lowered by the
   PPX to ordinary [Reativa_ui.View] calls. Expressions inside braces are plain
   OCaml and must return [View.t] for children, event handlers for [on*]
   attributes, or reactive functions for attributes such as [class] and
   [disabled]. *)

open Reativa
open Reativa_ui

type todo = {
  id : int;
  text : string;
  done_ : bool;
}

let todo id text = { id; text; done_ = false }

let trim text = String.trim text

let plural count singular plural =
  if count = 1 then singular else plural

let () =
  let count = Signal.make 2 in
  let step = Signal.make 1 in
  let todos =
    Signal.make
      [
        todo 1 "Write JSX-like markup";
        { (todo 2 "Reset the draft after submit") with done_ = true };
        todo 3 "Show derived state without a virtual DOM";
      ]
  in
  let next_todo_id = Signal.make 4 in
  let draft = Signal.make "" in
  let selected = Signal.make (Some "Everything below is driven by signals") in

  let doubled = Computed.make (fun () -> Signal.get count * 2) in
  let parity = Computed.make (fun () -> if Signal.get count mod 2 = 0 then "even" else "odd") in
  let can_submit = Computed.make (fun () -> String.length (trim (Signal.get draft)) > 0) in
  let completed_count =
    Computed.make (fun () ->
      Signal.get todos |> List.filter (fun item -> item.done_) |> List.length)
  in
  let remaining_count =
    Computed.make (fun () -> List.length (Signal.get todos) - Signal.get completed_count)
  in
  let progress =
    Computed.make (fun () ->
      let total = List.length (Signal.get todos) in
      if total = 0 then 0 else Signal.get completed_count * 100 / total)
  in

  let add_todo ev =
    Dom.prevent_default ev;
    let text = Signal.peek draft |> trim in
    if String.length text > 0 then begin
      let id = Signal.peek next_todo_id in
      Signal.update todos (fun items -> items @ [ todo id text ]);
      Signal.set next_todo_id (id + 1);
      Signal.set draft ""
    end
  in
  let toggle_todo id =
    Signal.update todos (fun items ->
      List.map (fun item -> if item.id = id then { item with done_ = not item.done_ } else item) items)
  in
  let remove_todo id =
    Signal.update todos (fun items -> List.filter (fun item -> item.id <> id) items)
  in
  let clear_done () =
    Signal.update todos (fun items -> List.filter (fun item -> not item.done_) items)
  in
  let reset_demo () =
    Signal.set count 2;
    Signal.set step 1;
    Signal.set draft "";
    Signal.set next_todo_id 4;
    Signal.set selected (Some "Everything below is driven by signals");
    Signal.set todos
      [
        todo 1 "Write JSX-like markup";
        { (todo 2 "Reset the draft after submit") with done_ = true };
        todo 3 "Show derived state without a virtual DOM";
      ]
  in

  let metric label value tone =
    [%reativa.jsx
      {jsx|
      <div class="rounded-lg border border-line bg-white/80 px-4 py-3 shadow-sm">
        <p class="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">{View.text label}</p>
        <p class={fun () -> "mt-1 text-2xl font-semibold tabular-nums " ^ tone}>{View.dyn_text value}</p>
      </div>
      |jsx}]
  in

  let code_block title code =
    [%reativa.jsx
      {|
      <figure class="rounded-xl border border-slate-800 bg-slate-950 p-4 text-slate-100 shadow-sm">
        <figcaption class="mb-3 text-xs font-semibold uppercase tracking-[0.18em] text-slate-400">{View.text title}</figcaption>
        <pre class="overflow-x-auto whitespace-pre text-xs leading-6"><code>{View.text code}</code></pre>
      </figure>
      |}]
  in

  let signals_code =
    "let count = Signal.make 2\n\
     let doubled = Computed.make (fun () -> Signal.get count * 2)\n\
     \n\
     let () =\n\
     \  Effect.run (fun () ->\n\
     \    Js.log (Signal.get doubled);\n\
     \    None)"
  in
  let counter_code =
    "<button onClick={fun _ -> Signal.update count (fun n -> n + Signal.peek step)}>\n\
     \  plus\n\
     </button>\n\
     \n\
     <strong>{View.dyn_int (fun () -> Signal.get count)}</strong>"
  in
  let conditional_code =
    "{View.maybe\n\
     \  ~fallback:(View.text \"No note selected.\")\n\
     \  (fun () -> Signal.get selected)\n\
     \  (fun text -> View.text text)}"
  in
  let todo_code =
    "<form onSubmit={add_todo}>\n\
     \  <input\n\
     \    value={fun () -> Signal.get draft}\n\
     \    onInput={fun ev -> Signal.set draft (Dom.target_value ev)}\n\
     \  />\n\
     </form>\n\
     \n\
     {View.for_ (fun () -> Signal.get todos) todo_row}"
  in

  let todo_row item =
    [%reativa.jsx
      {|
      <li class="group flex items-center gap-3 rounded-lg border border-line bg-white/80 px-3 py-2.5 shadow-sm transition hover:border-slate-300">
        <button
          class={fun () ->
            if item.done_ then
              "grid h-7 w-7 place-items-center rounded-full bg-ink text-xs font-bold text-white"
            else
              "grid h-7 w-7 place-items-center rounded-full border border-slate-300 bg-white text-sm text-slate-400"}
          onClick={fun _ -> toggle_todo item.id}
        >
          {View.text (if item.done_ then "done" else "")}
        </button>
        <span
          class={fun () ->
            if item.done_ then
              "min-w-0 flex-1 text-sm text-slate-400 line-through"
            else
              "min-w-0 flex-1 text-sm font-medium text-slate-800"}
        >
          {View.text item.text}
        </span>
        <button
          class="rounded-md px-2 py-1 text-xs font-medium text-slate-400 transition hover:bg-slate-100 hover:text-slate-700"
          onClick={fun _ -> remove_todo item.id}
        >
          remove
        </button>
      </li>
      |}]
  in

  View.mount_by_id
    "app"
    [%reativa.jsx
      {jsx|
      <main class="mx-auto flex min-h-screen w-full max-w-6xl flex-col gap-8 px-5 py-10 sm:px-8 lg:px-10">
        <header class="grid gap-6 lg:grid-cols-[1.25fr_0.75fr] lg:items-end">
          <div>
            <p class="text-sm font-semibold uppercase tracking-[0.24em] text-muted">reativa view</p>
            <h1 class="mt-3 max-w-3xl text-4xl font-semibold leading-tight tracking-tight text-ink sm:text-5xl">
              JSX-like markup, compiled to fine-grained views.
            </h1>
            <p class="mt-4 max-w-2xl text-base leading-7 text-slate-600">
              This demo keeps the JSX surface and the runtime deliberately small:
              static nodes are created once, reactive text updates in place, and
              dynamic regions are driven by signals.
            </p>
          </div>
          <aside class="rounded-xl border border-line bg-white/80 p-4 shadow-soft">
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">PPX sample</p>
            <code class="mt-3 block overflow-x-auto rounded-lg bg-slate-950 px-3 py-3 text-xs leading-6 text-slate-100">
              [%reativa.jsx "... button onClick handler ..."]
            </code>
          </aside>
        </header>

        <section class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {metric "count" (fun () -> string_of_int (Signal.get count)) "text-ink"}
          {metric "doubled" (fun () -> string_of_int (Signal.get doubled)) "text-slate-700"}
          {metric "parity" (fun () -> Signal.get parity) "text-slate-700"}
          {metric "todos left" (fun () -> string_of_int (Signal.get remaining_count)) "text-slate-700"}
        </section>

        <section class="grid gap-6 rounded-2xl border border-line bg-white p-5 shadow-soft lg:grid-cols-[0.9fr_1.1fr]">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">library shape</p>
            <h2 class="mt-2 text-2xl font-semibold text-ink">Signals, computed values and effects.</h2>
            <p class="mt-3 max-w-xl text-sm leading-7 text-slate-600">
              reativa keeps state in signals, derives cached values with Computed,
              and runs Effects when tracked reads change. The view layer mounts real
              DOM nodes once, then updates only the reactive text, attributes and
              dynamic regions that depend on a signal.
            </p>
            <dl class="mt-5 grid gap-3 text-sm sm:grid-cols-3">
              <div class="rounded-lg bg-wash px-3 py-3">
                <dt class="font-semibold text-ink">Signal</dt>
                <dd class="mt-1 text-slate-600">Mutable reactive state.</dd>
              </div>
              <div class="rounded-lg bg-wash px-3 py-3">
                <dt class="font-semibold text-ink">Computed</dt>
                <dd class="mt-1 text-slate-600">Cached derived state.</dd>
              </div>
              <div class="rounded-lg bg-wash px-3 py-3">
                <dt class="font-semibold text-ink">Effect</dt>
                <dd class="mt-1 text-slate-600">Tracked side effects.</dd>
              </div>
            </dl>
          </div>
          {code_block "signals core" signals_code}
        </section>

        <section class="grid gap-6 lg:grid-cols-[0.9fr_1.1fr]">
          <article class="rounded-xl border border-line bg-white p-5 shadow-soft">
            <div class="flex items-start justify-between gap-4">
              <div>
                <h2 class="text-lg font-semibold text-ink">Counter controls</h2>
                <p class="mt-1 text-sm leading-6 text-slate-600">
                  Static JSX tags wrap reactive children and event handlers.
                </p>
              </div>
              <button
                class="rounded-lg border border-line px-3 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
                onClick={fun _ -> reset_demo ()}
              >
                reset all
              </button>
            </div>

            <div class="mt-6 rounded-xl bg-slate-50 p-4">
              <div class="flex items-center justify-between">
                <span class="text-sm font-medium text-slate-500">current value</span>
                <strong class="text-5xl font-semibold tabular-nums text-ink">
                  {View.dyn_int (fun () -> Signal.get count)}
                </strong>
              </div>
              <div class="mt-5 grid grid-cols-3 gap-2">
                <button
                  class="rounded-lg bg-slate-900 px-3 py-2 text-sm font-semibold text-white transition hover:bg-slate-700"
                  onClick={fun _ -> Signal.update count (fun n -> n - Signal.peek step)}
                >
                  minus
                </button>
                <button
                  class="rounded-lg bg-ink px-3 py-2 text-sm font-semibold text-white transition hover:bg-slate-700"
                  onClick={fun _ -> Signal.update count (fun n -> n + Signal.peek step)}
                >
                  plus
                </button>
                <button
                  class="rounded-lg border border-line px-3 py-2 text-sm font-semibold text-slate-700 transition hover:bg-white"
                  disabled={fun () -> Signal.get count = 0}
                  onClick={fun _ -> Signal.set count 0}
                >
                  zero
                </button>
              </div>
              <div class="mt-4 flex items-center gap-3">
                <span class="text-sm font-medium text-slate-500">step</span>
                <button
                  class={fun () ->
                    if Signal.get step = 1 then
                      "rounded-full bg-ink px-3 py-1.5 text-sm font-semibold text-white"
                    else
                      "rounded-full border border-line px-3 py-1.5 text-sm font-semibold text-slate-600 hover:bg-white"}
                  onClick={fun _ -> Signal.set step 1}
                >
                  1
                </button>
                <button
                  class={fun () ->
                    if Signal.get step = 5 then
                      "rounded-full bg-ink px-3 py-1.5 text-sm font-semibold text-white"
                    else
                      "rounded-full border border-line px-3 py-1.5 text-sm font-semibold text-slate-600 hover:bg-white"}
                  onClick={fun _ -> Signal.set step 5}
                >
                  5
                </button>
              </div>
            </div>

            <div class="mt-5">
              {code_block "counter view" counter_code}
            </div>

            <div class="mt-5 rounded-lg border border-line bg-white px-4 py-3">
              <p class="text-sm text-slate-600">
                {View.maybe
                   ~fallback:(View.text "No note selected.")
                   (fun () -> Signal.get selected)
                   (fun text -> View.text text)}
              </p>
              <div class="mt-3 flex flex-wrap gap-2">
                <button
                  class="rounded-md bg-slate-100 px-2.5 py-1.5 text-xs font-semibold text-slate-600 transition hover:bg-slate-200"
                  onClick={fun _ -> Signal.set selected (Some "maybe renders the Some branch")}
                >
                  show note
                </button>
                <button
                  class="rounded-md bg-slate-100 px-2.5 py-1.5 text-xs font-semibold text-slate-600 transition hover:bg-slate-200"
                  onClick={fun _ -> Signal.set selected None}
                >
                  clear note
                </button>
              </div>
            </div>

            <div class="mt-5">
              {code_block "conditional view" conditional_code}
            </div>
          </article>

          <article class="rounded-xl border border-line bg-white p-5 shadow-soft">
            <div class="flex flex-wrap items-start justify-between gap-4">
              <div>
                <h2 class="text-lg font-semibold text-ink">Todo list</h2>
                <p class="mt-1 text-sm leading-6 text-slate-600">
                  Submit the form to append an item. The input is reactive, so
                  resetting the signal clears it immediately.
                </p>
              </div>
              <button
                class="rounded-lg border border-line px-3 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
                onClick={fun _ -> clear_done ()}
              >
                clear done
              </button>
            </div>

            <div class="mt-5">
              <div class="mb-2 flex items-center justify-between text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">
                <span>{View.dyn_text (fun () -> string_of_int (Signal.get progress) ^ "% complete")}</span>
                <span>{View.dyn_text (fun () -> string_of_int (Signal.get completed_count) ^ " done")}</span>
              </div>
              <div class="h-2 overflow-hidden rounded-full bg-slate-100">
                <div
                  class="h-full rounded-full bg-ink transition-all duration-300"
                  style={fun () -> "width: " ^ string_of_int (Signal.get progress) ^ "%"}
                ></div>
              </div>
            </div>

            <form class="mt-5 flex flex-col gap-3 sm:flex-row" onSubmit={add_todo}>
              <input
                class="min-w-0 flex-1 rounded-lg border border-line bg-white px-3 py-2.5 text-sm text-ink outline-none transition placeholder:text-slate-400 focus:border-ink focus:ring-4 focus:ring-slate-900/10"
                placeholder="add a todo"
                value={fun () -> Signal.get draft}
                onInput={fun ev -> Signal.set draft (Dom.target_value ev)}
              />
              <button
                class={fun () ->
                  if Signal.get can_submit then
                    "rounded-lg bg-ink px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-700"
                  else
                    "rounded-lg bg-slate-200 px-4 py-2.5 text-sm font-semibold text-slate-400"}
                disabled={fun () -> not (Signal.get can_submit)}
              >
                add todo
              </button>
            </form>

            <div class="mt-5">
              {View.show
                 ~fallback:
                   ([%reativa.jsx
                     {|
                     <div class="rounded-lg border border-dashed border-line bg-slate-50 px-4 py-8 text-center text-sm text-slate-500">
                       Nothing here yet. Add a todo to exercise for_.
                     </div>
                     |}])
                 (fun () -> Signal.get todos <> [])
                 (View.ul
                    ~attrs:[View.Attr.class_ "space-y-2"]
                    [View.for_ (fun () -> Signal.get todos) todo_row])}
            </div>

            <footer class="mt-5 rounded-lg bg-slate-50 px-4 py-3 text-sm text-slate-600">
              {View.dyn_text (fun () ->
                 let remaining = Signal.get remaining_count in
                 string_of_int remaining ^ " " ^ plural remaining "item" "items" ^ " remaining")}
            </footer>

            <div class="mt-5">
              {code_block "todo view" todo_code}
            </div>
          </article>
        </section>
      </main>
      |jsx}]

// Starter programs for the playground. Each one is a complete .mlx module: it
// opens Reativa, builds a view and mounts it into the preview frame's #app.
// The preview frame ships a small stylesheet (see preview.html) so these read
// as finished UI without any CSS of their own.
//
// They compile on either backend: the bare children here are strings and ints,
// which every backend guarantees, rather than options or booleans (which only
// Melange can tell apart at runtime — use View.Maybe / View.Show for those).

export const EXAMPLES = [
  {
    id: "counter",
    title: "Counter",
    blurb: "Signals, a computed and inline reads that update one text node.",
    code: `open Reativa
open Reativa.View.Mlx

let () =
  let count = Signal.make 0 in
  let doubled = Computed.make (fun () -> Signal.get count * 2) in

  View.mount_by_id "app"
    <section className="card">
      <h1>("Counter")</h1>

      (* An inline Signal.get is auto-tracked: only this text node updates. *)
      <p className="value">(Signal.get count)</p>
      <p className="muted">("doubled: " ^ string_of_int (Signal.get doubled))</p>

      <div className="row">
        <button onClick=(fun _ -> Signal.update count (fun n -> n - 1))>
          ("-1")
        </button>
        <button onClick=(fun _ -> Signal.update count (fun n -> n + 1))>
          ("+1")
        </button>
        <button className="ghost" onClick=(fun _ -> Signal.set count 0)>
          ("reset")
        </button>
      </div>
    </section>
`,
  },
  {
    id: "derived",
    title: "Derived state",
    blurb: "Two inputs, a computed value and a conditional region.",
    code: `open Reativa
open Reativa.View.Mlx

let () =
  let first = Signal.make "Ada" in
  let last = Signal.make "Lovelace" in
  let full = Computed.make (fun () -> Signal.get first ^ " " ^ Signal.get last) in
  let length = Computed.make (fun () -> String.length (Signal.get full)) in

  View.mount_by_id "app"
    <section className="card">
      <h1>("Derived state")</h1>

      <div className="row">
        <input
          value=(Signal.get first)
          placeholder="First name"
          onInput=(fun ev -> Signal.set first (Dom.target_value ev))
        />
        <input
          value=(Signal.get last)
          placeholder="Last name"
          onInput=(fun ev -> Signal.set last (Dom.target_value ev))
        />
      </div>

      <p className="value">(Signal.get full)</p>
      <p className="muted">(string_of_int (Signal.get length) ^ " characters")</p>

      (* Show swaps a whole region when the condition flips. *)
      <View.Show
        condition=(fun () -> Signal.get length > 18)
        fallback=(<p className="muted">("Short and sweet.")</p>)
      >
        <p className="muted">("That is a long name.")</p>
      </View.Show>
    </section>
`,
  },
  {
    id: "todos",
    title: "Todo list",
    blurb: "A keyed list, a form and a computed count.",
    code: `open Reativa
open Reativa.View.Mlx

type todo = { id : int; title : string; completed : bool }

let () =
  let todos =
    Signal.make
      [
        { id = 1; title = "Learn signals"; completed = true };
        { id = 2; title = "Build something in reativa"; completed = false };
      ]
  in
  let next_id = Signal.make 3 in
  let draft = Signal.make "" in

  let remaining =
    Computed.make (fun () ->
      Signal.get todos |> List.filter (fun t -> not t.completed) |> List.length)
  in

  let toggle id =
    Signal.update todos (fun items ->
      List.map
        (fun t -> if t.id = id then { t with completed = not t.completed } else t)
        items)
  in

  let add () =
    let title = String.trim (Signal.peek draft) in
    if title <> "" then begin
      let id = Signal.peek next_id in
      Signal.update todos (fun items -> items @ [ { id; title; completed = false } ]);
      Signal.set next_id (id + 1);
      Signal.set draft ""
    end
  in

  View.mount_by_id "app"
    <section className="card">
      <h1>("Todos")</h1>
      <p className="muted">(string_of_int (Signal.get remaining) ^ " left")</p>

      <div className="row">
        <input
          value=(Signal.get draft)
          placeholder="What needs doing?"
          onInput=(fun ev -> Signal.set draft (Dom.target_value ev))
          onKeyDown=(fun ev -> if Dom.key ev = "Enter" then add ())
        />
        <button onClick=(fun _ -> add ())>("Add")</button>
      </div>

      (* key reconciles rows by identity, so DOM nodes survive updates. *)
      <ul className="list">
        <View.ForEach
          items=(fun () -> Signal.get todos)
          key=(fun todo -> string_of_int todo.id)
          render=(fun todo ->
            <li className=(if todo.completed then "row done" else "row")>
              <input
                type_="checkbox"
                checked=todo.completed
                onChange=(fun _ -> toggle todo.id)
              />
              <span>(todo.title)</span>
            </li>)
        />
      </ul>
    </section>
`,
  },
];

export const DEFAULT_EXAMPLE = EXAMPLES[0];

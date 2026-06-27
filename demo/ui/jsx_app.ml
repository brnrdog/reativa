(* Proof-of-concept JSX-like syntax for the [reativa_ui] View layer.

   Raw JSX syntax is not valid OCaml before preprocessing, so this first pass
   uses an OCaml extension containing JSX markup:

     [%reativa.jsx {| <section class="card">...</section> |}]

   The PPX lowers that markup to the same [Reativa_ui.View] constructors used
   by app.ml. Children inside braces are ordinary OCaml expressions that must
   produce [View.t]; event handlers and reactive attributes are ordinary OCaml
   functions. *)

open Reativa
open Reativa_ui

let () =
  let count = Signal.make 0 in
  let doubled = Computed.make (fun () -> Signal.get count * 2) in
  let is_even = Computed.make ~equals:( = ) (fun () -> Signal.get count mod 2 = 0) in
  let items = Signal.make [ "write JSX-like markup"; "lower to View.t" ] in
  let draft = Signal.make "" in

  let add_item () =
    let text = Signal.peek draft |> String.trim in
    if String.length text > 0 then begin
      Signal.update items (fun xs -> xs @ [ text ]);
      Signal.set draft ""
    end
  in

  View.mount_by_id
    "app"
    (View.div
       [
         [%reativa.jsx
           {|
           <section class="card">
             <h2>Counter from JSX</h2>
             <div class="row">
               <span class="label">count</span>
               <span class="value">{View.dyn_int (fun () -> Signal.get count)}</span>
             </div>
             <div class="row">
               <span class="label">doubled</span>
               <span class="value">{View.dyn_int (fun () -> Signal.get doubled)}</span>
             </div>
             <div class="row">
               <span class="label">parity</span>
               <span class="value">
                 {View.show
                    ~fallback:(View.text "odd")
                    (fun () -> Signal.get is_even)
                    (View.text "even")}
               </span>
             </div>
             <div class="row">
               <button onClick={fun _ -> Signal.update count (fun n -> n - 1)}>-1</button>
               <button onClick={fun _ -> Signal.update count (fun n -> n + 1)}>+1</button>
               <button
                 disabled={fun () -> Signal.get count = 0}
                 onClick={fun _ -> Signal.set count 0}
               >
                 reset
               </button>
             </div>
           </section>
           |}];
         [%reativa.jsx
           {|
           <section class="card">
             <h2>List from JSX</h2>
             <ul>{View.for_ (fun () -> Signal.get items) (fun item -> View.li [View.text item])}</ul>
             <div class="row">
               <input
                 placeholder="add an item"
                 value={fun () -> Signal.get draft}
                 onInput={fun ev -> Signal.set draft (Dom.target_value ev)}
               />
               <button onClick={fun _ -> add_item ()}>add</button>
             </div>
           </section>
           |}];
       ])

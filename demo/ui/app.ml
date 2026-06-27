(* Browser demo for the reactive UI layer ([reativa_ui]).

   The whole page is described once with {!View} combinators. After that, only
   the reactive bits update — driven straight from the signals, no virtual DOM,
   no re-render of the surrounding markup.

   It shows off:
   - [dyn_int] / [dyn_text]   reactive text bound to a Signal / Computed
   - [Attr.disabled]          a reactive attribute
   - [show]                   conditional rendering on a Computed
   - [for_]                   list rendering from a Signal of a list *)

open Reativa
open Reativa_ui
open View

let () =
  let count = Signal.make 0 in
  let doubled = Computed.make (fun () -> Signal.get count * 2) in
  let is_even = Computed.make ~equals:( = ) (fun () -> Signal.get count mod 2 = 0) in

  (* A list signal, to exercise [for_]. *)
  let items = Signal.make [ "learn signals"; "build a UI layer" ] in
  let draft = Signal.make "" in

  let add_item () =
    let text = Signal.peek draft in
    if String.length (String.trim text) > 0 then begin
      Signal.update items (fun xs -> xs @ [ text ]);
      Signal.set draft ""
    end
  in

  let counter_section =
    section
      ~attrs:[ Attr.class_ "card" ]
      [ h2 [ text "Counter" ]
      ; div ~attrs:[ Attr.class_ "row" ]
          [ span ~attrs:[ Attr.class_ "label" ] [ text "count" ]
          ; span ~attrs:[ Attr.class_ "value" ] [ dyn_int (fun () -> Signal.get count) ]
          ]
      ; div ~attrs:[ Attr.class_ "row" ]
          [ span ~attrs:[ Attr.class_ "label" ] [ text "doubled" ]
          ; span ~attrs:[ Attr.class_ "value" ] [ dyn_int (fun () -> Signal.get doubled) ]
          ]
      ; div ~attrs:[ Attr.class_ "row" ]
          [ span ~attrs:[ Attr.class_ "label" ] [ text "parity" ]
          (* [show] swaps these two views as the parity Computed flips. *)
          ; show
              ~fallback:(span ~attrs:[ Attr.class_ "value" ] [ text "odd" ])
              (fun () -> Signal.get is_even)
              (span ~attrs:[ Attr.class_ "value" ] [ text "even" ])
          ]
      ; div ~attrs:[ Attr.class_ "row" ]
          [ button
              ~events:[ On.click (fun _ -> Signal.update count (fun n -> n - 1)) ]
              [ text "-1" ]
          ; button
              ~events:[ On.click (fun _ -> Signal.update count (fun n -> n + 1)) ]
              [ text "+1" ]
          ; button
              (* reactive attribute: the reset button disables itself at zero *)
              ~attrs:[ Attr.disabled (fun () -> Signal.get count = 0) ]
              ~events:[ On.click (fun _ -> Signal.set count 0) ]
              [ text "reset" ]
          ]
      ]
  in

  let list_section =
    section
      ~attrs:[ Attr.class_ "card" ]
      [ h2 [ text "List (for_)" ]
      ; ul
          [ for_
              (fun () -> Signal.get items)
              (fun item -> li [ text item ])
          ]
      ; div ~attrs:[ Attr.class_ "row" ]
          [ input
              ~attrs:
                [ Attr.placeholder "add an item…"; Attr.value_reactive (fun () -> Signal.get draft) ]
              ~events:[ On.input (fun ev -> Signal.set draft (Dom.target_value ev)) ]
              ()
          ; button ~events:[ On.click (fun _ -> add_item ()) ] [ text "add" ]
          ]
      ]
  in

  mount_by_id "app" (div [ counter_section; list_section ])

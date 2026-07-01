open Reativa
open Reativa.View.Mlx

let checked = Signal.make false
let draft = Signal.make "hello"
let numbers = Signal.make [ 1; 2; 3 ]
let selected = Signal.make (Some "selected")

let _view =
  ((section
      ~className:"fixture"
      ~aria_label:"MLX inference"
      ~children:
        [
          ((h1 ~children:[ View.text "Static title" ] ()) [@JSX]);
          ((input
              ~type_:"checkbox"
              ~checked:(fun () -> Signal.get checked)
              ~value:(fun () -> Signal.get draft)
              ~placeholder:"Type here"
              ())
           [@JSX]);
          ((p ~children:[ View.text (fun () -> Signal.get draft) ] ()) [@JSX]);
          ((p ~children:[ View.text (static "Explicit wrappers still work") ] ())
           [@JSX]);
        ]
      ())
   [@JSX])

let _for_each_view =
  ((View.ForEach.createElement ()
      ~children:[]
      ~items:[ 1; 2; 3 ]
      ~render:(fun item -> ((span ~children:[ View.int item ] ()) [@JSX])))
   [@JSX])

let _keyed_for_each_view =
  ((View.ForEach.createElement ()
      ~children:[]
      ~items:(fun () -> Signal.get numbers)
      ~key:string_of_int
      ~render:(fun item -> ((span ~children:[ View.int item ] ()) [@JSX])))
   [@JSX])

let _show_view =
  ((View.Show.createElement ()
      ~children:[ ((span ~children:[ View.text "Visible" ] ()) [@JSX]) ]
      ~condition:(fun () -> Signal.get checked)
      ~fallback:((span ~children:[ View.text "Hidden" ] ()) [@JSX]))
   [@JSX])

let _maybe_view =
  ((View.Maybe.createElement ()
      ~children:[]
      ~value:(fun () -> Signal.get selected)
      ~render:(fun value -> ((span ~children:[ View.text value ] ()) [@JSX]))
      ~fallback:((span ~children:[ View.text "Nothing selected" ] ()) [@JSX]))
   [@JSX])

let () = print_endline "mlx inference ok"

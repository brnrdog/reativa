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

(* Eager signal reads are auto-thunked into [dynamic] values, and literal
   children become view leaves without explicit [View.text]/[View.int]. *)
let _auto_tracked_view =
  ((section
      ~className:(if Signal.get checked then "fixture on" else "fixture off")
      ~children:
        [
          ((h1 ~children:[ "Bare string child" ] ()) [@JSX]);
          ((p ~children:[ "Draft: "; View.text (Signal.get draft) ] ()) [@JSX]);
          ((p ~children:[ 42; 1.5 ] ()) [@JSX]);
          ((p ~children:[ View.int (List.length (Signal.get numbers)) ] ())
           [@JSX]);
          ((p ~children:[ View.text (Signal.peek draft) ] ()) [@JSX]);
          ((input
              ~checked:(Signal.get checked)
              ~value:(Signal.get draft)
              ())
           [@JSX]);
        ]
      ())
   [@JSX])

let _tracked_view =
  View.tracked (fun () ->
    if Signal.get checked then View.text (static "on") else View.empty)

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

let _home_route =
  Route.createElement ()
    ~path:"/"
    ~children:[ ((span ~children:[ View.text "Home" ] ()) [@JSX]) ]

let _user_route =
  Route.createElement ()
    ~path:"/users/:id"
    ~children:[]
    ~render:(fun matched ->
      ((span
          ~children:
            [ View.text ("User " ^ Option.value ~default:"missing" (Router.param matched "id")) ]
          ())
       [@JSX]))

let _router_view =
  ((Router.createElement () ~children:[ _home_route; _user_route ]) [@JSX])

let _link_view =
  ((Link.createElement ()
      ~href:"/users/42"
      ~children:[ View.text "User 42" ])
   [@JSX])

let _redirect_view =
  ((Redirect.createElement () ~to_:"/" ~children:[]) [@JSX])

let () = print_endline "mlx inference ok"

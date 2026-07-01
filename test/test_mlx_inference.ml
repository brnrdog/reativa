open Reativa
open Reativa.View.Mlx

let checked = Signal.make false
let draft = Signal.make "hello"

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

let () = print_endline "mlx inference ok"

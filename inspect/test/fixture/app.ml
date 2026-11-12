(* A small app for the reativa-inspect tests: a counter, a derived label, a toggle. *)

open Reativa

let () =
  Devtools.install ();
  Devtools.expose ()

let count = Signal.make ~name:"count" 0
let label = Computed.make ~name:"label" (fun () -> Printf.sprintf "%d clicks" (Signal.get count))
let open_ = Signal.make ~name:"open" false

let app =
  View.div
    [
      View.Mlx.button ~id:(View.static "inc")
        ~onClick:(fun _ -> Signal.update count (fun n -> n + 1))
        ~children:[ View.text (View.static "+") ] ();
      View.Mlx.p ~id:(View.static "value") ~children:[ View.text (View.signal label) ] ();
      View.Mlx.button ~id:(View.static "toggle")
        ~onClick:(fun _ -> Signal.update open_ not)
        ~children:[ View.text (View.static "toggle") ] ();
      View.show (fun () -> Signal.get open_) (View.Mlx.aside ~id:(View.static "panel") ());
    ]

let () = View.mount_by_id "app" app

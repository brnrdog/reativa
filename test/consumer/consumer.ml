(* A consumer of the installed reativa packages, built outside the repository
   by CI's packaging job (see test/consumer/README.md). It uses the public API
   the way an application does, so a symbol that is hidden by mistake, or an
   interface that stopped matching its implementation, fails here. *)

open Reativa

let count = Signal.make ~name:"count" 0
let doubled = Computed.make (fun () -> Signal.get count * 2)
let todos = Signal.make [ "write"; "test" ]

let () =
  Effect.run (fun () ->
    ignore (Signal.get doubled);
    Some (fun () -> ()))

let theme = Owner.new_key "light"

module Badge = struct
  let component ~label =
    View.component (fun () ->
      Owner.on_cleanup (fun () -> ());
      let tone = Owner.lookup theme in
      View.Mlx.span ~className:(View.static tone) ~children:[ View.text (View.static label) ] ())
end

let app =
  View.Mlx.main
    ~children:
      [
        View.Mlx.h1 ~children:[ View.text (View.static "Consumer") ] ();
        View.Mlx.button
          ~onClick:(fun _ -> Signal.update count (fun n -> n + 1))
          ~disabled:(View.dynamic (fun () -> Signal.get count > 9))
          ~attrs:[ View.Attr.data "test" (View.static "inc") ]
          ~children:[ View.int (View.signal count) ]
          ();
        View.for_with_key (fun () -> Signal.get todos) ~key:Fun.id (fun todo ->
          View.Mlx.li ~children:[ View.text (View.signal todo) ] ());
        View.show (fun () -> Signal.get count > 0) (Badge.component ~label:"clicked");
        View.Mlx.svg ~viewBox:(View.static "0 0 4 4") ~children:[ View.Mlx.circle ~r:(View.static "2") () ] ();
        Router.outlet
          [
            Router.route "/" (fun _ -> View.text (View.static "home"));
            Router.route "/items/:id" (fun m ->
              View.text (View.static (Option.value ~default:"" (Router.param m "id"))));
          ];
        Router.link ~href:"/items/1" [ View.text (View.static "item") ];
      ]
    ()

(* 2.0 additions: lifecycle, refs, context, boundaries, portals, resources. *)
let color = Context.make "black"
let field = View.Ref.make ()
let greeting = Resource.make (fun () -> Promise.resolve "hello")

let extras =
  View.fragment
    [
      View.component (fun () ->
        View.on_mount (fun () -> ignore (View.Ref.current field));
        View.on_cleanup (fun () -> ());
        View.Mlx.input ~ref:field ());
      Context.provider color "red" (View.component (fun () -> View.text (View.static (Context.use color))));
      View.error_boundary
        ~fallback:(fun e reset ->
          View.Mlx.button ~onClick:(fun _ -> reset ()) ~children:[ View.text (View.static (Printexc.to_string e)) ] ())
        (View.component (fun () -> failwith "boom"));
      View.portal (View.Mlx.aside ());
      View.suspense ~fallback:(View.text (View.static "…"))
        (View.dyn (fun () ->
           View.text (View.static (Option.value ~default:"" (Resource.value (Resource.state greeting))))));
    ]

let () = View.mount_by_id "app" (View.fragment [ app; extras ])

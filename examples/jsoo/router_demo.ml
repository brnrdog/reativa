(* A second js_of_ocaml demo, exercising the SPA router.

   This proves the router port end to end: [src/router.ml] is reused verbatim
   (copied by dune), driving the browser through the js_of_ocaml [History] and
   [Dom] modules in this directory instead of their Melange counterparts.

   Written against the plain constructor API (Router.outlet / route / link /
   redirect) rather than JSX so the demo is fully self-contained; the
   <Router>/<Route>/<Link>/<Redirect> markup used elsewhere lowers to these same
   calls via the (engine-neutral) mlx ppx. *)

open Reativa

let text s = View.text (View.static s)

let link href label = Router.link ~href [ text label ]

let page title body =
  View.div
    ~attrs:[ View.Attr.class_ (View.static "page") ]
    [ View.h1 [ text title ]; View.p [ text body ] ]

let nav =
  View.div
    ~attrs:[ View.Attr.class_ (View.static "router-nav") ]
    [ link "/" "Home"; text " · "; link "/about" "About"; text " · "; link "/old" "Old (redirects)" ]

let home _ = page "Home" "This SPA router runs entirely on js_of_ocaml history bindings."

let routes =
  Router.outlet
    ~fallback:home
    [ Router.route "/" home;
      Router.route "/about" (fun _ ->
        page "About"
          "Same Router logic as the Melange build — only History and Dom are engine-specific.");
      Router.route "/old" (fun _ -> Router.redirect "/") ]

let () = View.mount_by_id "app" (View.div [ nav; routes ])

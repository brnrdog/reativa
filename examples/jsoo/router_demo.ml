(* A small SPA on the js_of_ocaml backend: links, pushState navigation and a
   redirect, all through [Reativa.Router].

   It uses the constructor API (Router.outlet / route / link / redirect) rather
   than JSX, which keeps the file self-contained — the <Router>/<Route>/<Link>
   markup used elsewhere lowers to these same calls. *)

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
          "Same Router logic as the Melange build — only History and Dom are backend-specific.");
      Router.route "/old" (fun _ -> Router.redirect "/") ]

let () = View.mount_by_id "app" (View.div [ nav; routes ])

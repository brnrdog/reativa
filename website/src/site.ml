(* What every page of the site shares: the base path the site is served
   under, the current route, the theme and syntax switches, the clipboard,
   and the few browser bindings the pages need. *)

open Reativa

(* ----- browser bindings used only by the site ----- *)

external copy_text : string -> unit = "writeText"
  [@@mel.scope ("navigator", "clipboard")]

external set_timeout : (unit -> unit) -> int -> unit = "setTimeout"
external set_interval : (unit -> unit) -> int -> float = "setInterval"
external clear_interval : float -> unit = "clearInterval"
external query_selector : string -> Dom.t = "querySelector" [@@mel.scope "document"]

external element_by_id : string -> Dom.t option = "getElementById"
  [@@mel.scope "document"] [@@mel.return nullable]

external get_attribute : Dom.t -> string -> string option = "getAttribute"
  [@@mel.send] [@@mel.return nullable]

external scroll_into_view : Dom.t -> unit = "scrollIntoView" [@@mel.send]
external scroll_to : float -> float -> unit = "scrollTo" [@@mel.scope "window"]
external store_item : string -> string -> unit = "setItem" [@@mel.scope "localStorage"]

external read_item : string -> string option = "getItem"
  [@@mel.scope "localStorage"] [@@mel.return nullable]

let set_document_title : string -> unit = [%mel.raw {|function (t) { document.title = t; }|}]
let stored key = try read_item key with _ -> None
let remember key value = try store_item key value with _ -> ()

(* ----- where the site lives ----- *)

(* GitHub Pages serves the site under /reativa/; vite.config.mjs uses the same
   base. Routes in the app are written without it ("/docs/learn/signals"). *)
let base = "/reativa"
let href path = if path = "/" then base ^ "/" else base ^ path
let github = "https://github.com/brnrdog/reativa"

(* A Markdown copy of an agent page, published next to the site. *)
let agent_markdown slug = base ^ "/docs/" ^ slug ^ ".md"

let starts_with ~prefix s =
  String.length s >= String.length prefix
  && String.sub s 0 (String.length prefix) = prefix

(* "/reativa/docs/" -> "/docs"; anything outside the base is left as is. *)
let route_of_pathname pathname =
  let path =
    if starts_with ~prefix:base pathname then
      String.sub pathname (String.length base) (String.length pathname - String.length base)
    else pathname
  in
  let rec trim p =
    let n = String.length p in
    if n > 1 && p.[n - 1] = '/' then trim (String.sub p 0 (n - 1)) else p
  in
  match trim path with "" -> "/" | p -> p

(* The route the page is on, without base or trailing slash. Equal routes do
   not notify, so a hash change does not rebuild the page. *)
let route =
  Computed.make ~equals:String.equal (fun () ->
    route_of_pathname (Signal.get (Router.location ())).pathname)

let is_current path = Signal.get route = path

(* A link to a route of this site: navigates in place on a plain click. *)
let link ?(className = "") path children =
  Router.link ~attrs:[ View.Attr.className (View.static className) ] ~href:(href path) children

(* The same, with [is-active] while the page is on that route. *)
let nav_link ?(className = "") ?(exact = true) path children =
  let active () =
    let r = Signal.get route in
    if exact then r = path else starts_with ~prefix:path r
  in
  Router.link
    ~attrs:
      [
        View.Attr.class_reactive (fun () ->
          if active () then String.trim (className ^ " is-active") else className);
      ]
    ~href:(href path) children

(* ----- color theme: light / dark ----- *)

(* index.html seeds [data-theme] on <html> before first paint (from
   localStorage or the OS preference). We read it back to align the signal,
   then keep the attribute - and the stored choice - in sync as it changes. *)

type theme = Light | Dark

let root_el = query_selector "html"

let theme =
  Signal.make
    (match get_attribute root_el "data-theme" with Some "dark" -> Dark | _ -> Light)

let () =
  Effect.run (fun () ->
    let name = match Signal.get theme with Dark -> "dark" | Light -> "light" in
    Dom.set_attribute root_el "data-theme" name;
    remember "theme" name;
    None)

let toggle_theme _ = Signal.update theme (function Light -> Dark | Dark -> Light)

(* ----- syntax toggle: OCaml (mlx) vs ReasonML (re) ----- *)

(* Neither syntax is the "real" one: the two render the same library, and the
   choice is remembered so a ReasonML reader keeps ReasonML across visits. *)

type syntax = OCaml | Reason

let syntax =
  Signal.make (match stored "syntax" with Some "reason" -> Reason | _ -> OCaml)

let () =
  Effect.run (fun () ->
    remember "syntax" (match Signal.get syntax with Reason -> "reason" | OCaml -> "ocaml");
    None)

(* Turn an mlx filename into its ReasonML counterpart: foo.mlx -> foo.re. *)
let reason_file file =
  match String.rindex_opt file '.' with
  | Some i -> String.sub file 0 i ^ ".re"
  | None -> file ^ ".re"

(* ----- copy-to-clipboard feedback ----- *)

let copied = Signal.make ""

let copy_code id source =
  (try copy_text source with _ -> ());
  Signal.set copied id;
  set_timeout (fun () -> if Signal.peek copied = id then Signal.set copied "") 1600

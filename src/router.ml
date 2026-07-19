(* Browser-side SPA routing for Reativa.

   The module keeps the browser location in a Signal, mirrors programmatic
   history changes immediately, and refreshes from [popstate] for back/forward
   navigation. Route matching is pure so it can be tested natively. *)

type state

type 'a nullable

(* Bound through the shipped runtime helper (see reativa_runtime.js): melange
   primitive spellings like "#undefined" are not valid symbols for the native
   toolchain, which also compiles (but never links) this module. *)
external nullable_undefined : unit -> 'a nullable = "getUndefined"
  [@@mel.module "./reativa_runtime.js"]

external nullable_return : 'a -> 'a nullable = "%identity"
external encode_state : 'a -> state = "%identity"
external decode_state : state -> 'a = "%identity"

let nullable_of_option = function
  | None -> nullable_undefined ()
  | Some value -> nullable_return value

type location = {
  href : string;
  origin : string;
  pathname : string;
  search : string;
  hash : string;
  state : state option;
}

type window
type history
type location_target
type pop_state_event

external get_window : unit -> window = "getWindow"
  [@@mel.module "./reativa_runtime.js"]

let window () = get_window ()

external history : window -> history = "history" [@@mel.get]
external browser_location : window -> location_target = "location" [@@mel.get]
external href : location_target -> string = "href" [@@mel.get]
external origin : location_target -> string = "origin" [@@mel.get]
external pathname : location_target -> string = "pathname" [@@mel.get]
external search : location_target -> string = "search" [@@mel.get]
external hash : location_target -> string = "hash" [@@mel.get]
external history_state : history -> state option = "state"
  [@@mel.get] [@@mel.return nullable]

external push_state : history -> state nullable -> string -> string -> unit
  = "pushState"
  [@@mel.send]

external replace_state : history -> state nullable -> string -> string -> unit
  = "replaceState"
  [@@mel.send]

external go_history : history -> int -> unit = "go" [@@mel.send]
external back_history : history -> unit = "back" [@@mel.send]
external forward_history : history -> unit = "forward" [@@mel.send]

external add_popstate_listener : window -> string -> (pop_state_event -> unit) -> unit
  = "addEventListener"
  [@@mel.send]

external default_prevented : Dom.event -> bool = "defaultPrevented" [@@mel.get]
external mouse_button : Dom.event -> int = "button" [@@mel.get]
external meta_key : Dom.event -> bool = "metaKey" [@@mel.get]
external ctrl_key : Dom.event -> bool = "ctrlKey" [@@mel.get]
external shift_key : Dom.event -> bool = "shiftKey" [@@mel.get]
external alt_key : Dom.event -> bool = "altKey" [@@mel.get]

let state value = encode_state value
let state_value encoded = decode_state encoded

let current () =
  let w = window () in
  let loc = browser_location w in
  let hist = history w in
  {
    href = href loc;
    origin = origin loc;
    pathname = pathname loc;
    search = search loc;
    hash = hash loc;
    state = history_state hist;
  }

let location_signal : location Signal.t Lazy.t = lazy (Signal.make (current ()))
let started = ref false

let sync signal = Signal.set signal (current ())

let start_with_signal signal =
  if not !started then begin
    started := true;
    let w = window () in
    add_popstate_listener w "popstate" (fun _ -> sync signal);
    sync signal
  end

let location () =
  let signal = Lazy.force location_signal in
  start_with_signal signal;
  signal

let start () = ignore (location ())
let current_signal = location

let path loc = loc.pathname ^ loc.search ^ loc.hash

let navigate ?(replace = false) ?state to_ () =
  let w = window () in
  let hist = history w in
  let next_state = nullable_of_option state in
  if replace then replace_state hist next_state "" to_
  else push_state hist next_state "" to_;
  sync (location ())

let replace ?state to_ () = navigate ~replace:true ?state to_ ()
let push ?state to_ () = navigate ?state to_ ()
let go delta = go_history (history (window ())) delta
let back () = back_history (history (window ()))
let forward () = forward_history (history (window ()))

let starts_with ~prefix value =
  let prefix_len = String.length prefix in
  String.length value >= prefix_len && String.sub value 0 prefix_len = prefix

let is_special_href href =
  href = "" || starts_with ~prefix:"#" href || starts_with ~prefix:"mailto:" href
  || starts_with ~prefix:"tel:" href || starts_with ~prefix:"javascript:" href
  || starts_with ~prefix:"//" href

let is_http_href href =
  starts_with ~prefix:"http://" href || starts_with ~prefix:"https://" href

let same_origin_href href =
  (not (is_http_href href)) || starts_with ~prefix:(current ()).origin href

let should_handle_click ?target ev href =
  let target_allows_spa =
    match target with None | Some "_self" -> true | Some _ -> false
  in
  target_allows_spa && (not (default_prevented ev)) && mouse_button ev = 0
  && (not (meta_key ev)) && (not (ctrl_key ev)) && (not (shift_key ev))
  && (not (alt_key ev)) && (not (is_special_href href)) && same_origin_href href

let link_value ?(replace = false) ?state ?target ?(attrs = []) ?(events = []) ~href children =
  let href_value = View.value_getter href in
  let attrs =
    let attrs = View.Attr.href href :: attrs in
    match target with
    | None -> attrs
    | Some target -> View.Attr.make "target" (View.static target) :: attrs
  in
  let on_click ev =
    let href = href_value () in
    if should_handle_click ?target ev href then begin
      Dom.prevent_default ev;
      navigate ~replace ?state href ()
    end
  in
  View.a ~attrs ~events:(events @ [ View.On.click on_click ]) children

let link ?replace ?state ?target ?attrs ?events ~href children =
  link_value ?replace ?state ?target ?attrs ?events ~href:(View.static href) children

type route_match = Router_match.t = {
  pattern : string;
  pathname : string;
  params : (string * string) list;
}

type route = {
  route_path : string;
  render : route_match -> View.t;
}

let route path render = { route_path = path; render }
let match_path = Router_match.match_path
let param = Router_match.param

let rec match_route pathname = function
  | [] -> None
  | route :: routes -> begin
    match match_path route.route_path pathname with
    | Some matched -> Some (route, matched)
    | None -> match_route pathname routes
  end

let outlet ?fallback routes =
  let fallback =
    match fallback with Some fallback -> fallback | None -> fun _ -> View.empty
  in
  View.dyn (fun () ->
    let loc = Signal.get (location ()) in
    match match_route loc.pathname routes with
    | Some (route, matched) -> route.render matched
    | None -> fallback loc)

let is_active ?(exact = true) href =
  let loc = Signal.get (location ()) in
  if exact then path loc = href
  else starts_with ~prefix:href (path loc)

let redirect_value ?(replace = true) ?state to_ =
  let destination = View.value_getter to_ in
  View.dyn (fun () ->
    navigate ~replace ?state (destination ()) ();
    View.empty)

let redirect ?replace ?state to_ = redirect_value ?replace ?state (View.static to_)

let component ?fallback ~children () = outlet ?fallback children
let createElement ?fallback () ~children = component ?fallback ~children ()

module Route = struct
  let component ?render ~path ~children () =
    let render =
      match render with
      | Some render -> render
      | None -> fun _ -> View.fragment children
    in
    route path render

  let createElement ?render () ~children ~path =
    component ?render ~path ~children ()
end

module Link = struct
  let component ?replace ?state ?target ~href ~children () =
    link_value ?replace ?state ?target ~href children

  let createElement ?replace ?state ?target () ~children ~href =
    component ?replace ?state ?target ~href ~children ()
end

module Redirect = struct
  let component ?replace ?state ~to_ () = redirect_value ?replace ?state to_

  let createElement ?replace ?state () ~children:_ ~to_ =
    component ?replace ?state ~to_ ()
end

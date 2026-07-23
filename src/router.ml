(* Browser-side SPA routing for Reativa.

   The module keeps the browser location in a Signal, mirrors programmatic
   history changes immediately, and refreshes from [popstate] for back/forward
   navigation. Route matching is pure so it can be tested natively. *)

(* All browser FFI now lives in {!History} (window/history/location) and {!Dom}
   (event modifier accessors), so this module is engine-agnostic OCaml. *)

type state = History.state

type location = {
  href : string;
  origin : string;
  pathname : string;
  search : string;
  hash : string;
  state : state option;
}

let window () = History.window ()

let state value = History.encode_state value
let state_value encoded = History.decode_state encoded

let current () =
  let w = History.window () in
  let loc = History.browser_location w in
  let hist = History.history w in
  {
    href = History.href loc;
    origin = History.origin loc;
    pathname = History.pathname loc;
    search = History.search loc;
    hash = History.hash loc;
    state = History.history_state hist;
  }

let location_signal : location Signal.t Lazy.t = lazy (Signal.make (current ()))
let started = ref false

let sync signal = Signal.set signal (current ())

let start_with_signal signal =
  if not !started then begin
    started := true;
    let w = History.window () in
    History.add_popstate_listener w "popstate" (fun _ -> sync signal);
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
  let w = History.window () in
  let hist = History.history w in
  let next_state = History.nullable_of_option state in
  if replace then History.replace_state hist next_state "" to_
  else History.push_state hist next_state "" to_;
  sync (location ())

let replace ?state to_ () = navigate ~replace:true ?state to_ ()
let push ?state to_ () = navigate ?state to_ ()
let go delta = History.go_history (History.history (History.window ())) delta
let back () = History.back_history (History.history (History.window ()))
let forward () = History.forward_history (History.history (History.window ()))

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
  target_allows_spa && (not (Dom.default_prevented ev)) && Dom.mouse_button ev = 0
  && (not (Dom.meta_key ev)) && (not (Dom.ctrl_key ev)) && (not (Dom.shift_key ev))
  && (not (Dom.alt_key ev)) && (not (is_special_href href)) && same_origin_href href

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

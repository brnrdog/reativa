(* Browser history / location FFI via the js_of_ocaml FFI.

   The js_of_ocaml counterpart of Reativa's Melange [History] module
   ([src/history.ml]). It exposes the exact same value signature, so the
   engine-agnostic [Router] logic (copied verbatim from src/router.ml) compiles
   against it unchanged — the routing port is, like the DOM port, just this one
   file plus [Dom]. Bindings go through [Js.Unsafe], mirroring the Melange
   [external ... [@@mel.*]] declarations one-for-one. *)

open Js_of_ocaml

type state = Js.Unsafe.any
type 'a nullable = Js.Unsafe.any

let js_undefined : Js.Unsafe.any = Js.Unsafe.pure_js_expr "undefined"
let js_null : Js.Unsafe.any = Js.Unsafe.pure_js_expr "null"

let nullable_undefined () : 'a nullable = js_undefined
let nullable_return (v : 'a) : 'a nullable = Js.Unsafe.inject v

let nullable_of_option = function
  | None -> nullable_undefined ()
  | Some value -> nullable_return value

(* history state is passed through opaquely, exactly as the Melange [%identity]
   externals do. *)
let encode_state (v : 'a) : state = Js.Unsafe.inject v
let decode_state (s : state) : 'a = Obj.magic s

type window = Js.Unsafe.any
type history = Js.Unsafe.any
type location_target = Js.Unsafe.any
type pop_state_event = Js.Unsafe.any

let get_window () : window = Js.Unsafe.get Js.Unsafe.global "window"
let window () = get_window ()

let history (w : window) : history = Js.Unsafe.get w "history"
let browser_location (w : window) : location_target = Js.Unsafe.get w "location"

let read_string (obj : Js.Unsafe.any) (field : string) : string =
  Js.to_string (Js.Unsafe.get obj field : Js.js_string Js.t)

let href (l : location_target) : string = read_string l "href"
let origin (l : location_target) : string = read_string l "origin"
let pathname (l : location_target) : string = read_string l "pathname"
let search (l : location_target) : string = read_string l "search"
let hash (l : location_target) : string = read_string l "hash"

(* [history.state] is [null] when unset; map [null]/[undefined] to [None] to
   match the Melange [@@mel.return nullable] behaviour. *)
let history_state (h : history) : state option =
  let s : Js.Unsafe.any = Js.Unsafe.get h "state" in
  if s == js_null || s == js_undefined then None else Some s

let push_state (h : history) (st : state nullable) (title : string) (url : string) : unit =
  ignore
    (Js.Unsafe.meth_call h "pushState"
       [| Js.Unsafe.inject st; Js.Unsafe.inject (Js.string title); Js.Unsafe.inject (Js.string url) |])

let replace_state (h : history) (st : state nullable) (title : string) (url : string) : unit =
  ignore
    (Js.Unsafe.meth_call h "replaceState"
       [| Js.Unsafe.inject st; Js.Unsafe.inject (Js.string title); Js.Unsafe.inject (Js.string url) |])

let go_history (h : history) (delta : int) : unit =
  ignore (Js.Unsafe.meth_call h "go" [| Js.Unsafe.inject delta |])

let back_history (h : history) : unit = ignore (Js.Unsafe.meth_call h "back" [||])
let forward_history (h : history) : unit = ignore (Js.Unsafe.meth_call h "forward" [||])

let add_popstate_listener (w : window) (name : string) (handler : pop_state_event -> unit) : unit =
  ignore
    (Js.Unsafe.meth_call w "addEventListener"
       [| Js.Unsafe.inject (Js.string name); Js.Unsafe.inject (Js.wrap_callback handler) |])

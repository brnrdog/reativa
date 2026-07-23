(* Low-level DOM bindings via the js_of_ocaml FFI.

   This is the js_of_ocaml counterpart to Reativa's Melange [Dom] module
   ([src/dom.ml]). It exposes the *exact same* value signature, so the entire
   reactive core (Signal/Computed/Effect/scheduler) and the [View] layer above
   it compile against it completely unchanged.

   That is the whole point of the prototype: only this one module is
   engine-specific. Swapping OCaml-to-JS engines is swapping this file — the
   Melange version binds the browser DOM through [external ... [@@mel.*]], this
   version binds it through js_of_ocaml's [Js.Unsafe]. Everything else is
   backend-agnostic OCaml.

   Like the Melange version it keeps a single abstract node type [t] standing in
   for every kind of DOM node (elements, text nodes and comment anchors alike),
   and binds the handful of browser APIs the View layer needs untyped-on-purpose
   through [Js.Unsafe], rather than fighting js_of_ocaml's typed [Dom_html]. *)

open Js_of_ocaml

type t = Js.Unsafe.any
type event = Js.Unsafe.any

let document : Js.Unsafe.any = Js.Unsafe.get Js.Unsafe.global "document"

(* ----- creating nodes ----- *)

let create_element (tag : string) : t =
  Js.Unsafe.meth_call document "createElement" [| Js.Unsafe.inject (Js.string tag) |]

let create_text_node (s : string) : t =
  Js.Unsafe.meth_call document "createTextNode" [| Js.Unsafe.inject (Js.string s) |]

(* Comment nodes are invisible; the View layer uses them as stable anchors that
   mark where a reactive region's nodes should be (re)inserted. *)
let create_comment (s : string) : t =
  Js.Unsafe.meth_call document "createComment" [| Js.Unsafe.inject (Js.string s) |]

let by_id (id : string) : t option =
  (* getElementById returns null when nothing matches; [Js.Opt.to_option] maps
     that JS null to [None]. *)
  let node : t Js.opt =
    Js.Unsafe.meth_call document "getElementById" [| Js.Unsafe.inject (Js.string id) |]
  in
  Js.Opt.to_option node

(* ----- tree manipulation ----- *)

let append_child (parent : t) (child : t) : unit =
  ignore (Js.Unsafe.meth_call parent "appendChild" [| Js.Unsafe.inject child |])

(* [insert_before parent node ref]: insert [node] as a child of [parent],
   immediately before the existing child [ref]. *)
let insert_before (parent : t) (node : t) (reference : t) : unit =
  ignore
    (Js.Unsafe.meth_call parent "insertBefore"
       [| Js.Unsafe.inject node; Js.Unsafe.inject reference |])

let remove_child (parent : t) (child : t) : unit =
  ignore (Js.Unsafe.meth_call parent "removeChild" [| Js.Unsafe.inject child |])

let next_sibling (node : t) : t option =
  Js.Opt.to_option (Js.Unsafe.get node "nextSibling" : t Js.opt)

let is_same_node (a : t) (b : t) : bool =
  Js.to_bool (Js.Unsafe.meth_call a "isSameNode" [| Js.Unsafe.inject b |] : bool Js.t)

(* ----- attributes & content ----- *)

let set_attribute (el : t) (name : string) (v : string) : unit =
  ignore
    (Js.Unsafe.meth_call el "setAttribute"
       [| Js.Unsafe.inject (Js.string name); Js.Unsafe.inject (Js.string v) |])

let remove_attribute (el : t) (name : string) : unit =
  ignore (Js.Unsafe.meth_call el "removeAttribute" [| Js.Unsafe.inject (Js.string name) |])

(* Setting [textContent] on a text node replaces its text; on an element it
   replaces all children with a single text node. *)
let set_text_content (node : t) (text : string) : unit =
  Js.Unsafe.set node "textContent" (Js.string text)

let set_value (el : t) (v : string) : unit = Js.Unsafe.set el "value" (Js.string v)
let set_checked (el : t) (v : bool) : unit = Js.Unsafe.set el "checked" (Js.bool v)

let key (ev : event) : string = Js.to_string (Js.Unsafe.get ev "key" : Js.js_string Js.t)

(* ----- events ----- *)

let add_event_listener (el : t) (name : string) (handler : event -> unit) : unit =
  ignore
    (Js.Unsafe.meth_call el "addEventListener"
       [| Js.Unsafe.inject (Js.string name); Js.Unsafe.inject (Js.wrap_callback handler) |])

let prevent_default (ev : event) : unit =
  ignore (Js.Unsafe.meth_call ev "preventDefault" [||])

(* Convenience reader for [event.target.value] (e.g. text inputs). *)
let target (ev : event) : t = Js.Unsafe.get ev "target"
let value (node : t) : string = Js.to_string (Js.Unsafe.get node "value" : Js.js_string Js.t)
let target_value ev = value (target ev)

let log : 'a -> unit =
 fun x ->
  ignore
    (Js.Unsafe.meth_call
       (Js.Unsafe.get Js.Unsafe.global "console")
       "log"
       [| Js.Unsafe.inject x |])

(* ----- runtime value inspection (used by [View.child]) ----- *)

(* JS [typeof x]: "string", "number", "boolean", "function", "object", ...
   See the note in the prototype README: this reads the *JavaScript runtime
   representation* of an OCaml value, so its answers depend on the engine's
   value mapping. For the strings, numbers and already-built views the demo
   passes as bare JSX children, js_of_ocaml (with its default JS-string
   representation) agrees with Melange. *)
let typeof (x : 'a) : string =
  Js.to_string
    (Js.Unsafe.fun_call
       (Js.Unsafe.js_expr "(function (v) { return typeof v; })")
       [| Js.Unsafe.inject x |])

(* JS [String(x)]: canonical display form for numbers and booleans. *)
let display_string (x : 'a) : string =
  Js.to_string (Js.Unsafe.fun_call (Js.Unsafe.js_expr "String") [| Js.Unsafe.inject x |])

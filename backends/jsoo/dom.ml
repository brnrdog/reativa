(* Low-level DOM bindings via the js_of_ocaml FFI.

   One of the two implementations of the [Dom] virtual module declared by
   src/dom.mli; the other is backends/melange/dom.ml. Both satisfy the same
   signature, so the entire reactive core (Signal/Computed/Effect/scheduler)
   and the [View] layer above it compile against either one unchanged.

   That is the whole point: only this module and [History] are
   engine-specific. Swapping OCaml-to-JS engines is swapping these two files —
   the Melange version binds the browser DOM through [external ... [@@mel.*]],
   this version binds it through js_of_ocaml's [Js.Unsafe]. Everything else is
   backend-agnostic OCaml.

   NOTE: [classify] below assumes OCaml strings are JS strings, i.e. the
   js-string runtime that js_of_ocaml enables by default. Building a consumer
   with [--disable use-js-string] would make bare string children in JSX render
   as objects rather than text. See backends/jsoo/dune.

   Like the Melange version it keeps a single abstract node type [t] standing in
   for every kind of DOM node (elements, text nodes and comment anchors alike),
   and binds the handful of browser APIs the View layer needs untyped-on-purpose
   through [Js.Unsafe], rather than fighting js_of_ocaml's typed [Dom_html]. *)

open Js_of_ocaml

type t = Js.Unsafe.any
type event = Js.Unsafe.any

(* Resolved per call rather than captured at module initialisation, so this
   matches Melange's [@@mel.scope "document"] — which emits [document.foo(...)]
   at the call site. Capturing it once would freeze whatever [document] happened
   to exist when the linked script was evaluated, which differs under a jsdom
   harness, in a worker, or in any non-browser host. *)
let document () : Js.Unsafe.any = Js.Unsafe.get Js.Unsafe.global "document"

(* ----- creating nodes ----- *)

let create_element (tag : string) : t =
  Js.Unsafe.meth_call (document ()) "createElement" [| Js.Unsafe.inject (Js.string tag) |]

let create_text_node (s : string) : t =
  Js.Unsafe.meth_call (document ()) "createTextNode" [| Js.Unsafe.inject (Js.string s) |]

(* Comment nodes are invisible; the View layer uses them as stable anchors that
   mark where a reactive region's nodes should be (re)inserted. *)
let create_comment (s : string) : t =
  Js.Unsafe.meth_call (document ()) "createComment" [| Js.Unsafe.inject (Js.string s) |]

let by_id (id : string) : t option =
  (* getElementById returns null when nothing matches; [Js.Opt.to_option] maps
     that JS null to [None]. *)
  let node : t Js.opt =
    Js.Unsafe.meth_call (document ()) "getElementById" [| Js.Unsafe.inject (Js.string id) |]
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

(* The JS helpers below are bound once, at module level, with [pure_js_expr]
   rather than inline with [js_expr]. [js_expr] is impure as far as
   js_of_ocaml is concerned, so it is re-evaluated at every call site — for the
   [typeof] wrapper that means allocating a fresh closure on every [View.child]
   coercion. [pure_js_expr] lets the expression be evaluated once and shared. *)
let typeof_fn : Js.Unsafe.any = Js.Unsafe.pure_js_expr "(function (v) { return typeof v; })"
let string_fn : Js.Unsafe.any = Js.Unsafe.pure_js_expr "String"
let decode_uri_component_fn : Js.Unsafe.any = Js.Unsafe.pure_js_expr "decodeURIComponent"

(* Kept private to this implementation: the backend contract (src/dom.mli)
   exposes the classified form below, not the raw JS string. *)
let raw_typeof (x : 'a) : string =
  Js.to_string (Js.Unsafe.fun_call typeof_fn [| Js.Unsafe.inject x |])

(* js_of_ocaml agrees with Melange on the classes [View.child] actually
   contracts for: OCaml strings are JS strings (the default js-string runtime),
   ints and floats are JS numbers, closures are JS functions, and blocks —
   including every non-constant [View.t] — are JS objects.

   It cannot agree on the rest, and does not pretend to. OCaml [None], [false]
   and [0] are all the JS number [0] here, so they classify as [`Number]; there
   is no runtime test that could separate them. [`Boolean] and [`Undefined] are
   therefore unreachable on this backend — see the note in src/dom.mli. *)
let classify (x : 'a) =
  match raw_typeof x with
  | "string" -> `String
  | "number" | "bigint" -> `Number
  | "boolean" -> `Boolean
  | "function" -> `Function
  | "undefined" -> `Undefined
  | "object" -> `Object
  | _ -> `Other

(* JS [String(x)]: canonical display form for numbers and booleans. *)
let display_string (x : 'a) : string =
  Js.to_string (Js.Unsafe.fun_call string_fn [| Js.Unsafe.inject x |])

(* ----- URI decoding ----- *)

let decode_uri_component (s : string) : string =
  Js.to_string
    (Js.Unsafe.fun_call decode_uri_component_fn [| Js.Unsafe.inject (Js.string s) |])

(* ----- event modifier/state accessors (used by Router) -----

   The js_of_ocaml counterparts of the Melange [@@mel.get] externals in
   src/dom.ml. event.button is a small integer, which js_of_ocaml represents as
   a plain OCaml int, so no conversion is needed. *)

let default_prevented (ev : event) : bool =
  Js.to_bool (Js.Unsafe.get ev "defaultPrevented" : bool Js.t)

let mouse_button (ev : event) : int = Js.Unsafe.get ev "button"
let meta_key (ev : event) : bool = Js.to_bool (Js.Unsafe.get ev "metaKey" : bool Js.t)
let ctrl_key (ev : event) : bool = Js.to_bool (Js.Unsafe.get ev "ctrlKey" : bool Js.t)
let shift_key (ev : event) : bool = Js.to_bool (Js.Unsafe.get ev "shiftKey" : bool Js.t)
let alt_key (ev : event) : bool = Js.to_bool (Js.Unsafe.get ev "altKey" : bool Js.t)

(* Low-level DOM bindings via Melange FFI — no external dependencies.

   Everything here is a thin, untyped-on-purpose binding over the browser DOM.
   A single abstract type [t] stands in for every kind of DOM node (elements,
   text nodes and comment anchors alike): the JS APIs we use don't care about
   the distinction, and keeping one type makes the {!View} layer simpler.

   This module compiles only under Melange (it speaks to the browser), which is
   why the UI layer lives in its own [reativa_ui] library rather than inside the
   plain-OCaml [reativa] core. *)

type t
type event

(* ----- creating nodes ----- *)

external create_element : string -> t = "createElement"
  [@@mel.scope "document"]

external create_text_node : string -> t = "createTextNode"
  [@@mel.scope "document"]

(* Comment nodes are invisible; the View layer uses them as stable anchors that
   mark where a reactive region's nodes should be (re)inserted. *)
external create_comment : string -> t = "createComment"
  [@@mel.scope "document"]

external by_id : string -> t option = "getElementById"
  [@@mel.scope "document"] [@@mel.return nullable]

(* ----- tree manipulation ----- *)

external append_child : t -> t -> unit = "appendChild" [@@mel.send]

(* [insert_before parent node ref]: insert [node] as a child of [parent],
   immediately before the existing child [ref]. *)
external insert_before : t -> t -> t -> unit = "insertBefore" [@@mel.send]

external remove_child : t -> t -> unit = "removeChild" [@@mel.send]

(* ----- attributes & content ----- *)

external set_attribute : t -> string -> string -> unit = "setAttribute"
  [@@mel.send]

external remove_attribute : t -> string -> unit = "removeAttribute"
  [@@mel.send]

(* Setting [textContent] on a text node replaces its text; on an element it
   replaces all children with a single text node. *)
external set_text_content : t -> string -> unit = "textContent" [@@mel.set]

external set_value : t -> string -> unit = "value" [@@mel.set]

(* ----- events ----- *)

external add_event_listener : t -> string -> (event -> unit) -> unit
  = "addEventListener"
  [@@mel.send]

external prevent_default : event -> unit = "preventDefault" [@@mel.send]

(* Convenience reader for [event.target.value] (e.g. text inputs). *)
external target : event -> t = "target" [@@mel.get]
external value : t -> string = "value" [@@mel.get]

let target_value ev = value (target ev)

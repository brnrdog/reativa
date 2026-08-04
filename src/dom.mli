(* The DOM backend contract.

   This is a dune *virtual module*: [src/] declares the signature, and each
   backend ships an implementation ([backends/melange/dom.ml] binds the browser
   DOM through Melange's [external ... [@@mel.*]] FFI; [backends/jsoo/dom.ml]
   binds it through js_of_ocaml's [Js.Unsafe]). {!View} and {!Router} compile
   against this signature alone, so they carry no FFI and stay
   backend-agnostic.

   Everything here is a thin, untyped-on-purpose binding over the browser DOM.
   A single abstract type {!t} stands in for every kind of DOM node (elements,
   text nodes and comment anchors alike): the JS APIs we use don't care about
   the distinction, and keeping one type makes the {!View} layer simpler.

   Adding a value here obliges *every* backend to implement it, so keep this
   surface to what {!View} and {!Router} genuinely need. *)

(* A DOM node: element, text node or comment anchor. *)
type t

(* A DOM event, as delivered to a listener registered by
   {!add_event_listener}. *)
type event

(* ----- creating nodes ----- *)

val create_element : string -> t
val create_text_node : string -> t

(* Comment nodes are invisible; the View layer uses them as stable anchors that
   mark where a reactive region's nodes should be (re)inserted. *)
val create_comment : string -> t

(* [None] when no element carries the id. *)
val by_id : string -> t option

(* ----- tree manipulation ----- *)

val append_child : t -> t -> unit

(* [insert_before parent node ref]: insert [node] as a child of [parent],
   immediately before the existing child [ref]. *)
val insert_before : t -> t -> t -> unit

val remove_child : t -> t -> unit
val next_sibling : t -> t option
val is_same_node : t -> t -> bool

(* ----- attributes & content ----- *)

val set_attribute : t -> string -> string -> unit
val remove_attribute : t -> string -> unit

(* Setting [textContent] on a text node replaces its text; on an element it
   replaces all children with a single text node. *)
val set_text_content : t -> string -> unit

(* [value] and [checked] are *properties*, not attributes: setting the
   attribute would only change the default, not the live control state. *)
val set_value : t -> string -> unit
val set_checked : t -> bool -> unit

(* ----- events ----- *)

val add_event_listener : t -> string -> (event -> unit) -> unit
val prevent_default : event -> unit
val key : event -> string
val target : event -> t
val value : t -> string

(* Convenience reader for [event.target.value] (e.g. text inputs). *)
val target_value : event -> string

val log : 'a -> unit

(* ----- runtime value inspection (used by [View.child]) ----- *)

(* Classify the *JavaScript representation* of an OCaml value, so {!View.child}
   can decide what to build for a bare JSX child.

   Each backend answers for its own value mapping, which is why this is part of
   the backend contract rather than a shared helper: Melange and js_of_ocaml
   represent OCaml values differently, and only the backend knows how.

   A polymorphic variant (rather than a shared [type]) keeps implementations
   independent — there is no definition for them to agree on, only the
   signature below.

   IMPORTANT: backends agree on [`String], [`Number], [`Function] and
   [`Object], and that intersection is exactly the contract {!View.child}
   documents. They do *not* agree on OCaml options and booleans: js_of_ocaml
   represents [None], [false] and [0] as the same JS value, so no
   implementation can tell them apart. Do not add meaning to [`Boolean] or
   [`Undefined] that a caller is expected to rely on. *)
val classify :
  'a ->
  [ `String | `Number | `Boolean | `Function | `Undefined | `Object | `Other ]

(* JS [String(x)]: canonical display form for numbers and booleans. *)
val display_string : 'a -> string

(* ----- URI decoding ----- *)

(* The browser's [decodeURIComponent].

   This is part of the backend contract rather than a helper in
   {!Router_match} because percent-decoding is representation-sensitive:
   decoding "%C3%A9" to "é" requires producing a string element above 255,
   which OCaml's [string]/[Char] API cannot express where strings are JS
   strings. The platform's own decoder is the only portable answer.

   {!Router} passes this to {!Router_match.match_path}; the pure byte-level
   fallback there is what keeps route matching natively testable. *)
val decode_uri_component : string -> string

(* ----- event modifier/state accessors -----

   Read by {!Router} to decide whether a link click should be handled as an SPA
   navigation. They live here (rather than inline in the router) so the router
   itself carries no FFI. *)

val default_prevented : event -> bool
val mouse_button : event -> int
val meta_key : event -> bool
val ctrl_key : event -> bool
val shift_key : event -> bool
val alt_key : event -> bool

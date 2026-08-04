(* The browser history/location backend contract.

   A dune *virtual module*, like {!Dom}: [src/] declares the signature and each
   backend implements it ([backends/melange/history.ml] via Melange externals,
   [backends/jsoo/history.ml] via js_of_ocaml's [Js.Unsafe]). Keeping the
   history/location FFI behind this signature is what lets {!Router} carry the
   routing *logic* only, with no FFI of its own.

   The surface is deliberately narrow: only what {!Router} uses today. It is a
   public contract — every backend must implement whatever is added here — so
   prefer extending {!Router} over widening this module. Notably absent, and
   deliberately out of scope for now: [scrollRestoration], hash-routing mode
   and [beforeunload] navigation guards. *)

(* An opaque history entry state value, as stored by [pushState]/
   [replaceState] and read back from [history.state]. *)
type state

(* A value that may be absent, mapping to JS [null]/[undefined]. *)
type 'a nullable

val nullable_of_option : 'a option -> 'a nullable

(* History state is passed through opaquely: it is written by [encode_state]
   and read back by [decode_state] at the caller's chosen type. Round-tripping
   at a *different* type is unchecked and unsound — {!Router} exposes these as
   [Router.state]/[Router.state_value] with the same caveat. *)
val encode_state : 'a -> state
val decode_state : state -> 'a

type window
type history
type location_target
type pop_state_event

val window : unit -> window
val history : window -> history
val browser_location : window -> location_target

(* ----- location readers ----- *)

val href : location_target -> string
val origin : location_target -> string
val pathname : location_target -> string
val search : location_target -> string
val hash : location_target -> string

(* [None] when the current entry has no state (JS [null]/[undefined]). *)
val history_state : history -> state option

(* ----- navigation ----- *)

(* [push_state hist state title url] / [replace_state hist state title url] *)
val push_state : history -> state nullable -> string -> string -> unit
val replace_state : history -> state nullable -> string -> string -> unit
val go_history : history -> int -> unit
val back_history : history -> unit
val forward_history : history -> unit

val add_popstate_listener : window -> string -> (pop_state_event -> unit) -> unit

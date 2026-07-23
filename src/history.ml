(* Browser history / location FFI (Melange).

   Extracted from {!Router} so the routing *logic* carries no FFI and stays
   engine-agnostic: this is the only history/location-specific module, and a
   js_of_ocaml build swaps just this file (see examples/jsoo/history.ml) exactly
   as it swaps {!Dom}. The router depends only on this signature.

   Bound through the shipped runtime helper (see reativa_runtime.js) for the
   window/undefined lookups: melange primitive spellings like "#undefined" are
   not valid symbols for the native toolchain, which also compiles (but never
   links) this module. *)

type state
type 'a nullable

external nullable_undefined : unit -> 'a nullable = "getUndefined"
  [@@mel.module "./reativa_runtime.js"]

external nullable_return : 'a -> 'a nullable = "%identity"
external encode_state : 'a -> state = "%identity"
external decode_state : state -> 'a = "%identity"

let nullable_of_option = function
  | None -> nullable_undefined ()
  | Some value -> nullable_return value

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

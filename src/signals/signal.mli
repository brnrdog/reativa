(** Mutable reactive state. *)

(* The representation lives in the internal Signal_core module, which is not
   re-exported: outside the library a signal is opaque. *)
type 'a t = 'a Signal_core.t

(** [make ?name ?equals v]. [equals] decides whether a write is a change
    (default: physical equality); an equal write notifies nobody. *)
val make : ?name:string -> ?equals:('a -> 'a -> bool) -> 'a -> 'a t

(** The current value, tracked as a dependency of the running computed or
    effect. *)
val get : 'a t -> 'a

(** The current value, untracked. *)
val peek : 'a t -> 'a

val set : 'a t -> 'a -> unit
val update : 'a t -> ('a -> 'a) -> unit
val name : 'a t -> string option

(** Run [f] with notifications held until it returns, so effects run once
    for all the writes it made. *)
val batch : (unit -> 'a) -> 'a

(** Run [f] without tracking the reads it makes. *)
val untrack : (unit -> 'a) -> 'a

(** How many computeds and effects currently read this signal. For tests
    and tooling. *)
val subscriber_count : 'a t -> int

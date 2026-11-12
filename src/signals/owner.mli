(** Ownership: the tree of scopes that disposes effects, computeds and
    cleanups. Components, keyed rows, effect runs and mounted roots each have
    an owner; most code never touches this module directly and uses
    {!View.on_cleanup} instead. *)

type t

(** The owner new effects and cleanups register with, if any. *)
val active : unit -> t option

(** A new owner whose parent (for context lookups and error handling) is
    [parent], by default the active one. It is not disposed with its
    parent: the caller decides when to {!dispose} it. *)
val make : ?parent:t option -> unit -> t

(** A new owner disposed together with the active one. *)
val make_child : unit -> t

(** Run [f] with the given owner active ([None]: no owner). *)
val run : t option -> (unit -> 'a) -> 'a

val run_in : t -> (unit -> 'a) -> 'a

(** Register a cleanup with the active owner; dropped when there is none. *)
val on_cleanup : (unit -> unit) -> unit

val add_cleanup : t -> (unit -> unit) -> unit

(** Run the cleanups registered so far and keep the owner usable. *)
val reset : t -> unit

val dispose : t -> unit
val is_disposed : t -> bool

(** {2 Values scoped to a subtree} *)

type 'a key

(** A new key whose lookups return [default] where nothing provides it. *)
val new_key : 'a -> 'a key

val provide : t -> 'a key -> 'a -> unit

(** The value provided by the nearest owner from [from] (default: the
    active one) upwards. *)
val lookup : ?from:t option -> 'a key -> 'a

(** {2 Errors} *)

(** Errors raised by effects owned (transitively) by this owner go to
    [handler]. *)
val set_error_handler : t -> (exn -> unit) -> unit

(** Hand an exception to the nearest handler from [from] upwards; re-raise
    it when there is none. *)
val handle_error : ?from:t option -> exn -> unit

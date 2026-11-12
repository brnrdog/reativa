(** Side effects that re-run when what they read changes. *)

type disposer = { dispose : unit -> unit }

(** [run f] runs [f] now and again whenever a signal it read changes. [f]
    may return a cleanup, run before the next run and on dispose. The effect
    is disposed with the current {!Owner}, and owns whatever [f] creates:
    that is disposed before each re-run. *)
val run : ?name:string -> (unit -> (unit -> unit) option) -> unit

val run_with_disposer : ?name:string -> (unit -> (unit -> unit) option) -> disposer

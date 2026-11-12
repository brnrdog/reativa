(** Derived state: a read-only signal whose value is computed from others. It
    recomputes lazily, on the first read after a dependency changed, and lets
    go of its dependencies while nothing reads it. *)

(** [make ?name ?equals f]. With [equals], an unchanged result stops the
    update there: nothing downstream re-runs. *)
val make : ?name:string -> ?equals:('a -> 'a -> bool) -> (unit -> 'a) -> 'a Signal.t

(** Detach from all dependencies. A later read recomputes. *)
val dispose : 'a Signal.t -> unit

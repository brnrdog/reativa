(** Asynchronous data as a signal.

    {[
      let user_id = Signal.make "1"

      let user =
        Resource.make (fun () ->
          let id = Signal.get user_id in   (* a dependency: read before the promise *)
          fetch_user id)                   (* a promise from your backend's APIs *)

      let view =
        View.dyn (fun () ->
          match Resource.state user with
          | Resource.Ready u -> <p>(u.name)</p>
          | Loading _ -> <p>("Loading…")</p>
          | Failed _ -> <p>("Could not load the user")</p>)
    ]}

    The fetcher runs in an effect, so the signals it reads before returning
    its promise are dependencies: changing one starts a new fetch. A result
    that arrives after a newer fetch started, or after the resource's owner
    was disposed, is dropped. Inside a {!View.suspense}, a loading resource
    keeps the suspense's fallback up. *)

type 'a state =
  | Loading of 'a option  (** in flight; carries the previous value, if any *)
  | Ready of 'a
  | Failed of exn  (** a JS rejection reason that is not an OCaml exception is
                       {!Promise.Rejected} *)

type 'a t

(** Start fetching now, and again whenever a dependency changes. *)
val make : (unit -> 'a Promise.t) -> 'a t

(** The current state, tracked. *)
val state : 'a t -> 'a state

(** The current state, untracked. *)
val peek : 'a t -> 'a state

(** Fetch again with the same dependencies. *)
val refetch : 'a t -> unit

(** Replace the value locally (e.g. an optimistic update); a fetch in flight
    is dropped. *)
val mutate : 'a t -> 'a -> unit

(** The value when ready, or the previous one while reloading. *)
val value : 'a state -> 'a option

val is_loading : 'a state -> bool
val error : 'a state -> exn option

(** What the reactive graph is doing: which signals were written, which
    computeds recomputed and which effects ran, why, and which DOM node an
    effect writes to.

    {[
      let () =
        Devtools.install ();
        Devtools.expose ();          (* for reativa-inspect and the browser console *)
        View.mount_by_id "app" app
    ]}

    Install it before creating what you want to see: only nodes created
    while it is installed are tracked. Until it is installed the library
    records nothing and the only cost is one boolean test at each
    instrumentation point; an app that never references this module does not
    ship it (Melange emits one module per file, and js_of_ocaml removes dead
    code). *)

type kind = Signal | Computed | Effect

type node_info = {
  id : int;
  kind : kind;
  name : string option;  (** the [?name] given to [Signal.make] and friends *)
  subscribers : int;
  dependencies : int list;
  disposed : bool;
}

type event =
  | Created of { id : int; kind : kind; name : string option }
  | Written of { id : int; name : string option; value : string }  (** a preview of the new value *)
  | Recomputed of { id : int; name : string option }
  | Ran of { id : int; name : string option }
  | Disposed of { id : int; name : string option }

(** Start tracking, keeping the last [history] events (default 1000). *)
val install : ?history:int -> unit -> unit

(** Stop tracking and forget everything recorded. *)
val uninstall : unit -> unit

val installed : unit -> bool

(** Call [f] on every event from now on; returns the unsubscribe function. *)
val subscribe : (event -> unit) -> unit -> unit

(** Run [f] without recording its events. Nodes created while muted (tooling
    such as the devtools panel) are also left out of {!snapshot}, {!leaks}
    and the element lookups. *)
val mute : (unit -> 'a) -> 'a

val history : unit -> event list
val clear_history : unit -> unit

(** Every tracked node that is not disposed, by id. *)
val snapshot : unit -> node_info list

val inspect : int -> node_info option

(** The preview of a signal's last written value. *)
val value : int -> string option

type counts = { writes : int; recomputes : int; runs : int; created : int; disposed : int }
type trace = { events : event list; counts : counts }

(** Run [f] and return what it caused. *)
val record : (unit -> unit) -> trace

(** {2 Causes} *)

type action =
  | Written_by_user  (** a signal written by the application *)
  | Recomputed_from  (** a computed, recomputed from its [because] *)
  | Ran_after  (** an effect, run after its [because] changed *)

type cause = {
  node : node_info;
  action : action;
  value : string option;
  because : cause option;
}

(** Why a node last changed or ran, back to the signal write that started
    it. *)
val why : int -> cause option

(** {2 The DOM} *)

(** The effects that write to this DOM node or to its own text children, with
    what they write ("text", or an attribute or property name). *)
val effects_writing : Dom.t -> (int * string) list

(** The DOM node an effect writes to, and what it writes. *)
val target_of : int -> (Dom.t * string) option

(** The signals whose writes reach this DOM node. *)
val writers_of : Dom.t -> int list

(** Effects that are alive but read nothing, so can never run again. *)
val leaks : unit -> node_info list

(** A short preview of any value: strings quoted, numbers and booleans
    printed, anything else ["<value>"]. *)
val preview : 'a -> string

(** Make the devtools reachable from JavaScript as [globalThis.\[name\]]
    (default ["__reativaDevtools"]): [snapshot()], [history()],
    [clearHistory()], [why(id)], [whyElement(el)] and [leaks()], each
    returning JSON. reativa-inspect drives an app through it. *)
val expose : ?name:string -> unit -> unit

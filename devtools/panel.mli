(** An in-page devtools panel: live counts of signals, computeds and effects,
    the latest events, effects that can never run again, and an inspect mode
    that explains why the element you click shows what it shows.

    {[
      let () =
        Reativa.Devtools.install ();
        View.mount_by_id "app" app;
        Reativa_devtools.Panel.mount ()
    ]}

    Installs {!Reativa.Devtools} if it is not installed yet. The panel's own
    signals and effects are created and updated with recording muted, so it
    never reports on itself. *)

(** Mount the panel into [target] (default: a new element appended to
    <body>). Returns a function that removes it. *)
val mount : ?target:Reativa.Dom.t -> ?open_:bool -> unit -> unit -> unit

(* Devtools instrumentation points (internal).

   The reactive core and the renderer call these at the moments devtools care
   about. Until devtools are installed ([Reativa.Devtools.install]) every call
   site costs one test of [enabled]; nothing is recorded and nothing is
   retained. *)

type hooks = {
  created : Core.node -> unit;
  (* A signal write that changed the value; the new value, untyped. *)
  written : Core.node -> Obj.t -> unit;
  recomputed : Core.node -> unit;
  ran : Core.node -> unit;
  disposed : Core.node -> unit;
  (* An effect that writes to a DOM node: the node, and what it writes
     ("text", or an attribute or property name). *)
  bound : Core.node -> Obj.t -> string -> unit;
}

let enabled = ref false

let noop =
  {
    created = ignore;
    written = (fun _ _ -> ());
    recomputed = ignore;
    ran = ignore;
    disposed = ignore;
    bound = (fun _ _ _ -> ());
  }

let hooks = ref noop

let install h =
  hooks := h;
  enabled := true

let uninstall () =
  enabled := false;
  hooks := noop

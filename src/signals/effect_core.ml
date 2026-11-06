(* A side effect that re-runs whenever any signal it reads changes. The effect
   body may return a cleanup function, which runs before the next re-run and on
   dispose.

   Ownership (see {!Owner}): an effect created while an owner is current is
   disposed with that owner. The effect is itself an owner for whatever its
   body creates — nested effects, computeds, [Owner.on_cleanup] callbacks —
   and resets it before every re-run, so each run starts from a clean slate.

   An exception raised by the body goes to the nearest error handler above the
   effect ({!Owner.handle_error}); with none, it propagates as before. *)
type disposer = { dispose : unit -> unit }

let make ?name ?target ~owned fn =
  let id = Id.make () in
  let parent = Owner.active () in
  let owner = if owned then Some (Owner.make ()) else None in
  let cleanup : (unit -> unit) option ref = ref None in
  let run_cleanup () =
    match !cleanup with
    | Some c ->
      cleanup := None;
      c ()
    | None -> ()
  in
  (* Run the previous cleanup, reset what the previous run owned, then the
     body, storing its new cleanup. *)
  let run_with_cleanup () =
    run_cleanup ();
    (match owner with Some o -> Owner.reset o | None -> ());
    match Owner.run owner fn with
    | next -> cleanup := next
    | exception e -> Owner.handle_error ~from:(match owner with Some _ -> owner | None -> parent) e
  in
  let node = Core.make_effect_node ~id ~name ~run:run_with_cleanup in
  let disposed = ref false in
  let dispose () =
    if not !disposed then begin
      disposed := true;
      if !Trace.enabled then !Trace.hooks.disposed node;
      Core.set_disposed node;
      Core.clear_deps node;
      run_cleanup ();
      match owner with Some o -> Owner.dispose o | None -> ()
    end
  in
  Owner.on_cleanup dispose;
  if !Trace.enabled then begin
    !Trace.hooks.created node;
    (match target with Some (el, what) -> !Trace.hooks.bound node el what | None -> ());
    !Trace.hooks.ran node
  end;
  (* Initial run under tracking to establish dependencies. [with_tracking]
     also restores the dependency cursor, which a node created inside this run
     moves. *)
  Scheduler.with_tracking node run_with_cleanup;
  Core.clear_dirty node;
  node.level <- Scheduler.compute_level node;
  { dispose }

let run_with_disposer ?name fn = make ?name ~owned:true fn
let run ?name fn = ignore (make ?name ~owned:true fn)

(* An effect that owns nothing: its body runs with no current owner, so
   anything it creates is not tied to it. For renderer leaves — a text node or
   an attribute that only reads signals and writes the DOM — this saves an
   owner per leaf. It is still disposed with the current owner. *)
let leaf ?name ?target fn = make ?name ?target ~owned:false fn

(* A derived, read-only signal. It is represented by the same {!Signal.t}
   record as a writable signal, but its [node] carries a [compute] closure and
   participates in the graph as both a source and an observer. Reading it lazily
   refreshes the value when a dependency has changed (see
   {!Scheduler.ensure_computed_fresh}). *)

(* Initial computation under tracking to establish dependencies.
   [with_tracking] also restores the dependency cursor, which a node created
   inside [compute] moves. *)
let initial_run node compute =
  let value = ref None in
  Scheduler.with_tracking node (fun () -> value := Some (compute ()));
  match !value with Some v -> v | None -> assert false

let make_without_equals ?name compute =
  let id = Id.make () in
  let signal_ref : 'a Signal.t ref = ref (Obj.magic ()) in
  (* Fast path: no custom equality, so every recompute is treated as a change. *)
  let recompute () =
    let signal = !signal_ref in
    signal.value <- compute ();
    signal.node.version <- signal.node.version + 1
  in
  let node = Core.make_computed_node ~id ~name ~defer_effects_until_recompute:false in
  node.compute <- Some recompute;
  let initial_value = initial_run node compute in
  let signal : 'a Signal.t =
    { value = initial_value; equals = Signal.never_equals; name; node }
  in
  signal_ref := signal;
  node.last_global_version <- !Core.global_version;
  Core.clear_dirty node;
  signal

let make_with_equals ?name compute equals =
  let id = Id.make () in
  let signal_ref : 'a Signal.t ref = ref (Obj.magic ()) in
  let recompute () =
    let signal = !signal_ref in
    let previous = signal.value in
    let next = compute () in
    let should_update = try not (signal.equals previous next) with _ -> true in
    if should_update then begin
      signal.value <- next;
      signal.node.version <- signal.node.version + 1
    end
  in
  let node = Core.make_computed_node ~id ~name ~defer_effects_until_recompute:true in
  node.compute <- Some recompute;
  let initial_value = initial_run node compute in
  let signal : 'a Signal.t = { value = initial_value; equals; name; node } in
  signal_ref := signal;
  node.last_global_version <- !Core.global_version;
  Core.clear_dirty node;
  signal

let make ?name ?equals compute =
  match equals with
  | Some eq -> make_with_equals ?name compute eq
  | None -> make_without_equals ?name compute

(* Detach the computed from its dependencies; it will no longer update. *)
let dispose (signal : 'a Signal.t) = Core.clear_deps signal.node

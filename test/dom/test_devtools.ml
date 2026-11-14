(* Devtools: events, traces, causes and DOM bindings. *)

open Reativa
open Harness

let with_devtools f () =
  Devtools.install ();
  match f () with
  | () -> Devtools.uninstall ()
  | exception e ->
    Devtools.uninstall ();
    raise e

let register () =
  suite "Devtools";
  test "nothing is tracked until installed"
    (fun () ->
      let s = Signal.make ~name:"before" 0 in
      Signal.set s 1;
      check "not installed" (not (Devtools.installed ()));
      Devtools.install ();
      check "nothing from before" (Devtools.snapshot () = [] && Devtools.history () = []);
      Devtools.uninstall ());
  test "a trace counts what an interaction caused"
    (with_devtools (fun () ->
       let count = Signal.make ~name:"count" 0 in
       let doubled = Computed.make ~name:"doubled" (fun () -> Signal.get count * 2) in
       let _c = mount (View.p [ View.int (View.signal doubled) ]) in
       let trace = Devtools.record (fun () -> Signal.set count 1) in
       equal_int "one write" ~expected:1 trace.counts.writes;
       equal_int "one recompute" ~expected:1 trace.counts.recomputes;
       equal_int "one run" ~expected:1 trace.counts.runs;
       check "the write carries a preview"
         (List.exists (function Devtools.Written { value = "1"; name = Some "count"; _ } -> true | _ -> false) trace.events)));
  test "why follows a DOM update back to the write"
    (with_devtools (fun () ->
       let count = Signal.make ~name:"count" 0 in
       let label = Computed.make ~name:"label" (fun () -> "n=" ^ string_of_int (Signal.get count)) in
       let c = mount (View.p ~attrs:[ View.Attr.class_reactive (fun () -> Signal.get label) ] []) in
       Signal.set count 3;
       let p = Option.get (Probe.query c "p") in
       match Devtools.effects_writing p with
       | [ (effect, what) ] -> (
         equal_string "writes the class" ~expected:"class" what;
         match Devtools.why effect with
         | Some { action = Ran_after; because = Some { node = { name = Some "label"; _ }; action = Recomputed_from; because = Some { node = { name = Some "count"; _ }; value = Some "3"; _ }; _ }; _ } ->
           check "effect <- computed <- write" true;
           check "writers_of names the signal"
             (List.map (fun id -> (Option.get (Devtools.inspect id)).name) (Devtools.writers_of p) = [ Some "count" ])
         | _ -> check "cause chain" false)
       | l -> check (Printf.sprintf "one effect writes the <p> (got %d)" (List.length l)) false));
  test "snapshot, dispose and leaks"
    (with_devtools (fun () ->
       let visible = Signal.make ~name:"visible" true in
       let _c = mount (View.show (fun () -> Signal.get visible) (View.p [ View.dyn_text (fun () -> "x") ])) in
       let effects () = List.length (List.filter (fun (n : Devtools.node_info) -> n.kind = Effect) (Devtools.snapshot ())) in
       let before = effects () in
       Signal.set visible false;
       check "disposed effects leave the snapshot" (effects () < before);
       Effect.run (fun () -> None);
       equal_int "an effect that reads nothing is reported" ~expected:1 (List.length (Devtools.leaks ()))));
  test "mute hides events"
    (with_devtools (fun () ->
       let s = Signal.make 0 in
       Devtools.clear_history ();
       Devtools.mute (fun () -> Signal.set s 1);
       equal_int "no events" ~expected:0 (List.length (Devtools.history ()))))

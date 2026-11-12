(* Entry point of the jsdom suites. Each module registers its tests; [run]
   executes them in order and reports to test/dom/run.mjs. *)

let () =
  Test_view.register ();
  Test_ownership.register ();
  Test_attributes.register ();
  Harness.run ()

(* Ownership in the rendered tree: components are lazy, untracked and own
   what they create; regions and keyed rows dispose what they owned. *)

open Reativa
open Harness

let register () =
  suite "Ownership: components";
  test "a component body runs at mount, not when the view is built" (fun () ->
    let ran = ref 0 in
    let view = View.component (fun () -> incr ran; View.text (View.static "x")) in
    equal_int "not yet" ~expected:0 !ran;
    let c = mount view in
    equal_int "ran once at mount" ~expected:1 !ran;
    equal_string "rendered" ~expected:"x" (html c));
  test "a component body is untracked" (fun () ->
    let s = Signal.make 0 in
    let region_runs = ref 0 in
    let _c =
      mount
        (View.dyn (fun () ->
           incr region_runs;
           View.component (fun () -> View.int (View.static (Signal.get s)))))
    in
    Signal.set s 1;
    equal_int "the region did not re-render" ~expected:1 !region_runs);
  test "effects created in a component die with it" (fun () ->
    let visible = Signal.make true and s = Signal.make 0 in
    let runs = ref 0 and cleaned = ref 0 in
    let comp =
      View.component (fun () ->
        Effect.run (fun () ->
          ignore (Signal.get s);
          incr runs;
          None);
        Owner.on_cleanup (fun () -> incr cleaned);
        View.text (View.static "c"))
    in
    let _c = mount (View.show (fun () -> Signal.get visible) comp) in
    Signal.set s 1;
    equal_int "effect live while mounted" ~expected:2 !runs;
    Signal.set visible false;
    equal_int "cleanup ran on removal" ~expected:1 !cleaned;
    Signal.set s 2;
    equal_int "effect disposed with the component" ~expected:2 !runs);
  test "computeds created in a component are released with it" (fun () ->
    let visible = Signal.make true and src = Signal.make 1 in
    let comp =
      View.component (fun () ->
        let doubled = Computed.make (fun () -> Signal.get src * 2) in
        View.int (View.signal doubled))
    in
    let c = mount (View.show (fun () -> Signal.get visible) comp) in
    equal_string "rendered" ~expected:"2<!---->" (html c);
    Signal.set visible false;
    check "source released" (Signal.subscriber_count src = 0));

  suite "Ownership: keyed rows";
  test "a removed row disposes its effects" (fun () ->
    let items = Signal.make [ 1; 2 ] and tick = Signal.make 0 in
    let runs = Hashtbl.create 4 in
    let bump k = Hashtbl.replace runs k (1 + Option.value ~default:0 (Hashtbl.find_opt runs k)) in
    let _c =
      mount
        (View.for_with_key (fun () -> Signal.get items) ~key:string_of_int (fun item ->
           let k = Signal.peek item in
           Effect.run (fun () ->
             ignore (Signal.get tick);
             bump k;
             None);
           View.int (View.signal item)))
    in
    Signal.set items [ 2 ];
    Signal.set tick 1;
    equal_int "row 1 effect stopped" ~expected:1 (Hashtbl.find runs 1);
    equal_int "row 2 effect still runs" ~expected:2 (Hashtbl.find runs 2));
  test "a row's render function is untracked" (fun () ->
    let items = Signal.make [ 1 ] and other = Signal.make 0 in
    let renders = ref 0 in
    let _c =
      mount
        (View.for_with_key (fun () -> Signal.get items) ~key:string_of_int (fun item ->
           incr renders;
           ignore (Signal.get other);
           View.int (View.signal item)))
    in
    Signal.set other 1;
    equal_int "reading in render does not re-run the list" ~expected:1 !renders);

  suite "Ownership: mount";
  test "mount_disposable disposes and removes everything" (fun () ->
    let s = Signal.make 0 and runs = ref 0 in
    let c = Probe.container () in
    let dispose =
      View.mount_disposable c
        (View.div
           [
             View.text
               (View.dynamic (fun () ->
                  incr runs;
                  string_of_int (Signal.get s)));
           ])
    in
    equal_string "mounted" ~expected:"<div>0</div>" (html c);
    dispose ();
    equal_string "removed" ~expected:"" (html c);
    Signal.set s 1;
    equal_int "effects disposed" ~expected:1 !runs)

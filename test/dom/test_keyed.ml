(* The keyed reconciler: correct order after any update, rows kept by key,
   and the minimum of DOM work for the common updates. *)

open Reativa
open Harness

let row_texts c = List.map Probe.text_content (Probe.query_all c "li")
let ints l = String.concat "," (List.map string_of_int l)
let strs l = String.concat "," l

let keyed_list items =
  View.ul
    [
      View.for_with_key (fun () -> Signal.get items) ~key:string_of_int (fun item ->
        View.li [ View.int (View.signal item) ]);
    ]

(* A small deterministic PRNG so the permutation test is reproducible. *)
let seed = ref 12345

let next_int bound =
  seed := (!seed * 1103515245 + 12345) land 0x3fffffff;
  !seed mod bound

let shuffle l =
  let a = Array.of_list l in
  for i = Array.length a - 1 downto 1 do
    let j = next_int (i + 1) in
    let t = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- t
  done;
  Array.to_list a

let register () =
  suite "Keyed lists: order and identity";
  test "any sequence of updates leaves the DOM in item order" (fun () ->
    let items = Signal.make [] in
    let c = mount (keyed_list items) in
    let ok = ref true in
    for _ = 1 to 60 do
      (* random subset of 0..19, in random order *)
      let next = List.filter (fun _ -> next_int 3 > 0) (List.init 20 Fun.id) |> shuffle in
      Signal.set items next;
      if strs (row_texts c) <> ints next then begin
        ok := false;
        check (Printf.sprintf "order after [%s]: got [%s]" (ints next) (strs (row_texts c))) false
      end
    done;
    check "sixty random updates" !ok);
  test "a surviving row keeps its DOM node" (fun () ->
    let items = Signal.make [ 1; 2; 3 ] in
    let c = mount (keyed_list items) in
    let second = List.nth (Probe.query_all c "li") 1 in
    Signal.set items [ 3; 2; 1; 4 ];
    let now = List.nth (Probe.query_all c "li") 1 in
    check "same node for key 2" (Dom.is_same_node second now);
    equal_string "order" ~expected:"3,2,1,4" (strs (row_texts c)));
  test "duplicate keys are an error" (fun () ->
    let items = Signal.make [ 1 ] in
    let _c = mount (keyed_list items) in
    raises "duplicate key raises" (fun () -> Signal.set items [ 2; 2 ]));
  test "for_ with raw items rebuilds a row whose item changed" (fun () ->
    let items = Signal.make [ (1, "a"); (2, "b") ] in
    let builds = ref 0 in
    let c =
      mount
        (View.ul
           [
             View.ForEach.component
               ~key:(fun (k, _) -> string_of_int k)
               ~items:(View.signal items)
               ~render:(fun (_, s) ->
                 incr builds;
                 View.li [ View.text (View.static s) ])
               ();
           ])
    in
    let first = List.hd (Probe.query_all c "li") in
    let unchanged = List.hd (Signal.peek items) in
    Signal.set items [ unchanged; (2, "B") ];
    equal_string "updated" ~expected:"a,B" (strs (row_texts c));
    equal_int "only the changed row was rebuilt" ~expected:3 !builds;
    check "unchanged row kept its node" (Dom.is_same_node first (List.hd (Probe.query_all c "li"))));

  suite "Keyed lists: DOM work";
  let thousand = List.init 1000 Fun.id in
  test "swapping two rows of a thousand moves two" (fun () ->
    let items = Signal.make thousand in
    let c = mount (keyed_list items) in
    let a = Array.of_list thousand in
    let t = a.(1) in
    a.(1) <- a.(998);
    a.(998) <- t;
    Probe.reset_ops ();
    Signal.set items (Array.to_list a);
    equal_int "insertBefore calls" ~expected:2 (Probe.ops "insertBefore");
    equal_string "order" ~expected:(ints (Array.to_list a)) (strs (row_texts c)));
  test "appending inserts the new rows with one call" (fun () ->
    let items = Signal.make thousand in
    let _c = mount (keyed_list items) in
    Probe.reset_ops ();
    Signal.set items (thousand @ List.init 10 (fun i -> 1000 + i));
    equal_int "insertBefore calls" ~expected:1 (Probe.ops "insertBefore"));
  test "removing a row moves nothing" (fun () ->
    let items = Signal.make thousand in
    let _c = mount (keyed_list items) in
    Probe.reset_ops ();
    Signal.set items (List.filter (fun i -> i <> 500) thousand);
    equal_int "insertBefore calls" ~expected:0 (Probe.ops "insertBefore");
    equal_int "one row removed" ~expected:1 (Probe.ops "remove" + Probe.ops "removeChild"));
  test "reversing moves all but one" (fun () ->
    let items = Signal.make (List.init 10 Fun.id) in
    let c = mount (keyed_list items) in
    Probe.reset_ops ();
    Signal.set items (List.rev (List.init 10 Fun.id));
    equal_int "insertBefore calls" ~expected:9 (Probe.ops "insertBefore");
    equal_string "order" ~expected:"9,8,7,6,5,4,3,2,1,0" (strs (row_texts c)));

  test "clearing a list that owns its parent empties it in one write" (fun () ->
    let items = Signal.make thousand in
    let c = mount (keyed_list items) in
    Probe.reset_ops ();
    Signal.set items [];
    equal_int "one textContent write" ~expected:1 (Probe.ops "textContent");
    equal_int "no per-row removal" ~expected:0 (Probe.ops "remove" + Probe.ops "removeChild");
    equal_string "only the anchor is left" ~expected:"<ul><!----></ul>" (html c);
    Signal.set items [ 1; 2 ];
    equal_string "and the list still works" ~expected:"1,2" (strs (row_texts c)));
  test "clearing a list that shares its parent keeps the siblings" (fun () ->
    let items = Signal.make [ 1; 2; 3 ] in
    let c =
      mount
        (View.ul
           [
             View.li [ View.text (View.static "first") ];
             View.for_with_key (fun () -> Signal.get items) ~key:string_of_int (fun item ->
               View.li [ View.int (View.signal item) ]);
           ])
    in
    Signal.set items [];
    equal_string "sibling kept" ~expected:"<ul><li>first</li><!----></ul>" (html c));

  test "a row that starts with a region moves with the region's content" (fun () ->
    let values = Hashtbl.create 2 in
    Hashtbl.replace values "a" (Signal.make 1);
    Hashtbl.replace values "b" (Signal.make 10);
    let items = Signal.make [ "a"; "b" ] in
    let c =
      mount
        (View.div
           [
             View.for_with_key (fun () -> Signal.get items) ~key:Fun.id (fun item ->
               let v = Hashtbl.find values (Signal.peek item) in
               View.fragment
                 [ View.dyn (fun () -> View.text (View.static (string_of_int (Signal.get v)))); View.element "i" [] ]);
           ])
    in
    Signal.set (Hashtbl.find values "a") 2;
    Signal.set items [ "b"; "a" ];
    equal_string "order and content" ~expected:"<div>10<!----><i></i>2<!----><i></i><!----></div>" (html c);
    Signal.set items [ "a"; "b" ];
    equal_string "and back" ~expected:"<div>2<!----><i></i>10<!----><i></i><!----></div>" (html c));

  suite "Leaves: skip equal writes";
  test "a class that does not change is not rewritten" (fun () ->
    let selected = Signal.make 0 in
    let rows = List.init 100 Fun.id in
    let _c =
      mount
        (View.ul
           (List.map
              (fun i ->
                View.li
                  ~attrs:
                    [ View.Attr.class_reactive (fun () -> if Signal.get selected = i then "on" else "") ]
                  [])
              rows))
    in
    Probe.reset_ops ();
    Signal.set selected 5;
    equal_int "two setAttribute calls" ~expected:2 (Probe.ops "setAttribute"));
  test "a thunk child returning a scalar updates its text node in place" (fun () ->
    let n = Signal.make 1 in
    let c = mount (View.p [ View.child (fun () -> Signal.get n) ]) in
    let node = Option.get (Probe.first_child (Option.get (Probe.query c "p"))) in
    Probe.reset_ops ();
    Signal.set n 2;
    equal_string "updated" ~expected:"<p>2<!----></p>" (html c);
    check "same text node" (Dom.is_same_node node (Option.get (Probe.first_child (Option.get (Probe.query c "p")))));
    equal_int "no node inserted" ~expected:0 (Probe.ops "insertBefore" + Probe.ops "createTextNode"))

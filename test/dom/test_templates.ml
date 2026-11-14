(* Templates: a parsed skeleton cloned per instance, with holes filled. *)

open Reativa
open Harness
module T = View.Template

let txt s = View.text (View.static s)

(* <li class="row"><span> </span><!----><button>x</button></li> *)
let row_template = T.make {|<li class="row"><span> </span><!----><button>x</button></li>|}

let row ~label ~selected ~on_remove extra =
  View.template row_template
    [
      T.attr [ 0 ] (View.Attr.class_reactive (fun () -> if Signal.get selected then "row on" else "row"));
      T.text [ 0; 0; 0 ] (View.dynamic (fun () -> Signal.get label));
      T.child [ 0; 1 ] extra;
      T.event [ 0; 2 ] "click" on_remove;
    ]

let register () =
  suite "Templates";
  test "holes are filled and the skeleton is otherwise kept" (fun () ->
    let label = Signal.make "first" and selected = Signal.make false and removed = ref 0 in
    let c = mount (View.ul [ row ~label ~selected ~on_remove:(fun _ -> incr removed) (txt "!") ]) in
    equal_string "markup" ~expected:{|<ul><li class="row"><span>first</span>!<button>x</button></li></ul>|} (html c);
    Signal.set label "second";
    Signal.set selected true;
    equal_string "updated" ~expected:{|<ul><li class="row on"><span>second</span>!<button>x</button></li></ul>|}
      (html c);
    Probe.click (Option.get (Probe.query c "button"));
    equal_int "event hole" ~expected:1 !removed);
  test "each instance is one clone of a skeleton parsed once" (fun () ->
    let selected = Signal.make false in
    let items = List.init 20 Fun.id in
    Probe.reset_ops ();
    let c =
      mount
        (View.ul
           (List.map
              (fun i -> row ~label:(Signal.make (string_of_int i)) ~selected ~on_remove:ignore View.empty)
              items))
    in
    equal_int "20 rows" ~expected:20 (List.length (Probe.query_all c "li"));
    equal_int "one clone per row" ~expected:20 (Probe.ops "cloneNode");
    (* the test container and the <ul>; nothing per row *)
    equal_int "no createElement for the rows" ~expected:2 (Probe.ops "createElement"));
  test "a child hole takes any view, including regions" (fun () ->
    let n = Signal.make 1 in
    let tpl = T.make {|<p><!----> and <!----></p>|} in
    let c =
      mount
        (View.template tpl
           [
             T.child [ 0; 0 ] (View.dyn (fun () -> View.int (View.static (Signal.get n))));
             T.child [ 0; 2 ] (View.element "b" []);
           ])
    in
    equal_string "initial" ~expected:"<p>1<!----> and <b></b></p>" (html c);
    Signal.set n 2;
    equal_string "region updated" ~expected:"<p>2<!----> and <b></b></p>" (html c));
  test "top-level holes and several roots" (fun () ->
    let tpl = T.make {|<!----><hr><i> </i>|} in
    let c = mount (View.div [ View.template tpl [ T.child [ 0 ] (txt "a"); T.text [ 2; 0 ] (View.static "b") ] ]) in
    equal_string "markup" ~expected:"<div>a<hr><i>b</i></div>" (html c));
  test "an SVG template is parsed in the SVG namespace" (fun () ->
    let tpl = T.make {|<svg viewBox="0 0 2 2"><circle r="1"></circle></svg>|} in
    let c = mount (View.template tpl []) in
    let circle = Option.get (Probe.query c "circle") in
    equal_string "namespace" ~expected:"http://www.w3.org/2000/svg" (Probe.string_property circle "namespaceURI"));
  test "a template used inside an svg is parsed as SVG" (fun () ->
    let tpl = T.make {|<g><rect width="1"></rect></g>|} in
    let c = mount (View.Mlx.svg ~children:[ View.template tpl [] ] ()) in
    let rect = Option.get (Probe.query c "rect") in
    equal_string "namespace" ~expected:"http://www.w3.org/2000/svg" (Probe.string_property rect "namespaceURI"))

  (* A region in a top-level child hole re-renders on its own: the instance
     must report only its anchor, or a keyed row that moves (or a dispose)
     would act on nodes the region already replaced. *)
let register_regions () =
  suite "Templates: regions in top-level holes";
  let tpl = T.make {|<!----><i>x</i>|} in
  let row n = View.template tpl [ T.child [ 0 ] (View.dyn (fun () -> View.text (View.static (string_of_int (Signal.get n))))) ] in
  test "mount_disposable removes everything after the region re-rendered" (fun () ->
    let n = Signal.make 1 in
    let c = Probe.container () in
    let dispose = View.mount_disposable c (row n) in
    Signal.set n 2;
    (match dispose () with
     | () -> check "no error" true
     | exception e -> check ("dispose raised " ^ Printexc.to_string e) false);
    equal_string "empty" ~expected:"" (html c));
  test "a moved keyed row takes its region's current nodes along" (fun () ->
    let a = Signal.make 1 and b = Signal.make 10 in
    let items = Signal.make [ "a"; "b" ] in
    let c =
      mount
        (View.div
           [
             View.for_with_key (fun () -> Signal.get items) ~key:Fun.id (fun item ->
               row (if Signal.peek item = "a" then a else b));
           ])
    in
    Signal.set a 2;
    Signal.set items [ "b"; "a" ];
    equal_string "order and content" ~expected:"<div>10<!----><i>x</i>2<!----><i>x</i><!----></div>" (html c))


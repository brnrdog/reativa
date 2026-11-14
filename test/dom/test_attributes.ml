(* Element props, the attrs escape hatch, removable attributes and SVG. *)

open Reativa
open Harness
module M = View.Mlx

let register () =
  suite "Attributes: mlx props";
  test "typed props render as attributes" (fun () ->
    let c =
      mount
        (M.img ~src:(View.static "/a.png") ~alt:(View.static "A") ~width:(View.static "10")
           ~tabIndex:(View.static 2) ~aria_hidden:(View.static "true") ())
    in
    let el = Option.get (Probe.query c "img") in
    List.iter
      (fun (name, value) ->
        equal_string name ~expected:value (Option.value ~default:"<none>" (Probe.attribute el name)))
      [ ("src", "/a.png"); ("alt", "A"); ("width", "10"); ("tabindex", "2"); ("aria-hidden", "true") ]);
  test "keyword-named props map to their attribute" (fun () ->
    let c =
      mount
        (M.label ~for_:(View.static "f") ~className:(View.static "l") ~children:[ View.text (View.static "x") ] ())
    in
    equal_string "markup" ~expected:{|<label class="l" for="f">x</label>|} (html c));
  test "toggle props add and remove the attribute" (fun () ->
    let req = Signal.make true in
    let c = mount (M.input ~required:(View.signal req) ~readOnly:(View.static true) ()) in
    let el = Option.get (Probe.query c "input") in
    check "required present" (Probe.attribute el "required" = Some "");
    check "readonly present" (Probe.attribute el "readonly" = Some "");
    Signal.set req false;
    check "required removed" (Probe.attribute el "required" = None));
  test "attrs come after the typed props" (fun () ->
    let c =
      mount
        (M.div ~id:(View.static "x")
           ~attrs:[ View.Attr.data "role" (View.static "card"); View.Attr.make "itemprop" (View.static "name") ]
           ())
    in
    equal_string "markup" ~expected:{|<div id="x" data-role="card" itemprop="name"></div>|} (html c));
  test "event props register listeners" (fun () ->
    let ups = ref 0 and focused = ref 0 in
    let c =
      mount (M.input ~onKeyUp:(fun _ -> incr ups) ~onFocus:(fun _ -> incr focused) ())
    in
    let el = Option.get (Probe.query c "input") in
    Probe.dispatch el "keyup";
    Probe.dispatch el "focus";
    equal_int "keyup" ~expected:1 !ups;
    equal_int "focus" ~expected:1 !focused);

  suite "Attributes: removable";
  test "Attr.optional sets and removes" (fun () ->
    let title = Signal.make (Some "hello") in
    let c = mount (View.div ~attrs:[ View.Attr.optional "title" (fun () -> Signal.get title) ] []) in
    let el = Option.get (Probe.query c "div") in
    equal_string "set" ~expected:"hello" (Option.value ~default:"<none>" (Probe.attribute el "title"));
    Signal.set title None;
    check "removed" (Probe.attribute el "title" = None);
    Signal.set title (Some "again");
    equal_string "set again" ~expected:"again" (Option.value ~default:"<none>" (Probe.attribute el "title")));

  suite "Attributes: SVG";
  test "svg and its children are created in the SVG namespace" (fun () ->
    let c =
      mount
        (M.svg ~viewBox:(View.static "0 0 10 10")
           ~children:[ M.circle ~cx:(View.static "5") ~cy:(View.static "5") ~r:(View.static "4") () ]
           ())
    in
    let svg = Option.get (Probe.query c "svg") and circle = Option.get (Probe.query c "circle") in
    let ns = "http://www.w3.org/2000/svg" in
    equal_string "svg namespace" ~expected:ns (Probe.string_property svg "namespaceURI");
    equal_string "circle namespace" ~expected:ns (Probe.string_property circle "namespaceURI");
    equal_string "viewBox keeps its case" ~expected:"0 0 10 10"
      (Option.value ~default:"" (Probe.attribute svg "viewBox")));
  test "a region inside svg re-renders in the SVG namespace" (fun () ->
    let n = Signal.make 1 in
    let c =
      mount
        (M.svg
           ~children:
             [ View.dyn (fun () -> View.fragment (List.init (Signal.get n) (fun _ -> M.rect ()))) ]
           ())
    in
    Signal.set n 2;
    let rects = Probe.query_all c "rect" in
    equal_int "two rects" ~expected:2 (List.length rects);
    check "all in the SVG namespace"
      (List.for_all (fun r -> Probe.string_property r "namespaceURI" = "http://www.w3.org/2000/svg") rects));
  test "foreignObject children are HTML again" (fun () ->
    let c =
      mount
        (M.svg ~children:[ View.element "foreignObject" [ M.div ~children:[] () ] ] ())
    in
    let div = Option.get (Probe.query c "div") in
    equal_string "html namespace" ~expected:"http://www.w3.org/1999/xhtml"
      (Probe.string_property div "namespaceURI"))

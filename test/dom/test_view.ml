(* Behaviour of the View layer as it renders into a real (jsdom) DOM. *)

open Reativa
open Harness

let register () =
  suite "View: static content";
  test "text, elements and attributes" (fun () ->
    let c =
      mount
        (View.div
           ~attrs:[ View.Attr.class_ (View.static "box"); View.Attr.id (View.static "x") ]
           [ View.text (View.static "hello"); View.span [ View.int (View.static 3) ] ])
    in
    equal_string "markup" ~expected:{|<div class="box" id="x">hello<span>3</span></div>|} (html c));
  test "fragments and empty render their children only" (fun () ->
    let c =
      mount (View.fragment [ View.text (View.static "a"); View.empty; View.text (View.static "b") ])
    in
    equal_string "markup" ~expected:"ab" (html c));

  suite "View: reactive leaves";
  test "reactive text updates in place" (fun () ->
    let count = Signal.make 1 in
    let c = mount (View.p [ View.int (View.signal count) ]) in
    let text_before = Probe.first_child (Option.get (Probe.query c "p")) in
    equal_string "initial" ~expected:"<p>1</p>" (html c);
    Signal.set count 2;
    equal_string "after set" ~expected:"<p>2</p>" (html c);
    let text_after = Probe.first_child (Option.get (Probe.query c "p")) in
    check "same text node"
      (match (text_before, text_after) with
       | Some a, Some b -> Dom.is_same_node a b
       | _ -> false));
  test "reactive attribute" (fun () ->
    let on = Signal.make false in
    let c =
      mount
        (View.div
           ~attrs:[ View.Attr.class_reactive (fun () -> if Signal.get on then "on" else "off") ]
           [])
    in
    let el = Option.get (Probe.query c "div") in
    equal_string "initial" ~expected:"off" (Option.get (Probe.attribute el "class"));
    Signal.set on true;
    equal_string "after set" ~expected:"on" (Option.get (Probe.attribute el "class")));
  test "toggle attribute" (fun () ->
    let disabled = Signal.make true in
    let c = mount (View.button ~attrs:[ View.Attr.disabled (fun () -> Signal.get disabled) ] []) in
    let el = Option.get (Probe.query c "button") in
    check "present" (Probe.attribute el "disabled" <> None);
    Signal.set disabled false;
    check "removed" (Probe.attribute el "disabled" = None));
  test "value and checked are properties" (fun () ->
    let v = Signal.make "a" in
    let checked = Signal.make true in
    let c =
      mount
        (View.div
           [
             View.input ~attrs:[ View.Attr.value (View.signal v) ] ();
             View.input ~attrs:[ View.Attr.checked (View.signal checked) ] ();
           ])
    in
    match Probe.query_all c "input" with
    | [ text; box ] ->
      equal_string "value" ~expected:"a" (Probe.string_property text "value");
      Signal.set v "b";
      equal_string "value updated" ~expected:"b" (Probe.string_property text "value");
      equal_bool "checked" ~expected:true (Probe.bool_property box "checked");
      Signal.set checked false;
      equal_bool "unchecked" ~expected:false (Probe.bool_property box "checked")
    | _ -> check "two inputs" false);

  suite "View: events";
  test "click handler" (fun () ->
    let clicks = ref 0 in
    let c = mount (View.button ~events:[ View.On.click (fun _ -> incr clicks) ] [ View.text (View.static "+") ]) in
    Probe.click (Option.get (Probe.query c "button"));
    Probe.click (Option.get (Probe.query c "button"));
    equal_int "clicks" ~expected:2 !clicks);
  test "input handler reads the target value" (fun () ->
    let seen = ref "" in
    let c = mount (View.input ~events:[ View.On.input (fun ev -> seen := Dom.target_value ev) ] ()) in
    Probe.type_text (Option.get (Probe.query c "input")) "typed";
    equal_string "value" ~expected:"typed" !seen);

  suite "View: dynamic regions";
  test "dyn rebuilds its region and keeps its place" (fun () ->
    let n = Signal.make 1 in
    let c =
      mount
        (View.div
           [
             View.text (View.static "[");
             View.dyn (fun () -> View.fragment (List.init (Signal.get n) (fun i -> View.span [ View.int (View.static i) ])));
             View.text (View.static "]");
           ])
    in
    equal_string "initial" ~expected:"<div>[<span>0</span><!---->]</div>" (html c);
    Signal.set n 3;
    equal_string "grown" ~expected:"<div>[<span>0</span><span>1</span><span>2</span><!---->]</div>" (html c);
    Signal.set n 0;
    equal_string "emptied" ~expected:"<div>[<!---->]</div>" (html c));
  test "effects inside a replaced region are disposed" (fun () ->
    let outer = Signal.make true in
    let inner = Signal.make 0 in
    let runs = ref 0 in
    let _c =
      mount
        (View.dyn (fun () ->
           if Signal.get outer then
             View.text
               (View.dynamic (fun () ->
                  incr runs;
                  string_of_int (Signal.get inner)))
           else View.empty))
    in
    equal_int "ran once" ~expected:1 !runs;
    Signal.set inner 1;
    equal_int "ran on change" ~expected:2 !runs;
    Signal.set outer false;
    Signal.set inner 2;
    equal_int "disposed with its region" ~expected:2 !runs);
  test "show swaps content and fallback" (fun () ->
    let visible = Signal.make false in
    let c =
      mount
        (View.show
           ~fallback:(View.text (View.static "hidden"))
           (fun () -> Signal.get visible)
           (View.text (View.static "shown")))
    in
    equal_string "fallback" ~expected:"hidden<!---->" (html c);
    Signal.set visible true;
    equal_string "content" ~expected:"shown<!---->" (html c));
  test "maybe renders the Some case" (fun () ->
    let user = Signal.make None in
    let c =
      mount
        (View.maybe
           ~fallback:(View.text (View.static "anon"))
           (fun () -> Signal.get user)
           (fun name -> View.text (View.static ("hi " ^ name))))
    in
    equal_string "none" ~expected:"anon<!---->" (html c);
    Signal.set user (Some "ada");
    equal_string "some" ~expected:"hi ada<!---->" (html c));
  test "for_ re-renders the whole list" (fun () ->
    let items = Signal.make [ "a"; "b" ] in
    let c = mount (View.ul [ View.for_ (fun () -> Signal.get items) (fun s -> View.li [ View.text (View.static s) ]) ]) in
    equal_string "initial" ~expected:"<ul><li>a</li><li>b</li><!----></ul>" (html c);
    Signal.set items [ "c" ];
    equal_string "replaced" ~expected:"<ul><li>c</li><!----></ul>" (html c));
  test "child coerces bare values" (fun () ->
    let n = Signal.make 1 in
    let c =
      mount
        (View.div
           [
             View.child "s";
             View.child 2;
             View.child (View.span []);
             View.child (fun () -> Signal.get n);
           ])
    in
    equal_string "initial" ~expected:"<div>s2<span></span>1<!----></div>" (html c);
    Signal.set n 5;
    equal_string "thunk tracked" ~expected:"<div>s2<span></span>5<!----></div>" (html c));

  suite "View: built-in components";
  test "Show.createElement" (fun () ->
    let on = Signal.make true in
    let c =
      mount
        (View.Show.createElement
           ~fallback:(View.text (View.static "off"))
           () ~condition:(View.signal on)
           ~children:[ View.text (View.static "on") ])
    in
    equal_string "on" ~expected:"on<!---->" (html c);
    Signal.set on false;
    equal_string "off" ~expected:"off<!---->" (html c));
  test "Maybe.createElement" (fun () ->
    let v = Signal.make (Some 1) in
    let c =
      mount
        (View.Maybe.createElement () ~children:[]
           ~value:(View.signal v)
           ~render:(fun n -> View.int (View.static n)))
    in
    equal_string "some" ~expected:"1<!---->" (html c);
    Signal.set v None;
    equal_string "none" ~expected:"<!---->" (html c));
  test "ForEach.createElement with a key" (fun () ->
    let items = Signal.make [ 1; 2 ] in
    let c =
      mount
        (View.ForEach.createElement ~key:string_of_int () ~children:[]
           ~items:(View.signal items)
           ~render:(fun n -> View.span [ View.int (View.static n) ]))
    in
    equal_string "initial" ~expected:"<span>1</span><span>2</span><!---->" (html c);
    Signal.set items [ 2; 3 ];
    equal_string "updated" ~expected:"<span>2</span><span>3</span><!---->" (html c))

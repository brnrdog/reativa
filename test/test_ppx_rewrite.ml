(* Behavioral test for the mlx PPX: parse a snippet, run the rewriter, and
   compare against the expected source. Both sides are parsed and printed with
   the same printer, so the comparison is about structure, not formatting. *)

let parse source = Ppxlib.Parse.implementation (Lexing.from_string source)
let print structure = Ppxlib.Pprintast.string_of_structure structure

let failures = ref 0

(* The element path (no templates), so these cases show the inference rules
   on their own. Template compilation has its own cases, at the end. *)
let check name input expected =
  let actual = print (Reativa_mlx_ppx.rewrite_without_templates (parse input)) in
  let expected = print (parse expected) in
  if String.equal actual expected then
    Printf.printf "ok - %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL - %s\n--- expected ---\n%s\n--- actual ---\n%s\n" name
      expected actual
  end

let contains haystack needle =
  let n = String.length needle and h = String.length haystack in
  let rec go i = i + n <= h && (String.sub haystack i n = needle || go (i + 1)) in
  go 0

(* For generated code whose exact printing depends on the ppxlib version (how
   nested [fun]s are merged): check the parts that matter. *)
let check_generated name input ~has ~lacks =
  let actual = print (Reativa_mlx_ppx.rewrite (parse input)) in
  let squash s = String.concat "" (String.split_on_char ' ' (String.concat "" (String.split_on_char '\n' s))) in
  let actual_s = squash actual in
  let missing = List.filter (fun s -> not (contains actual_s (squash s))) has in
  let present = List.filter (fun s -> contains actual_s (squash s)) lacks in
  if missing = [] && present = [] then Printf.printf "ok - %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL - %s\n--- actual ---\n%s\n" name actual;
    List.iter (Printf.printf "    missing: %s\n") missing;
    List.iter (Printf.printf "    unexpected: %s\n") present
  end

let () =
  check_generated "components get a lazy createElement"
    {| module Greeting = struct
         let component = fun ~name ?(size = 1) -> view name size
       end |}
    ~has:
      [ "let createElement ~children:_";
        "~name:reativa__name";
        "?size:reativa__size";
        "View.component";
        "component ~name:reativa__name ?size:reativa__size" ]
    ~lacks:[];

  check_generated "children are forwarded when the component takes them"
    {| module Card = struct
         let component ~title ~children = view title children
       end |}
    ~has:
      [ "~children:reativa__children";
        "View.component";
        "component ~title:reativa__title ~children:reativa__children" ]
    ~lacks:[ "~children:_" ];

  check_generated "a trailing unit parameter is forwarded"
    {| module Panel = struct
         let component ?open_ ~label () = view open_ label
       end |}
    ~has:[ "View.component"; "component ?open_:reativa__open_ ~label:reativa__label ()" ]
    ~lacks:[];

  check_generated "an unreadable component falls back to the eager form"
    {| module Alias = struct
         let component = Other.component
       end |}
    ~has:[ "let createElement () ~children:_ = component" ]
    ~lacks:[ "View.component" ];

  check_generated "a handwritten createElement is left alone"
    {| module Custom = struct
         let component ~x = x
         let createElement ~x () = component ~x
       end |}
    ~has:[ "let createElement ~x () = component ~x" ]
    ~lacks:[ "View.component" ];

  check "any element prop is inferred, handlers and escape hatches are not"
    {| let v = ((img ~src:url ~alt:(Signal.get label) ~onLoad:loaded ~attrs:extra ()) [@JSX]) |}
    {| let v =
         ((img ~src:(static url) ~alt:(dynamic (fun () -> Signal.get label))
             ~onLoad:loaded ~attrs:extra ())
          [@JSX]) |};

  check "a local helper that reads a signal is an eager read"
    {| let label () = "Hi " ^ Signal.get name
       let v = ((p ~children:[label ()] ()) [@JSX]) |}
    {| let label () = "Hi " ^ Signal.get name
       let v = ((p ~children:[View.child (fun () -> label ())] ()) [@JSX]) |};

  check "helpers calling helpers count too"
    {| let first () = Signal.get name
       let greeting () = "Hi " ^ first ()
       let v = ((p ~className:(greeting ()) ()) [@JSX]) |}
    {| let first () = Signal.get name
       let greeting () = "Hi " ^ first ()
       let v = ((p ~className:(dynamic (fun () -> greeting ())) ()) [@JSX]) |};

  check "an alias of Signal.get is an eager read"
    {| let get = Signal.get
       let v = ((p ~className:(get cls) ()) [@JSX]) |}
    {| let get = Signal.get
       let v = ((p ~className:(dynamic (fun () -> get cls)) ()) [@JSX]) |};

  check "a helper that only reads inside a callback is not reactive"
    {| let handler () = fun _ -> Signal.get name
       let v = ((p ~className:(handler ()) ()) [@JSX]) |}
    {| let handler () = fun _ -> Signal.get name
       let v = ((p ~className:(static (handler ())) ()) [@JSX]) |};

  check "plain attribute values stay static"
    {| let v = ((div ~className:"box" ()) [@JSX]) |}
    {| let v = ((div ~className:(static "box") ()) [@JSX]) |};

  check "explicit wrappers are preserved"
    {| let v = ((div ~className:(dynamic f) ~id:(static "a") ()) [@JSX]) |}
    {| let v = ((div ~className:(dynamic f) ~id:(static "a") ()) [@JSX]) |};

  check "thunked attributes become dynamic"
    {| let v = ((input ~checked:(fun () -> Signal.get on) ()) [@JSX]) |}
    {| let v = ((input ~checked:(dynamic (fun () -> Signal.get on)) ()) [@JSX]) |};

  check "eager signal reads in attributes are auto-thunked"
    {| let v = ((div ~className:(if Signal.get on then "a" else "b") ()) [@JSX]) |}
    {| let v =
         ((div
             ~className:(dynamic (fun () -> if Signal.get on then "a" else "b"))
             ())
          [@JSX]) |};

  check "qualified reads are auto-thunked too"
    {| let v = ((input ~value:(Reativa.Signal.get draft) ()) [@JSX]) |}
    {| let v =
         ((input ~value:(dynamic (fun () -> Reativa.Signal.get draft)) ())
          [@JSX]) |};

  check "eager signal reads in View.text are auto-thunked"
    {| let v = View.text ("n: " ^ string_of_int (Signal.get count)) |}
    {| let v = View.text (dynamic (fun () -> "n: " ^ string_of_int (Signal.get count))) |};

  check "eager signal reads in View.int are auto-thunked"
    {| let v = View.int (List.length (Signal.get todos)) |}
    {| let v = View.int (dynamic (fun () -> List.length (Signal.get todos))) |};

  check "Signal.peek stays static"
    {| let v = View.text (Signal.peek draft) |}
    {| let v = View.text (static (Signal.peek draft)) |};

  check "reads inside a lambda are not eager"
    {| let v = ((div ~className:(make_class (fun () -> Signal.get on)) ()) [@JSX]) |}
    {| let v =
         ((div ~className:(static (make_class (fun () -> Signal.get on))) ())
          [@JSX]) |};

  check "bare scalar children become view leaves"
    {| let v = ((p ~children:["Hello"; 42; 1.5; View.text name] ()) [@JSX]) |}
    {| let v =
         ((p
             ~children:[View.text (static "Hello");
                        View.int (static 42);
                        View.float (static 1.5);
                        View.text (static name)]
             ())
          [@JSX]) |};

  check "bare value children go through View.child"
    {| let v = ((p ~children:[title; todo.text] ()) [@JSX]) |}
    {| let v = ((p ~children:[View.child title; View.child todo.text] ()) [@JSX]) |};

  check "eager signal reads as children become tracked View.child regions"
    {| let v = ((p ~children:[Signal.get draft] ()) [@JSX]) |}
    {| let v = ((p ~children:[View.child (fun () -> Signal.get draft)] ()) [@JSX]) |};

  check "thunk children become tracked View.child regions"
    {| let v = ((p ~children:[(fun () -> Signal.get draft)] ()) [@JSX]) |}
    {| let v = ((p ~children:[View.child (fun () -> Signal.get draft)] ()) [@JSX]) |};

  check "nested elements and View calls stay untouched children"
    {| let v =
         ((p ~children:[((span ~children:[] ()) [@JSX]); View.show cond body] ())
          [@JSX]) |}
    {| let v =
         ((p ~children:[((span ~children:[] ()) [@JSX]); View.show cond body] ())
          [@JSX]) |};

  check "non-literal children lists are left alone"
    {| let v = ((p ~children:rows ()) [@JSX]) |}
    {| let v = ((p ~children:rows ()) [@JSX]) |};

  check "component children only wrap literals"
    {| let v =
         ((Router.createElement () ~children:[home_route; "About"]) [@JSX]) |}
    {| let v =
         ((Router.createElement ()
             ~children:[home_route; View.text (static "About")])
          [@JSX]) |};

  (* ----- templates ----- *)
  check_generated "an element tree compiles to a hoisted template with holes"
    {| let v =
         ((div ~className:"card" ~title:(Signal.get t) ~onClick:go
             ~children:["Hi "; ((b ~children:[name] ()) [@JSX]); ((hr ()) [@JSX])] ())
          [@JSX]) |}
    ~has:
      [ {|let __reativa_template_0 = Reativa.View.Template.make "<div class=\"card\">Hi <b><!----></b><hr></div>"|};
        "Reativa.View.template __reativa_template_0";
        {|Reativa.View.Template.string_prop [0] "title" (Reativa.View.dynamic (fun () -> Signal.get t))|};
        {|Reativa.View.Template.event [0] "click" go|};
        "Reativa.View.Template.child [0; 1; 0] (View.child name)" ]
    ~lacks:[ "Mlx" ];

  check_generated "literal props render statically, value and checked stay holes"
    {| let v = ((input ~type_:"checkbox" ~tabIndex:2 ~required:true ~disabled:false ~value:"v" ~checked:true ()) [@JSX]) |}
    ~has:
      [ {|"<input type=\"checkbox\" tabindex=\"2\" required>"|};
        {|Reativa.View.Template.string_prop [0] "value" (Reativa.View.static "v")|};
        {|Reativa.View.Template.bool_prop [0] "checked" (Reativa.View.static true)|} ]
    ~lacks:[ "disabled" ];

  check_generated "identical skeletons share one binding"
    {| let a = ((p ~children:["x"] ()) [@JSX])
       let b = ((p ~children:["x"] ()) [@JSX]) |}
    ~has:[ "let a = Reativa.View.template __reativa_template_0 []"; "let b = Reativa.View.template __reativa_template_0 []" ]
    ~lacks:[ "__reativa_template_1" ];

  check_generated "text is escaped"
    {| let v = ((p ~title:"a&b" ~children:["1 < 2 & 3"] ()) [@JSX]) |}
    ~has:[ "1 &lt; 2 &amp; 3</p>"; "title=" ]
    ~lacks:[];

  check_generated "markup with non-ASCII text is a {js|...|js} literal, for Melange"
    {| let v = ((p ~children:[{js|café|js}] ()) [@JSX]) |}
    ~has:[ "Reativa.View.Template.make {js|<p>café</p>|js}" ]
    ~lacks:[];

  check_generated "an unknown prop keeps the element on the View.Mlx path"
    {| let v = ((div ~notAProp:1 ()) [@JSX]) |}
    ~has:[ "div ~notAProp:(static 1)" ]
    ~lacks:[ "Reativa.View.template" ];

  check_generated "markup the parser would rewrite is kept out of the skeleton"
    {| let v = ((p ~children:[((div ()) [@JSX])] ()) [@JSX]) |}
    ~has:
      [ {|Reativa.View.Template.make "<p><!----></p>"|};
        "Reativa.View.Template.child [0; 0] (Reativa.View.template" ]
    ~lacks:[ "<p><div>" ];

  check_generated "a component or computed child is a child hole"
    {| let v = ((ul ~children:[((Item.createElement ~children:[] ()) [@JSX]); Signal.get n] ()) [@JSX]) |}
    ~has:[ "<ul><!----><!----></ul>"; "Reativa.View.Template.child [0; 0]"; "Reativa.View.Template.child [0; 1] (View.child (fun () -> Signal.get n))" ]
    ~lacks:[];

  check_generated "opens of View.Mlx never warn, since templates may leave them unused"
    {| open Reativa.View.Mlx
       let v = ((p ~children:["x"] ()) [@JSX]) |}
    ~has:[ {|open Reativa.View.Mlx[@@ocaml.warning "-33"]|} ]
    ~lacks:[];

  check_generated "children inside svg are marked"
    {| let v = ((svg ~children:[shape] ()) [@JSX]) |}
    ~has:[ "Reativa.View.Template.child ~svg:true [0; 0] (View.child shape)" ]
    ~lacks:[];

  if !failures > 0 then begin
    Printf.printf "%d failure(s)\n" !failures;
    exit 1
  end;
  print_endline "ppx rewrite ok"

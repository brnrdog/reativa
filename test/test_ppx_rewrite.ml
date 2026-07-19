(* Behavioral test for the mlx PPX: parse a snippet, run the rewriter, and
   compare against the expected source. Both sides are parsed and printed with
   the same printer, so the comparison is about structure, not formatting. *)

let parse source = Ppxlib.Parse.implementation (Lexing.from_string source)
let print structure = Ppxlib.Pprintast.string_of_structure structure

let failures = ref 0

let check name input expected =
  let actual = print (Reativa_mlx_ppx.mapper#structure (parse input)) in
  let expected = print (parse expected) in
  if String.equal actual expected then
    Printf.printf "ok - %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL - %s\n--- expected ---\n%s\n--- actual ---\n%s\n" name
      expected actual
  end

let () =
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

  if !failures > 0 then begin
    Printf.printf "%d failure(s)\n" !failures;
    exit 1
  end;
  print_endline "ppx rewrite ok"

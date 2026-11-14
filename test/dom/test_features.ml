(* Lifecycle, refs, context, error boundaries, portals, resources and
   suspense. *)

open Reativa
open Harness

let txt s = View.text (View.static s)

(* Wait for pending promise callbacks: a macrotask runs after all of them. *)
let after_promises f = Probe.set_timeout 0 f

let register () =
  suite "Lifecycle";
  test "on_mount runs after the nodes are in place" (fun () ->
    let seen = ref "" in
    let c = Probe.container () in
    View.mount c
      (View.component (fun () ->
         View.on_mount (fun () -> seen := Probe.inner_html c);
         View.p [ txt "hello" ]));
    equal_string "saw the rendered markup" ~expected:"<p>hello</p>" !seen);
  test "on_mount in a keyed row runs once the row is placed" (fun () ->
    let items = Signal.make [ 1 ] and connected = ref [] in
    let _c =
      mount
        (View.for_with_key (fun () -> Signal.get items) ~key:string_of_int (fun item ->
           let r = View.Ref.make () in
           View.on_mount (fun () ->
             connected := Probe.is_connected (Option.get (View.Ref.current r)) :: !connected);
           View.Mlx.li ~ref:r ~children:[ View.int (View.signal item) ] ()))
    in
    Signal.set items [ 1; 2 ];
    equal_string "both rows were connected" ~expected:"true,true"
      (String.concat "," (List.map string_of_bool !connected)));
  test "on_cleanup runs when the component goes away" (fun () ->
    let visible = Signal.make true and cleaned = ref 0 in
    let _c =
      mount
        (View.show (fun () -> Signal.get visible)
           (View.component (fun () ->
              View.on_cleanup (fun () -> incr cleaned);
              txt "x")))
    in
    Signal.set visible false;
    equal_int "cleaned" ~expected:1 !cleaned);

  suite "Refs";
  test "a ref holds its element, and the callback form is called" (fun () ->
    let r = View.Ref.make () and called = ref false in
    let cb = View.Ref.from_callback (fun _ -> called := true) in
    let _c = mount (View.div [ View.Mlx.input ~ref:r (); View.element "span" ~attrs:[ View.Attr.ref_ cb ] [] ]) in
    check "filled" (View.Ref.current r <> None);
    check "callback called" !called);
  test "a ref is cleared when its element's owner is disposed" (fun () ->
    let visible = Signal.make true and r = View.Ref.make () in
    let _c = mount (View.show (fun () -> Signal.get visible) (View.component (fun () -> View.Mlx.p ~ref:r ()))) in
    check "filled" (View.Ref.current r <> None);
    Signal.set visible false;
    check "cleared" (View.Ref.current r = None));

  suite "Context";
  let theme = Context.make "light" in
  let badge () = View.component (fun () -> txt (Context.use theme)) in
  test "the default applies outside any provider" (fun () ->
    equal_string "default" ~expected:"light" (html (mount (badge ()))));
  test "a provider reaches everything below it, the nearest one wins" (fun () ->
    let c =
      mount
        (Context.provider theme "dark"
           (View.fragment [ badge (); Context.provider theme "blue" (badge ()); badge () ]))
    in
    equal_string "markup" ~expected:"darkbluedark" (html c));
  test "Context.Provider takes a value prop" (fun () ->
    let c =
      mount
        (Context.Provider.createElement () ~context:theme ~value:(View.static "green")
           ~children:[ badge () ])
    in
    equal_string "markup" ~expected:"green" (html c));
  test "a provider does not leak to its siblings" (fun () ->
    let c = mount (View.fragment [ Context.provider theme "dark" (badge ()); badge () ]) in
    equal_string "markup" ~expected:"darklight" (html c));
  test "rows and regions below a provider see it" (fun () ->
    let items = Signal.make [ 1 ] and show = Signal.make false in
    let c =
      mount
        (Context.provider theme "dark"
           (View.fragment
              [
                View.for_with_key (fun () -> Signal.get items) ~key:string_of_int (fun _ -> badge ());
                View.show (fun () -> Signal.get show) (badge ());
              ]))
    in
    Signal.set items [ 1; 2 ];
    Signal.set show true;
    equal_string "markup" ~expected:"darkdark<!---->dark<!---->" (html c));
  test "provide outside a component is an error" (fun () ->
    raises "raises" (fun () -> Context.provide theme "x"));

  suite "Error boundaries";
  let fallback e reset =
    View.Mlx.button
      ~onClick:(fun _ -> reset ())
      ~children:[ txt ("error: " ^ match e with Failure m -> m | e -> Printexc.to_string e) ]
      ()
  in
  test "an error while rendering shows the fallback" (fun () ->
    let c = mount (View.error_boundary ~fallback (View.component (fun () -> failwith "boom"))) in
    equal_string "fallback" ~expected:"<button>error: boom</button><!---->" (html c));
  test "an error in a later effect swaps in the fallback, reset renders again" (fun () ->
    let n = Signal.make 0 in
    let child =
      View.component (fun () ->
        Effect.run (fun () -> if Signal.get n = 1 then failwith "one" else None);
        View.int (View.signal n))
    in
    let c = mount (View.error_boundary ~fallback child) in
    equal_string "child" ~expected:"0<!---->" (html c);
    Signal.set n 1;
    equal_string "fallback" ~expected:"<button>error: one</button><!---->" (html c);
    Signal.set n 2;
    Probe.click (Option.get (Probe.query c "button"));
    equal_string "child again" ~expected:"2<!---->" (html c));
  test "an error in the fallback goes to the next boundary up" (fun () ->
    let c =
      mount
        (View.error_boundary ~fallback
           (View.error_boundary
              ~fallback:(fun _ _ -> View.component (fun () -> failwith "fallback broke"))
              (View.component (fun () -> failwith "inner"))))
    in
    equal_string "outer fallback" ~expected:"<button>error: fallback broke</button><!---->" (html c));
  test "an error with no boundary propagates" (fun () ->
    raises "mount raises" (fun () -> ignore (mount (View.component (fun () -> failwith "no boundary")))));

  suite "Portals";
  test "a portal renders into its target and is removed with its owner" (fun () ->
    let target = Probe.container () and visible = Signal.make true in
    let c =
      mount
        (View.show (fun () -> Signal.get visible)
           (View.portal ~target (View.Mlx.p ~children:[ txt "in portal" ] ())))
    in
    equal_string "target" ~expected:"<p>in portal</p>" (html target);
    check "nothing rendered in place but a marker" (not (String.length (html c) > 30));
    Signal.set visible false;
    equal_string "removed" ~expected:"" (html target));
  test "a portal's content sees the context around the portal" (fun () ->
    let target = Probe.container () in
    let _c = mount (Context.provider theme "dark" (View.portal ~target (badge ()))) in
    equal_string "target" ~expected:"dark" (html target));
  test "the default target is <body>" (fun () ->
    let dispose =
      View.mount_disposable (Probe.container ())
        (View.portal (View.Mlx.aside ~id:(View.static "portal-default") ()))
    in
    check "appended to body" (Probe.query (Probe.body ()) "body > #portal-default" <> None);
    dispose ();
    check "removed" (Probe.query (Probe.body ()) "#portal-default" = None));

  suite "Resources";
  async "a resource goes from loading to ready" (fun done_ ->
    let promise, resolve, _ = Probe.deferred () in
    let r = Resource.make (fun () -> promise) in
    check "loading" (Resource.is_loading (Resource.peek r));
    resolve 42;
    after_promises (fun () ->
      check "ready" (Resource.peek r = Resource.Ready 42);
      done_ ()));
  async "a rejection becomes Failed" (fun done_ ->
    let promise, _, reject = Probe.deferred () in
    let r = Resource.make (fun () -> promise) in
    reject "nope";
    after_promises (fun () ->
      (match Resource.peek r with
       | Resource.Failed (Promise.Rejected m) -> equal_string "message" ~expected:"nope" m
       | _ -> check "failed with Rejected" false);
      done_ ()));
  async "a dependency change refetches, and a stale result is dropped" (fun done_ ->
    let id = Signal.make 1 in
    let pending = Hashtbl.create 4 in
    let r =
      Resource.make (fun () ->
        let promise, resolve, _ = Probe.deferred () in
        Hashtbl.replace pending (Signal.get id) resolve;
        promise)
    in
    Signal.set id 2;
    (Hashtbl.find pending 2) "two";
    (Hashtbl.find pending 1) "one (stale)";
    after_promises (fun () ->
      check "the newest fetch wins" (Resource.peek r = Resource.Ready "two");
      done_ ()));
  async "refetch keeps the previous value while loading; mutate sets it" (fun done_ ->
    let count = ref 0 in
    let r =
      Resource.make (fun () ->
        incr count;
        Promise.resolve !count)
    in
    after_promises (fun () ->
      check "first" (Resource.peek r = Resource.Ready 1);
      Resource.refetch r;
      check "loading with previous" (Resource.peek r = Resource.Loading (Some 1));
      after_promises (fun () ->
        check "second" (Resource.peek r = Resource.Ready 2);
        Resource.mutate r 10;
        check "mutated" (Resource.peek r = Resource.Ready 10);
        done_ ())));

  suite "Suspense";
  async "the fallback shows until the resources below settle" (fun done_ ->
    let promise, resolve, _ = Probe.deferred () in
    let mounted_children = ref 0 in
    let child =
      View.component (fun () ->
        let r = Resource.make (fun () -> promise) in
        View.on_mount (fun () -> incr mounted_children);
        View.dyn (fun () ->
          match Resource.state r with
          | Resource.Ready s -> View.Mlx.p ~children:[ txt s ] ()
          | _ -> txt "…"))
    in
    let c = mount (View.suspense ~fallback:(txt "loading") child) in
    equal_string "fallback" ~expected:"loading<!---->" (html c);
    equal_int "the child rendered meanwhile" ~expected:1 !mounted_children;
    resolve "done";
    after_promises (fun () ->
      equal_string "child" ~expected:"<!----><p>done</p><!----><!----><!---->" (html c);
      done_ ()));
  test "with nothing pending the child shows right away" (fun () ->
    let c = mount (View.suspense ~fallback:(txt "loading") (txt "ready")) in
    equal_string "child" ~expected:"<!---->ready<!----><!---->" (html c))

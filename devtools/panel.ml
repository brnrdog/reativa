open Reativa

module D = Devtools

let txt s = View.text (View.static s)
let dyn_txt f = View.text (View.dynamic f)
let cls c = View.Attr.class_ (View.static c)

let kind_name = function D.Signal -> "signal" | D.Computed -> "computed" | D.Effect -> "effect"
let label (n : D.node_info) = match n.name with Some s -> s | None -> Printf.sprintf "#%d" n.id

let event_line = function
  | D.Created { kind; name; id } -> Printf.sprintf "+ %s %s" (kind_name kind) (Option.value ~default:(Printf.sprintf "#%d" id) name)
  | D.Written { name; id; value } -> Printf.sprintf "= %s <- %s" (Option.value ~default:(Printf.sprintf "#%d" id) name) value
  | D.Recomputed { name; id } -> Printf.sprintf "~ %s" (Option.value ~default:(Printf.sprintf "#%d" id) name)
  | D.Ran { name; id } -> Printf.sprintf "> effect %s" (Option.value ~default:(Printf.sprintf "#%d" id) name)
  | D.Disposed { name; id } -> Printf.sprintf "x %s" (Option.value ~default:(Printf.sprintf "#%d" id) name)

let rec cause_lines (c : D.cause) =
  let verb =
    match c.action with
    | D.Written_by_user -> Printf.sprintf "written = %s" (Option.value ~default:"?" c.value)
    | D.Recomputed_from -> "recomputed"
    | D.Ran_after -> "ran"
  in
  Printf.sprintf "%s %s (%s)" (kind_name c.node.kind) (label c.node) verb
  :: (match c.because with Some b -> cause_lines b | None -> [])

let styles =
  {|.rv-dt{position:fixed;right:12px;bottom:12px;z-index:2147483647;font:12px/1.4 ui-monospace,monospace;color:#e8e8ea;background:#18181b;border:1px solid #3f3f46;border-radius:8px;box-shadow:0 8px 24px rgba(0,0,0,.35);width:340px;max-height:60vh;display:flex;flex-direction:column}
.rv-dt header{display:flex;gap:6px;align-items:center;padding:6px 8px;border-bottom:1px solid #3f3f46}
.rv-dt header strong{flex:1}
.rv-dt button{font:inherit;color:inherit;background:#27272a;border:1px solid #3f3f46;border-radius:4px;padding:1px 6px;cursor:pointer}
.rv-dt .rv-body{overflow:auto;padding:6px 8px}
.rv-dt ul{list-style:none;margin:4px 0;padding:0}
.rv-dt li{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rv-dt .rv-muted{color:#a1a1aa}
.rv-dt.rv-closed .rv-body{display:none}|}

let mount ?target ?(open_ = true) () =
  if not (D.installed ()) then D.install ();
  let quiet f = D.mute f in
  quiet (fun () ->
    let events = Signal.make [] in
    let counts = Signal.make (0, 0, 0) in
    let leaks = Signal.make [] in
    let why = Signal.make [] in
    let picking = Signal.make false in
    let is_open = Signal.make open_ in
    let refresh () =
      quiet (fun () ->
        let nodes = D.snapshot () in
        let n k = List.length (List.filter (fun (x : D.node_info) -> x.kind = k) nodes) in
        Signal.batch (fun () ->
          Signal.set counts (n D.Signal, n D.Computed, n D.Effect);
          Signal.set leaks (List.map label (D.leaks ()))))
    in
    (* Events arrive while the app's flush is running. Writing the panel's
       signals right there would schedule the panel's effects later in that
       same flush, outside [mute], and their own events would come back here:
       a loop. So events go to a plain buffer, and the panel refreshes once,
       in a microtask, where its whole update runs muted. *)
    let pending = ref [] and scheduled = ref false in
    let flush_pending () =
      scheduled := false;
      let fresh = !pending in
      pending := [];
      quiet (fun () ->
        Signal.batch (fun () ->
          Signal.update events (fun l -> List.filteri (fun i _ -> i < 30) (List.rev_append fresh l));
          refresh ()))
    in
    let unsubscribe =
      D.subscribe (fun e ->
        pending := event_line e :: !pending;
        if not !scheduled then begin
          scheduled := true;
          Promise.on_settled (Promise.resolve ()) ~ok:flush_pending ~error:ignore
        end)
    in
    refresh ();
    (* Inspect mode: the next click anywhere outside the panel explains its
       target instead of reaching the app. *)
    let host = match target with Some t -> t | None ->
      let el = Dom.create_element "div" in
      Dom.append_child (Dom.body ()) el;
      el
    in
    let rec inside node =
      Dom.is_same_node node host || match Dom.parent_node node with Some p -> inside p | None -> false
    in
    let on_pick ev =
      if Signal.peek picking && not (inside (Dom.target ev)) then begin
        Dom.prevent_default ev;
        let el = Dom.target ev in
        let lines =
          match D.effects_writing el with
          | [] -> [ "no reactive binding writes this element" ]
          | bindings ->
            List.concat_map
              (fun (id, what) ->
                (what ^ " <- effect #" ^ string_of_int id)
                :: (match D.why id with Some c -> List.map (fun l -> "  " ^ l) (List.tl (cause_lines c)) | None -> []))
              bindings
        in
        quiet (fun () ->
          Signal.batch (fun () ->
            Signal.set why lines;
            Signal.set picking false))
      end
    in
    Dom.add_event_listener (Dom.body ()) "click" on_pick;
    let panel =
      View.div
        ~attrs:[ View.Attr.class_reactive (fun () -> if Signal.get is_open then "rv-dt" else "rv-dt rv-closed") ]
        [
          View.element "style" [ txt styles ];
          View.element "header"
            [
              View.element "strong" [ txt "reativa devtools" ];
              View.button
                ~events:[ View.On.click (fun _ -> quiet (fun () -> Signal.update picking not)) ]
                [ dyn_txt (fun () -> if Signal.get picking then "click an element…" else "inspect") ];
              View.button
                ~events:[ View.On.click (fun _ -> quiet (fun () -> Signal.update is_open not)) ]
                [ dyn_txt (fun () -> if Signal.get is_open then "–" else "+") ];
            ];
          View.div ~attrs:[ cls "rv-body" ]
            [
              View.p
                [
                  dyn_txt (fun () ->
                    let s, c, e = Signal.get counts in
                    Printf.sprintf "%d signals · %d computeds · %d effects" s c e);
                ];
              View.show (fun () -> Signal.get why <> [])
                (View.div
                   [
                     View.element "strong" [ txt "why" ];
                     View.for_ (fun () -> Signal.get why) (fun l -> View.element "pre" [ txt l ]);
                   ]);
              View.show (fun () -> Signal.get leaks <> [])
                (View.p [ dyn_txt (fun () -> "can never run again: " ^ String.concat ", " (Signal.get leaks)) ]);
              View.element "strong" [ txt "latest events" ];
              View.ul ~attrs:[ cls "rv-events" ] [ View.for_ (fun () -> Signal.get events) (fun l -> View.li [ txt l ]) ];
            ];
        ]
    in
    let dispose = View.mount_disposable host panel in
    fun () ->
      unsubscribe ();
      dispose ();
      match target with Some _ -> () | None -> Dom.remove host)

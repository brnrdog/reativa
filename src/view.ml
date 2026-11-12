(* A small, fine-grained reactive UI layer on top of Reativa signals.

   The model is the one popularised by SolidJS (and used by brnrdog/xote, the
   ReScript library this is inspired by): there is *no* virtual DOM. A view
   describes real DOM nodes, and the only things that update after the first
   render are the reactive regions — driven directly by Effects that mutate the
   exact DOM node that depends on a signal.

   A {!t} is a declarative description of a piece of UI. {!mount} (or its
   children) walk that description, create the corresponding DOM nodes, and wire
   up an Effect for every reactive part:

   - [Reactive_text f] — a text node whose content is recomputed by an Effect.
   - [Dynamic f]       — a region that re-renders its whole subtree when any
                         signal it read changes. Built around a comment anchor
                         so the region can find its place to re-insert into.
   - reactive attributes — set by an Effect per attribute.

   Reactive effects are tracked so that when an enclosing [Dynamic] re-renders,
   the Effects (and DOM nodes) it created last time are disposed first — no
   leaks, even with nested dynamic regions. *)

(* An element reference: filled with the element when it is created, cleared
   when the element's owner is disposed. *)
type element_ref = {
  mutable current : Dom.t option;
  on_set : (Dom.t -> unit) option;
}

type attr =
  | Attr_static of string * string
  | Attr_reactive of string * (unit -> string)
  | Attr_bool_static of string * bool
  | Attr_bool_reactive of string * (unit -> bool)
  (* Toggle an attribute's presence (e.g. [disabled]) from a boolean signal. *)
  | Attr_toggle of string * (unit -> bool)
  (* Set while [Some], removed while [None]. *)
  | Attr_optional of string * (unit -> string option)
  | Attr_ref of element_ref

type handler = string * (Dom.event -> unit)

type 'a value =
  | Static of 'a
  | Reactive of (unit -> 'a)

(* A static skeleton, parsed on first use and cloned for every instance; one
   copy parsed in an HTML context and, when needed, one in an SVG context. *)
type template = {
  html : string;
  mutable html_skeleton : Dom.t option;
  mutable svg_skeleton : Dom.t option;
}

type t =
  | Empty
  | Text of string
  | Reactive_text of (unit -> string)
  | Element of {
      tag : string;
      attrs : attr list;
      events : handler list;
      children : t list;
    }
  | Fragment of t list
  | Dynamic of (unit -> t)
  (* A component body, run when the view is inserted: under its own owner and
     untracked (see {!component}). *)
  | Component of (unit -> t)
  (* [child], or [fallback] once [child] raised; see {!error_boundary}. *)
  | Boundary of {
      child : t;
      fallback : exn -> (unit -> unit) -> t;
    }
  (* [child] rendered into another container; see {!portal}. *)
  | Portal of {
      target : Dom.t option;
      child : t;
    }
  (* [fallback] while a resource below is pending; see {!suspense}. *)
  | Suspense of {
      child : t;
      fallback : t;
    }
  (* A clone of [template]'s skeleton with its holes filled; see {!Template}. *)
  | Template of template * hole list
  | Keyed :
      {
        items : unit -> 'item list;
        key : 'item -> string;
        render : 'item Signal.t -> t;
      }
      -> t
  | Keyed_raw :
      {
        items : unit -> 'item list;
        key : 'item -> string;
        render : 'item -> t;
      }
      -> t

(* A place in a template's skeleton, by child indices from the skeleton's
   root, and what to put there. *)
and hole =
  | Hole_attr of int list * attr
  | Hole_event of int list * handler
  (* The node at the path is a text node; its data is set. *)
  | Hole_text of int list * string value
  (* The node at the path is a placeholder comment; the view replaces it. *)
  | Hole_child of int list * bool * t
  | Hole_attrs of int list * attr list

(* Ownership. Every Effect created while building a subtree registers with
   the current {!Owner}: a [Dynamic] region's effect owns its current pass and
   resets it before re-rendering, a keyed row owns its row, a component owns
   its body, and {!mount} provides the root. *)

(* Tail-recursive [List.map]. Lists here can hold every row of a long list,
   and js_of_ocaml runs on the browser's stack, which [List.map] (not
   tail-recursive before OCaml 5.1) overflows at around ten thousand items. *)
let map_list f l = List.rev (List.fold_left (fun acc x -> f x :: acc) [] l)

let place parent before node =
  match before with
  | Some ref_node -> Dom.insert_before parent node ref_node
  | None -> Dom.append_child parent node

(* Where a region inserts: the anchor's current parent. A region's nodes can
   move after it was created (a keyed row is built in a fragment and then
   inserted), so the parent it was created under is only a fallback. *)
let parent_of anchor fallback = match Dom.parent_node anchor with Some p -> p | None -> fallback

(* ----- leaves -----

   Each reactive leaf remembers the last value it wrote and skips the DOM when
   a run lands on the same value: selecting one row of a thousand runs every
   row's class effect, but only two of them write. *)

let leaf_string write f =
  let last = ref None in
  ignore
    (Effect_core.leaf (fun () ->
       let v = f () in
       (match !last with
        | Some prev when String.equal prev v -> ()
        | _ ->
          last := Some v;
          write v);
       None))

let leaf_bool write f =
  let last = ref None in
  ignore
    (Effect_core.leaf (fun () ->
       let v = f () in
       (match !last with
        | Some prev when prev = v -> ()
        | _ ->
          last := Some v;
          write v);
       None))

let toggle_attribute el name present =
  if present then Dom.set_attribute el name "" else Dom.remove_attribute el name

let apply_attr el = function
  | Attr_static ("value", v) -> Dom.set_value el v
  | Attr_static (name, v) -> Dom.set_attribute el name v
  | Attr_reactive ("value", f) -> leaf_string (Dom.set_value el) f
  | Attr_reactive (name, f) -> leaf_string (Dom.set_attribute el name) f
  | Attr_bool_static ("checked", v) -> Dom.set_checked el v
  | Attr_bool_static (name, v) -> toggle_attribute el name v
  | Attr_bool_reactive ("checked", f) -> leaf_bool (Dom.set_checked el) f
  | Attr_bool_reactive (name, f) | Attr_toggle (name, f) -> leaf_bool (toggle_attribute el name) f
  | Attr_ref r ->
    r.current <- Some el;
    (match r.on_set with Some f -> f el | None -> ());
    Owner.on_cleanup (fun () ->
      match r.current with Some e when e == el -> r.current <- None | _ -> ())
  | Attr_optional (name, f) ->
    let last = ref None and first = ref true in
    ignore
      (Effect_core.leaf (fun () ->
         let v = f () in
         if !first || v <> !last then begin
           first := false;
           last := v;
           match v with
           | Some v -> if name = "value" then Dom.set_value el v else Dom.set_attribute el name v
           | None -> Dom.remove_attribute el name
         end;
         None))

let rec apply_attrs el = function
  | [] -> ()
  | attr :: rest ->
    apply_attr el attr;
    apply_attrs el rest

let rec add_listeners el = function
  | [] -> ()
  | (name, handler) :: rest ->
    Dom.add_event_listener el name handler;
    add_listeners el rest

(* SVG. Elements created while [in_svg] holds go in the SVG namespace: an
   <svg> element sets it for its children, a <foreignObject> clears it again.
   Regions that re-render later (a [Dynamic] pass, a keyed row) capture the
   flag when they are created and restore it for each re-run. *)
let svg_namespace = "http://www.w3.org/2000/svg"
let in_svg = ref false

let with_svg svg f =
  let prev = !in_svg in
  in_svg := svg;
  match f () with
  | result ->
    in_svg := prev;
    result
  | exception e ->
    in_svg := prev;
    raise e

(* ----- on_mount -----

   [on_mount] callbacks wait until the insertion that created them is
   finished — the outermost [mount], region pass or list pass — so the nodes
   they look for are in place. [insertion] wraps each of those entry points;
   the callbacks run in registration order when the outermost one returns,
   each under the owner it was registered in, untracked, and only if that
   owner is still alive. *)

let mount_queue : (unit -> unit) list ref = ref []
let insertion_depth = ref 0

let flush_mount_queue () =
  while !mount_queue <> [] do
    let queued = List.rev !mount_queue in
    mount_queue := [];
    List.iter (fun f -> f ()) queued
  done

let insertion f =
  incr insertion_depth;
  match f () with
  | result ->
    decr insertion_depth;
    if !insertion_depth = 0 then flush_mount_queue ();
    result
  | exception e ->
    decr insertion_depth;
    if !insertion_depth = 0 then mount_queue := [];
    raise e

let on_mount f =
  let owner = Owner.active () in
  let run () =
    match owner with
    | Some o when Owner.is_disposed o -> ()
    | _ -> Owner.run owner (fun () -> Signal.untrack f)
  in
  if !insertion_depth = 0 then run () else mount_queue := run :: !mount_queue

let on_cleanup f = Owner.on_cleanup f

(* ----- templates ----- *)

let template_skeleton tpl svg =
  if not svg then
    match tpl.html_skeleton with
    | Some skeleton -> skeleton
    | None ->
      let skeleton = Dom.template_content tpl.html in
      tpl.html_skeleton <- Some skeleton;
      skeleton
  else
    match tpl.svg_skeleton with
    | Some skeleton -> skeleton
    | None ->
      (* Parsed inside an <svg> so its elements land in the SVG namespace,
         then moved out of it into a fragment of their own. *)
      let wrapper = Dom.template_content ("<svg>" ^ tpl.html ^ "</svg>") in
      let svg_el = Dom.child_at wrapper 0 in
      let skeleton = Dom.create_fragment () in
      let rec move () =
        match Dom.first_child svg_el with
        | Some node ->
          Dom.append_child skeleton node;
          move ()
        | None -> ()
      in
      move ();
      tpl.svg_skeleton <- Some skeleton;
      skeleton

(* ----- keyed lists -----

   A keyed list keeps one row per key across passes. [table] maps keys to rows
   and survives between passes; each pass stamps the rows it reaches, so the
   ones left unstamped are the stale ones, found without building a key set.
   [index] is a row's position in the previous pass, which is also its
   relative DOM order. *)

type 'item row = {
  key : string;
  mutable value : 'item;
  (* [Some] for [for_with_key]: a surviving row receives the new item here. *)
  signal : 'item Signal.t option;
  mutable nodes : Dom.t list;
  (* Owns the row's effects; disposed when the row is dropped. *)
  owner : Owner.t;
  mutable stamp : int;
  mutable index : int;
}

type 'item keyed_state = {
  mutable rows : 'item row array;
  table : (string, 'item row) Hashtbl.t;
  mutable pass : int;
}

let dispose_row row =
  Owner.dispose row.owner;
  List.iter Dom.remove row.nodes;
  row.nodes <- []

(* [build_row] needs [insert], which is defined below it in the same
   recursive group as the reconciler; this ref breaks the cycle. *)
let insert_ref : (Dom.t -> Dom.t option -> t -> Dom.t list ref -> unit) ref =
  ref (fun _ _ _ _ -> ())

(* Build one row into [into] (a fragment) under a fresh owner. The owner's
   parent is the current one (the list's reconciling effect), for context
   lookups; it is not registered there — the list disposes its rows itself.
   Rows render untracked, so a read in a row's render function never
   subscribes the whole list. *)
let build_row into view_of key value signal =
  let owner = Owner.make () in
  let nodes = ref [] in
  Owner.run_in owner (fun () ->
    Signal.untrack (fun () -> insert_ref.contents into None (view_of ()) nodes));
  { key; value; signal; nodes = List.rev !nodes; owner; stamp = 0; index = -1 }

(* Whether the rows (in order) and then the anchor are all of [parent]'s
   children. *)
let owns_parent parent anchor rows =
  Option.is_none (Dom.next_sibling anchor)
  &&
  let first =
    let rec find i =
      if i >= Array.length rows then Some anchor
      else match rows.(i).nodes with first :: _ -> Some first | [] -> find (i + 1)
    in
    find 0
  in
  match (first, Dom.first_child parent) with
  | Some a, Some b -> Dom.is_same_node a b
  | _ -> false

(* Indices into [positions] (values >= 0) forming a longest strictly
   increasing subsequence, as a membership array. O(n log n). *)
let lis_members positions =
  let n = Array.length positions in
  let member = Array.make n false in
  let tails = Array.make (n + 1) 0 (* index of the smallest tail per length *) in
  let prev = Array.make n (-1) in
  let len = ref 0 in
  for i = 0 to n - 1 do
    let p = positions.(i) in
    if p >= 0 then begin
      (* binary search for the first length whose tail is >= p *)
      let lo = ref 0 and hi = ref !len in
      while !lo < !hi do
        let mid = (!lo + !hi) / 2 in
        if positions.(tails.(mid)) < p then lo := mid + 1 else hi := mid
      done;
      if !lo > 0 then prev.(i) <- tails.(!lo - 1);
      tails.(!lo) <- i;
      if !lo = !len then incr len
    end
  done;
  if !len > 0 then begin
    let k = ref tails.(!len - 1) in
    while !k >= 0 do
      member.(!k) <- true;
      k := prev.(!k)
    done
  end;
  member

(* One pass of a keyed list.

   - Surviving rows are reused: [reuse row item] updates them and returns
     [false] when the row must be rebuilt instead ([for_] of raw items rebuilds
     a row whose item changed physically).
   - Stale rows are disposed and their nodes removed.
   - New rows are built in order, each run of consecutive new rows into one
     fragment that is inserted with a single DOM call.
   - Surviving rows that keep their relative order (a longest increasing
     subsequence of their previous positions) stay where they are; only the
     others move. An append, a removal or a swap moves nothing or almost
     nothing. *)
let reconcile ~make ~reuse anchor fallback_parent state items key =
  let parent = parent_of anchor fallback_parent in
  state.pass <- state.pass + 1;
  let pass = state.pass in
  let items = Array.of_list items in
  let n = Array.length items in
  let replaced = ref [] in
  (* Match items to rows. Slots for new rows hold [placeholder] until the rows
     are built below; nothing reads a slot before it is filled. *)
  let placeholder : _ row = Obj.magic 0 in
  let next = Array.make n placeholder in
  let is_new = Array.make n false in
  let old = state.rows in
  let old_n = Array.length old in
  for i = 0 to n - 1 do
    let item = items.(i) in
    let k = key item in
    (* A row that kept its index and key (appends, in-place updates) is found
       without hashing its key. *)
    let found =
      if i < old_n && String.equal old.(i).key k then old.(i)
      else match Hashtbl.find_opt state.table k with Some row -> row | None -> placeholder
    in
    if found == placeholder then is_new.(i) <- true
    else if found.stamp = pass then failwith ("View.for_with_key: duplicate key " ^ k)
    else if reuse found item then begin
      found.stamp <- pass;
      next.(i) <- found
    end
    else begin
      (* Rebuild: the old row goes once the new one is in place. *)
      found.stamp <- pass;
      replaced := found :: !replaced;
      is_new.(i) <- true
    end
  done;
  (* Drop stale rows (and rows being rebuilt). When every row goes and the
     list owns all of its parent's children (its rows, then its anchor), one
     [textContent] write empties the parent instead of a removal per node. *)
  if n = 0 && Array.length state.rows > 0 && owns_parent parent anchor state.rows then begin
    Dom.set_text_content parent "";
    Array.iter
      (fun row ->
        row.nodes <- [];
        Owner.dispose row.owner)
      state.rows;
    Hashtbl.reset state.table;
    Dom.append_child parent anchor
  end
  else
    Array.iter
      (fun row ->
        if row.stamp <> pass then begin
          Hashtbl.remove state.table row.key;
          dispose_row row
        end)
      state.rows;
  (* A rebuilt row's old entry must not count as a duplicate below. *)
  List.iter
    (fun row ->
      row.stamp <- -1;
      dispose_row row)
    !replaced;
  (* Build new rows in order, one fragment per run of consecutive new rows. *)
  let fragments = Array.make n None in
  let current = ref None in
  for i = 0 to n - 1 do
    if is_new.(i) then begin
      let fragment =
        match !current with
        | Some f -> f
        | None ->
          let f = Dom.create_fragment () in
          current := Some f;
          fragments.(i) <- Some f;
          f
      in
      let item = items.(i) in
      let k = key item in
      (match Hashtbl.find_opt state.table k with
       | Some existing when existing.stamp = pass ->
         failwith ("View.for_with_key: duplicate key " ^ k)
       | _ -> ());
      let row = make fragment item k in
      row.stamp <- pass;
      Hashtbl.replace state.table row.key row;
      next.(i) <- row
    end
    else current := None
  done;
  (* Place: walk backwards from the anchor. *)
  let positions = Array.init n (fun i -> if is_new.(i) then -1 else next.(i).index) in
  let stay = lis_members positions in
  let before = ref anchor in
  for i = n - 1 downto 0 do
    let row = next.(i) in
    if is_new.(i) then begin
      (* The first row of a run carries the run's fragment. *)
      match fragments.(i) with
      | Some fragment ->
        Dom.insert_before parent fragment !before;
        (* The run's first node is now the reference for what precedes it. *)
        let rec first_of j =
          if j >= n || not is_new.(j) then None
          else match next.(j).nodes with first :: _ -> Some first | [] -> first_of (j + 1)
        in
        (match first_of i with Some first -> before := first | None -> ())
      | None -> ()
    end
    else begin
      if not stay.(i) then List.iter (fun node -> Dom.insert_before parent node !before) row.nodes;
      match row.nodes with first :: _ -> before := first | [] -> ()
    end
  done;
  Array.iteri (fun i row -> row.index <- i) next;
  state.rows <- next

let keyed_region ~make ~reuse parent before acc items key =
  let anchor = Dom.create_comment "" in
  place parent before anchor;
  acc := anchor :: !acc;
  let state = { rows = [||]; table = Hashtbl.create 16; pass = 0 } in
  Owner.on_cleanup (fun () ->
    Array.iter dispose_row state.rows;
    state.rows <- [||];
    Hashtbl.reset state.table);
  let svg = !in_svg in
  Effect_core.run (fun () ->
    let items = items () in
    insertion (fun () -> with_svg svg (fun () -> reconcile ~make ~reuse anchor parent state items key));
    None)

(* Build [view] and insert its top-level nodes into [parent] (before [before],
   or appended when [before] is [None]). Top-level nodes are pushed onto [acc]
   so a [Dynamic] region can later remove exactly what it inserted. Effects
   created here register with the current owner. *)
let rec insert parent before view (acc : Dom.t list ref) =
  match view with
  | Empty -> ()
  | Text s ->
    let node = Dom.create_text_node s in
    place parent before node;
    acc := node :: !acc
  | Reactive_text f ->
    let node = Dom.create_text_node "" in
    leaf_string (Dom.set_text_content node) f;
    place parent before node;
    acc := node :: !acc
  | Element { tag; attrs; events; children } ->
    let el = insert_element tag attrs events children in
    place parent before el;
    acc := el :: !acc
  | Fragment views -> List.iter (fun v -> insert parent before v acc) views
  | Dynamic f -> dynamic_region parent before acc f
  | Component body ->
    (* Runs now, at insertion: under its own owner (disposed with the current
       one) and untracked, so reads in the body never subscribe the region
       that inserted it. *)
    let owner = Owner.make_child () in
    Owner.run_in owner (fun () -> insert parent before (Signal.untrack body) acc)
  | Keyed { items; key; render } ->
    keyed_region parent before acc items key
      ~make:(fun into item k ->
        let signal = Signal.make item in
        build_row into (fun () -> render signal) k item (Some signal))
      ~reuse:(fun row item ->
        (match row.signal with Some s -> Signal.set s item | None -> ());
        row.value <- item;
        true)
  | Keyed_raw { items; key; render } ->
    keyed_region parent before acc items key
      ~make:(fun into item k -> build_row into (fun () -> render item) k item None)
      ~reuse:(fun row item -> row.value == item)
  | Template (tpl, holes) -> insert_template parent before acc tpl holes
  | Boundary { child; fallback } -> boundary_region parent before acc child fallback
  | Portal { target; child } -> portal_region parent before acc target child
  | Suspense { child; fallback } -> suspense_region parent before acc child fallback

(* Build an element and its subtree.

   No closure created here captures [children] or [attrs]: js_of_ocaml's
   release build inlines the attribute helpers into this function, so a
   closure that captured the lists would share this call's scope with the
   attribute effects, which live as long as the element, and keep the whole
   view description of the subtree alive. Children are walked by a plain
   recursive loop for the same reason. *)
and insert_element tag attrs events children =
  let svg = !in_svg || tag = "svg" in
  let el = if svg then Dom.create_element_ns svg_namespace tag else Dom.create_element tag in
  apply_attrs el attrs;
  add_listeners el events;
  let prev = !in_svg in
  in_svg := svg && tag <> "foreignObject";
  (match insert_children el children with
   | () -> in_svg := prev
   | exception e ->
     in_svg := prev;
     raise e);
  el

(* Children go straight into [el]; their top-level nodes are irrelevant to the
   caller, so they share a throwaway accumulator. *)
and insert_children el = function
  | [] -> ()
  | child :: rest ->
    insert el None child (ref []);
    insert_children el rest

(* A region rebuilt whenever a signal [f] read changes. The anchor stays put;
   the region's nodes live just before it. The effect owns each pass: before a
   re-run it disposes everything the previous pass created.

   When the previous pass and the new one are both a single text, the text
   node is kept and only its data is written: a [View.child] thunk returning a
   string or a number updates like a reactive text leaf instead of rebuilding
   a node each time. *)
and dynamic_region parent before acc f =
  let anchor = Dom.create_comment "" in
  place parent before anchor;
  acc := anchor :: !acc;
  let region : Dom.t list ref = ref [] in
  let text_node = ref None in
  let clear () =
    List.iter Dom.remove !region;
    region := [];
    text_node := None
  in
  Owner.on_cleanup clear;
  let svg = !in_svg in
  Effect_core.run (fun () ->
    let view = f () in
    (match (view, !text_node) with
     | Text s, Some node -> Dom.set_text_content node s
     | _ ->
       clear ();
       let local = ref [] in
       insertion (fun () ->
         with_svg svg (fun () -> insert (parent_of anchor parent) (Some anchor) view local));
       region := !local;
       (match (view, !local) with Text _, [ node ] -> text_node := Some node | _ -> ()));
    None)

(* A template instance: clone the skeleton, find every hole's node before
   touching any (filling a child hole shifts the indices after it), fill the
   holes, then move the whole clone into place with one call. *)
and insert_template parent before acc tpl holes =
  let svg = !in_svg in
  let fragment = Dom.clone_node (template_skeleton tpl svg) in
  let rec resolve node = function [] -> node | i :: rest -> resolve (Dom.child_at node i) rest in
  let rec locate = function
    | [] -> []
    | hole :: rest ->
      let path =
        match hole with
        | Hole_attr (p, _) | Hole_event (p, _) | Hole_text (p, _) | Hole_child (p, _, _) | Hole_attrs (p, _) -> p
      in
      resolve fragment path :: locate rest
  in
  let rec fill holes nodes =
    match (holes, nodes) with
    | hole :: holes, node :: nodes ->
      (match hole with
       | Hole_attr (_, a) -> apply_attr node a
       | Hole_attrs (_, l) -> apply_attrs node l
       | Hole_event (_, (name, handler)) -> Dom.add_event_listener node name handler
       | Hole_text (_, Static s) -> Dom.set_text_content node s
       | Hole_text (_, Reactive f) -> leaf_string (Dom.set_text_content node) f
       | Hole_child (_, hole_svg, view) ->
         let p = parent_of node fragment in
         with_svg (svg || hole_svg) (fun () -> insert p (Some node) view (ref []));
         Dom.remove node);
      fill holes nodes
    | _ -> ()
  in
  fill holes (locate holes);
  let rec collect = function
    | None -> ()
    | Some node ->
      acc := node :: !acc;
      collect (Dom.next_sibling node)
  in
  collect (Dom.first_child fragment);
  place parent before fragment

(* An error boundary. The child renders under an owner whose parent carries
   the error handler, so an exception raised while rendering the child, or
   later by any effect below it, replaces the child with [fallback err reset];
   [reset ()] renders the child again. The fallback renders outside the
   boundary: its own errors go to the next boundary up. *)
and boundary_region parent before acc child fallback =
  let anchor = Dom.create_comment "" in
  place parent before anchor;
  acc := anchor :: !acc;
  let outer = Owner.active () in
  let boundary = Owner.make_child () in
  let region = ref [] and pass = ref None and rendering = ref false in
  let svg = !in_svg in
  let clear () =
    List.iter Dom.remove !region;
    region := [];
    match !pass with
    | Some o ->
      pass := None;
      Owner.dispose o
    | None -> ()
  in
  Owner.add_cleanup boundary clear;
  let rec render ~handled view_of =
    clear ();
    let o = Owner.make ~parent:(if handled then Some boundary else outer) () in
    pass := Some o;
    let local = ref [] in
    rendering := handled;
    match
      insertion (fun () ->
        Owner.run_in o (fun () ->
          with_svg svg (fun () -> insert (parent_of anchor parent) (Some anchor) (view_of ()) local)))
    with
    | () ->
      rendering := false;
      region := !local
    | exception e ->
      rendering := false;
      region := !local;
      if handled then failed e else raise e
  and failed e = render ~handled:false (fun () -> fallback e reset)
  and reset () = render ~handled:true (fun () -> child) in
  (* While the child is being rendered, an effect's error unwinds that render
     (re-raised here, caught above) instead of swapping regions mid-insert. *)
  Owner.set_error_handler boundary (fun e -> if !rendering then raise e else failed e);
  Owner.run_in boundary (fun () -> reset ())

(* A portal: [child] is appended to [target] (default: <body>) but owned here,
   so it is disposed and its nodes removed with this point of the tree, and
   context lookups inside it see this point's providers. *)
and portal_region parent before acc target child =
  let anchor = Dom.create_comment "portal" in
  place parent before anchor;
  acc := anchor :: !acc;
  let target = match target with Some t -> t | None -> Dom.body () in
  let owner = Owner.make_child () in
  let nodes = ref [] in
  Owner.add_cleanup owner (fun () ->
    List.iter Dom.remove !nodes;
    nodes := []);
  Owner.run_in owner (fun () -> with_svg false (fun () -> insert target None child nodes))

(* Suspense. The child renders right away, between two comment markers in a
   detached fragment, under an owner that provides a pending counter
   ({!Suspense_scope}). While the counter is above zero the fallback is shown
   and the child's nodes wait in the fragment; when it drops to zero the
   fallback goes and the child's nodes move into place, effects and all. *)
and suspense_region parent before acc child fallback =
  let anchor = Dom.create_comment "" in
  place parent before anchor;
  acc := anchor :: !acc;
  let svg = !in_svg in
  let counter = Signal.make 0 in
  let owner = Owner.make_child () in
  Owner.provide owner Suspense_scope.key (Some counter);
  let holder = Dom.create_fragment () in
  let start_marker = Dom.create_comment "" and end_marker = Dom.create_comment "" in
  Dom.append_child holder start_marker;
  Owner.run_in owner (fun () -> with_svg svg (fun () -> insert holder None child (ref [])));
  Dom.append_child holder end_marker;
  (* The child's nodes, markers included, in document order. *)
  let child_nodes () =
    let rec walk node acc =
      let acc = node :: acc in
      if node == end_marker then List.rev acc
      else match Dom.next_sibling node with Some next -> walk next acc | None -> List.rev acc
    in
    walk start_marker []
  in
  let in_holder () =
    match Dom.parent_node start_marker with Some p -> Dom.is_same_node p holder | None -> true
  in
  let fallback_nodes = ref [] and fallback_owner = ref None in
  let hide_fallback () =
    List.iter Dom.remove !fallback_nodes;
    fallback_nodes := [];
    match !fallback_owner with
    | Some o ->
      fallback_owner := None;
      Owner.dispose o
    | None -> ()
  in
  Owner.on_cleanup (fun () ->
    hide_fallback ();
    List.iter Dom.remove (child_nodes ()));
  Effect_core.run (fun () ->
    let pending = Signal.get counter > 0 in
    let p = parent_of anchor parent in
    Signal.untrack (fun () ->
      if pending then begin
        if not (in_holder ()) then List.iter (Dom.append_child holder) (child_nodes ());
        if Option.is_none !fallback_owner then begin
          let o = Owner.make () in
          fallback_owner := Some o;
          let local = ref [] in
          insertion (fun () ->
            Owner.run_in o (fun () -> with_svg svg (fun () -> insert p (Some anchor) fallback local)));
          fallback_nodes := !local
        end
      end
      else begin
        hide_fallback ();
        if in_holder () then
          insertion (fun () -> List.iter (fun node -> Dom.insert_before p node anchor) (child_nodes ()))
      end);
    None)

let () = insert_ref := insert

(* ----- public constructors ----- *)

let static value = Static value
let dynamic value = Reactive value
let signal signal = Reactive (fun () -> Signal.get signal)

let value_getter = function Static value -> fun () -> value | Reactive f -> f
let map_value f = function
  | Static value -> Static (f value)
  | Reactive value -> Reactive (fun () -> f (value ()))

(* Renders nothing. Exposed as an empty fragment rather than the [Empty]
   constructor: constant constructors are plain integers in the Melange
   representation, and {!child} must be able to tell an empty view apart from a
   literal [0]. *)
let empty = Fragment []
let text = function Static s -> Text s | Reactive f -> Reactive_text f
let int value = text (map_value string_of_int value)
let float value = text (map_value string_of_float value)
let dyn_text f = text (dynamic f)
let dyn_int f = int (dynamic f)
let dyn_float f = float (dynamic f)
let fragment views = Fragment views

(* A component: [body] runs when the view is mounted, not when this value is
   built — under its own owner, so effects, computeds and cleanups it creates
   are disposed with it, and untracked, so its signal reads never subscribe
   the region around it. The mlx ppx wraps every component tag in this. *)
let component body = Component body

(* ----- templates (public) ----- *)

type view = t

module Template = struct
  type t = template
  type nonrec hole = hole

  let make html = { html; html_skeleton = None; svg_skeleton = None }
  let attr path a = Hole_attr (path, a)
  let event path name handler = Hole_event (path, (name, handler))
  let text path v = Hole_text (path, v)
  let child ?(svg = false) path (view : view) = Hole_child (path, svg, view)
  let attrs path l = Hole_attrs (path, l)

  (* Typed props, one per kind of the mlx prop table, so generated code is
     checked like View.Mlx.create. *)
  let string_prop path name = function
    | Static v -> Hole_attr (path, Attr_static (name, v))
    | Reactive f -> Hole_attr (path, Attr_reactive (name, f))

  let int_prop path name v = string_prop path name (map_value string_of_int v)

  let toggle_prop path name = function
    | Static b -> Hole_attr (path, Attr_bool_static (name, b))
    | Reactive f -> Hole_attr (path, Attr_toggle (name, f))

  let bool_prop path name = function
    | Static b -> Hole_attr (path, Attr_bool_static (name, b))
    | Reactive f -> Hole_attr (path, Attr_bool_reactive (name, f))

  let instance tpl holes = Template (tpl, holes)
end

let template = Template.instance

(* ----- refs, boundaries, portals, suspense ----- *)

module Ref = struct
  type t = element_ref

  let make () = { current = None; on_set = None }
  let from_callback f = { current = None; on_set = Some f }
  let current r = r.current
end

let error_boundary ~fallback child = Boundary { child; fallback }

module ErrorBoundary = struct
  let component ~fallback ~children () = error_boundary ~fallback (Fragment children)
  let createElement () ~children ~fallback = component ~fallback ~children ()
end

let portal ?target child = Portal { target; child }

module Portal = struct
  let component ?target ~children () = portal ?target (Fragment children)
  let createElement ?target () ~children = component ?target ~children ()
end

let suspense ~fallback child = Suspense { child; fallback }

module Suspense = struct
  let component ~fallback ~children () = suspense ~fallback (Fragment children)
  let createElement () ~children ~fallback = component ~fallback ~children ()
end

let element ?(attrs = []) ?(events = []) tag children =
  Element { tag; attrs; events; children }

(* A reactive region: [f] is re-run (and its subtree rebuilt) whenever a signal
   it reads changes. The building block behind {!show}, {!maybe} and {!for_}. *)
let dyn f = Dynamic f

(* xote-style name for {!dyn}: a block that auto-subscribes to every signal
   read while building its children and swaps them wholesale on change. Use it
   when a whole region depends on structural state; prefer reactive text and
   attributes for fine-grained updates. *)
let tracked f = Dynamic f

(* Runtime child coercion (xote's [View.child]): accept whatever a JSX child
   evaluates to and build the right node for it. The mlx PPX routes bare JSX
   children here when it cannot tell their type at compile time.

   SUPPORTED BARE CHILDREN — guaranteed identical on every backend:

   - [string]                  renders as text
   - [int] / [float]           rendered via JS [String]
   - an already-built [t]      passes through untouched
   - a thunk ([unit -> _])     becomes a tracked region, re-coerced whenever a
                               signal it read changes

   NOT SUPPORTED — [option] and [bool]. Their JS representation is
   backend-specific: js_of_ocaml maps [None], [false] and [0] onto the same JS
   value, so no runtime check can recover them (see {!Dom.classify}). Use the
   constructors that carry the OCaml type through instead, which render the
   same on any backend:

   {[
     View.maybe (fun () -> current_user ()) render   (* not a bare option *)
     View.show  (fun () -> is_open ()) content       (* not a bare bool   *)
   ]}

   The [Obj.magic]s below are irreducible for a function of this shape: it
   accepts ['a] precisely because the PPX has no type information to give it,
   so the classification is the only evidence available. They are confined to
   this one function, and each is guarded by the classification immediately
   above it. *)
let rec child : 'a. 'a -> t =
 fun x ->
  match Dom.classify x with
  | `String -> Text (Obj.magic x : string)
  | `Number | `Boolean -> Text (Dom.display_string x)
  | `Function -> Dynamic (fun () -> child ((Obj.magic x : unit -> Obj.t) ()))
  | `Object -> (Obj.magic x : t)
  (* Melange's [None]. Unreachable under js_of_ocaml, which classifies it as
     [`Number] — hence the "not supported" note above. *)
  | `Undefined -> Empty
  (* [symbol], and anything a future backend classifies as neither a scalar nor
     an object. Render nothing rather than [Obj.magic] a non-view into [t]. *)
  | `Other -> Empty

(* ----- control flow (xote-style components, as plain functions) ----- *)

(* Render [child] while [cond ()] holds, otherwise [fallback]. *)
let show ?(fallback = Empty) cond child =
  Dynamic (fun () -> if cond () then child else fallback)

(* Render from the [Some] case of an option signal, otherwise [fallback]. *)
let maybe ?(fallback = Empty) get f =
  Dynamic (fun () -> match get () with Some x -> f x | None -> fallback)

(* Map a (reactive) list to a view. The whole list re-renders when [items]
   changes. *)
let for_ items f = Dynamic (fun () -> Fragment (map_list f (items ())))

(* Map a reactive list by stable string key. Existing keyed rows keep their DOM
   nodes and effects; each row receives a signal that is updated with the latest
   item value for that key. *)
let for_with_key items ~key render = Keyed { items; key; render }
let forWithKey = for_with_key

module Show = struct
  let component ?(fallback = Empty) ~condition ~children () =
    show ~fallback (value_getter condition) (Fragment children)

  let createElement ?fallback () ~children ~condition =
    component ?fallback ~condition ~children ()
end

module Maybe = struct
  let component ?(fallback = Empty) ~value ~render () =
    maybe ~fallback (value_getter value) render

  let createElement ?fallback () ~children:_ ~value ~render =
    component ?fallback ~value ~render ()
end

module ForEach = struct
  let component ?key ~items ~render () =
    let items = value_getter items in
    match key with
    | None -> for_ items render
    | Some key -> Keyed_raw { items; key; render }

  let createElement ?key () ~children:_ ~items ~render =
    component ?key ~items ~render ()
end

(* ----- common HTML element helpers ----- *)

let tag name ?attrs ?events children = element ?attrs ?events name children
let div = tag "div"
let span = tag "span"
let p = tag "p"
let h1 = tag "h1"
let h2 = tag "h2"
let h3 = tag "h3"
let ul = tag "ul"
let ol = tag "ol"
let li = tag "li"
let button = tag "button"
let a = tag "a"
let input ?attrs ?events () = element ?attrs ?events "input" []
let label = tag "label"
let section = tag "section"

(* ----- attribute helpers ----- *)

module Attr = struct
  let make name = function
    | Static v -> Attr_static (name, v)
    | Reactive f -> Attr_reactive (name, f)

  let reactive name f = make name (dynamic f)
  let toggle name f = Attr_toggle (name, f)
  let class_ v = make "class" v
  let className v = class_ v
  let class_reactive f = class_ (dynamic f)
  let className_reactive f = class_reactive f
  let id v = make "id" v
  let type_ v = make "type" v
  let value v = make "value" v
  let value_reactive f = value (dynamic f)
  let placeholder v = make "placeholder" v
  let href v = make "href" v
  let disabled f = Attr_toggle ("disabled", f)
  let bool_property name = function
    | Static v -> Attr_bool_static (name, v)
    | Reactive f -> Attr_bool_reactive (name, f)

  let checked v = bool_property "checked" v

  (* An attribute that is present while [f ()] is [Some v] (with value [v])
     and removed while it is [None]. *)
  let optional name f = Attr_optional (name, f)

  (* A [data-*] attribute: [data "id" v] sets [data-id]. *)
  let data name v = make ("data-" ^ name) v

  (* Fill [r] with the element. *)
  let ref_ r = Attr_ref r
end

(* ----- event helpers ----- *)

module On = struct
  let on name handler : handler = (name, handler)
  let click handler : handler = ("click", handler)
  let input handler : handler = ("input", handler)
  let change handler : handler = ("change", handler)
  let keydown handler : handler = ("keydown", handler)
  let submit handler : handler = ("submit", handler)
end

(* The targets of mlx's element lowering: [<input type_="text" />] becomes
   [Mlx.input ~type_:(static "text") ()] once the ppx has wrapped the values.
   [attrs] takes any further attributes (data-*, custom elements), appended
   after the typed ones. *)
module Mlx = struct
  let static = static
  let dynamic = dynamic
  let signal = signal

  (* BEGIN GENERATED MLX PROPS *)
  (* Generated by scripts/generate-mlx-props.mjs from its prop table; edit
     the table, not this block. *)

  let push_string name value attrs =
    match value with Some value -> Attr.make name value :: attrs | None -> attrs

  let push_int name value attrs =
    match value with
    | Some value -> Attr.make name (map_value string_of_int value) :: attrs
    | None -> attrs

  let push_toggle name value attrs =
    match value with
    | Some (Static true) -> Attr_static (name, "") :: attrs
    | Some (Static false) | None -> attrs
    | Some (Reactive f) -> Attr.toggle name f :: attrs

  let push_prop name value attrs =
    match value with Some value -> Attr.bool_property name value :: attrs | None -> attrs

  let push_event name handler events =
    match handler with Some handler -> (name, handler) :: events | None -> events

  type element =
    ?class_:string value ->
    ?className:string value ->
    ?id:string value ->
    ?title:string value ->
    ?lang:string value ->
    ?dir:string value ->
    ?role:string value ->
    ?style:string value ->
    ?tabIndex:int value ->
    ?hidden:bool value ->
    ?draggable:string value ->
    ?contentEditable:string value ->
    ?spellcheck:string value ->
    ?translate:string value ->
    ?slot:string value ->
    ?aria_label:string value ->
    ?aria_labelledby:string value ->
    ?aria_describedby:string value ->
    ?aria_hidden:string value ->
    ?aria_expanded:string value ->
    ?aria_controls:string value ->
    ?aria_current:string value ->
    ?aria_pressed:string value ->
    ?aria_selected:string value ->
    ?aria_checked:string value ->
    ?aria_disabled:string value ->
    ?aria_live:string value ->
    ?aria_haspopup:string value ->
    ?aria_invalid:string value ->
    ?href:string value ->
    ?target:string value ->
    ?rel:string value ->
    ?download:string value ->
    ?hreflang:string value ->
    ?src:string value ->
    ?srcSet:string value ->
    ?sizes:string value ->
    ?alt:string value ->
    ?width:string value ->
    ?height:string value ->
    ?loading:string value ->
    ?decoding:string value ->
    ?crossOrigin:string value ->
    ?poster:string value ->
    ?preload:string value ->
    ?controls:bool value ->
    ?autoplay:bool value ->
    ?loop:bool value ->
    ?muted:bool value ->
    ?playsInline:bool value ->
    ?name:string value ->
    ?type_:string value ->
    ?value:string value ->
    ?placeholder:string value ->
    ?for_:string value ->
    ?htmlFor:string value ->
    ?form:string value ->
    ?action:string value ->
    ?method_:string value ->
    ?enctype:string value ->
    ?accept:string value ->
    ?acceptCharset:string value ->
    ?autocomplete:string value ->
    ?pattern:string value ->
    ?min:string value ->
    ?max:string value ->
    ?step:string value ->
    ?minLength:int value ->
    ?maxLength:int value ->
    ?size:int value ->
    ?rows:int value ->
    ?cols:int value ->
    ?wrap:string value ->
    ?list:string value ->
    ?inputMode:string value ->
    ?enterKeyHint:string value ->
    ?label_:string value ->
    ?disabled:bool value ->
    ?required:bool value ->
    ?readOnly:bool value ->
    ?multiple:bool value ->
    ?autofocus:bool value ->
    ?noValidate:bool value ->
    ?checked:bool value ->
    ?selected:bool value ->
    ?colSpan:int value ->
    ?rowSpan:int value ->
    ?headers:string value ->
    ?scope:string value ->
    ?start:int value ->
    ?reversed:bool value ->
    ?open_:bool value ->
    ?dateTime:string value ->
    ?cite:string value ->
    ?viewBox:string value ->
    ?xmlns:string value ->
    ?d:string value ->
    ?fill:string value ->
    ?fill_rule:string value ->
    ?fill_opacity:string value ->
    ?stroke:string value ->
    ?stroke_width:string value ->
    ?stroke_linecap:string value ->
    ?stroke_linejoin:string value ->
    ?stroke_dasharray:string value ->
    ?stroke_dashoffset:string value ->
    ?opacity:string value ->
    ?transform:string value ->
    ?cx:string value ->
    ?cy:string value ->
    ?r:string value ->
    ?rx:string value ->
    ?ry:string value ->
    ?x:string value ->
    ?y:string value ->
    ?x1:string value ->
    ?y1:string value ->
    ?x2:string value ->
    ?y2:string value ->
    ?points:string value ->
    ?offset:string value ->
    ?stop_color:string value ->
    ?preserveAspectRatio:string value ->
    ?onClick:(Dom.event -> unit) ->
    ?onDblClick:(Dom.event -> unit) ->
    ?onContextMenu:(Dom.event -> unit) ->
    ?onInput:(Dom.event -> unit) ->
    ?onChange:(Dom.event -> unit) ->
    ?onSubmit:(Dom.event -> unit) ->
    ?onReset:(Dom.event -> unit) ->
    ?onInvalid:(Dom.event -> unit) ->
    ?onKeyDown:(Dom.event -> unit) ->
    ?onKeyUp:(Dom.event -> unit) ->
    ?onFocus:(Dom.event -> unit) ->
    ?onBlur:(Dom.event -> unit) ->
    ?onFocusIn:(Dom.event -> unit) ->
    ?onFocusOut:(Dom.event -> unit) ->
    ?onMouseDown:(Dom.event -> unit) ->
    ?onMouseUp:(Dom.event -> unit) ->
    ?onMouseEnter:(Dom.event -> unit) ->
    ?onMouseLeave:(Dom.event -> unit) ->
    ?onMouseMove:(Dom.event -> unit) ->
    ?onMouseOver:(Dom.event -> unit) ->
    ?onMouseOut:(Dom.event -> unit) ->
    ?onPointerDown:(Dom.event -> unit) ->
    ?onPointerUp:(Dom.event -> unit) ->
    ?onPointerMove:(Dom.event -> unit) ->
    ?onPointerEnter:(Dom.event -> unit) ->
    ?onPointerLeave:(Dom.event -> unit) ->
    ?onPointerOver:(Dom.event -> unit) ->
    ?onPointerOut:(Dom.event -> unit) ->
    ?onPointerCancel:(Dom.event -> unit) ->
    ?onTouchStart:(Dom.event -> unit) ->
    ?onTouchMove:(Dom.event -> unit) ->
    ?onTouchEnd:(Dom.event -> unit) ->
    ?onTouchCancel:(Dom.event -> unit) ->
    ?onWheel:(Dom.event -> unit) ->
    ?onScroll:(Dom.event -> unit) ->
    ?onDragStart:(Dom.event -> unit) ->
    ?onDrag:(Dom.event -> unit) ->
    ?onDragEnd:(Dom.event -> unit) ->
    ?onDragEnter:(Dom.event -> unit) ->
    ?onDragOver:(Dom.event -> unit) ->
    ?onDragLeave:(Dom.event -> unit) ->
    ?onDrop:(Dom.event -> unit) ->
    ?onCopy:(Dom.event -> unit) ->
    ?onCut:(Dom.event -> unit) ->
    ?onPaste:(Dom.event -> unit) ->
    ?onLoad:(Dom.event -> unit) ->
    ?onError:(Dom.event -> unit) ->
    ?onToggle:(Dom.event -> unit) ->
    ?onClose:(Dom.event -> unit) ->
    ?onAnimationStart:(Dom.event -> unit) ->
    ?onAnimationEnd:(Dom.event -> unit) ->
    ?onTransitionEnd:(Dom.event -> unit) ->
    ?onPlay:(Dom.event -> unit) ->
    ?onPause:(Dom.event -> unit) ->
    ?onEnded:(Dom.event -> unit) ->
    ?onTimeUpdate:(Dom.event -> unit) ->
    ?ref:Ref.t ->
    ?attrs:attr list ->
    ?children:t list ->
    unit ->
    t

  (* [className] wins over [class_] when both are given. *)
  let create tag : element = fun ?class_ ?className
      ?id ?title ?lang ?dir ?role ?style ?tabIndex ?hidden ?draggable ?contentEditable ?spellcheck ?translate ?slot ?aria_label ?aria_labelledby ?aria_describedby ?aria_hidden ?aria_expanded ?aria_controls ?aria_current ?aria_pressed ?aria_selected ?aria_checked ?aria_disabled ?aria_live ?aria_haspopup ?aria_invalid ?href ?target ?rel ?download ?hreflang ?src ?srcSet ?sizes ?alt ?width ?height ?loading ?decoding ?crossOrigin ?poster ?preload ?controls ?autoplay ?loop ?muted ?playsInline ?name ?type_ ?value ?placeholder ?for_ ?htmlFor ?form ?action ?method_ ?enctype ?accept ?acceptCharset ?autocomplete ?pattern ?min ?max ?step ?minLength ?maxLength ?size ?rows ?cols ?wrap ?list ?inputMode ?enterKeyHint ?label_ ?disabled ?required ?readOnly ?multiple ?autofocus ?noValidate ?checked ?selected ?colSpan ?rowSpan ?headers ?scope ?start ?reversed ?open_ ?dateTime ?cite ?viewBox ?xmlns ?d ?fill ?fill_rule ?fill_opacity ?stroke ?stroke_width ?stroke_linecap ?stroke_linejoin ?stroke_dasharray ?stroke_dashoffset ?opacity ?transform ?cx ?cy ?r ?rx ?ry ?x ?y ?x1 ?y1 ?x2 ?y2 ?points ?offset ?stop_color ?preserveAspectRatio
      ?onClick ?onDblClick ?onContextMenu ?onInput ?onChange ?onSubmit ?onReset ?onInvalid ?onKeyDown ?onKeyUp ?onFocus ?onBlur ?onFocusIn ?onFocusOut ?onMouseDown ?onMouseUp ?onMouseEnter ?onMouseLeave ?onMouseMove ?onMouseOver ?onMouseOut ?onPointerDown ?onPointerUp ?onPointerMove ?onPointerEnter ?onPointerLeave ?onPointerOver ?onPointerOut ?onPointerCancel ?onTouchStart ?onTouchMove ?onTouchEnd ?onTouchCancel ?onWheel ?onScroll ?onDragStart ?onDrag ?onDragEnd ?onDragEnter ?onDragOver ?onDragLeave ?onDrop ?onCopy ?onCut ?onPaste ?onLoad ?onError ?onToggle ?onClose ?onAnimationStart ?onAnimationEnd ?onTransitionEnd ?onPlay ?onPause ?onEnded ?onTimeUpdate
      ?ref ?(attrs = []) ?(children = []) () ->
    let class_ = match className with Some _ -> className | None -> class_ in
    let acc = push_string "class" class_ [] in
    let acc = push_string "id" id acc in
    let acc = push_string "title" title acc in
    let acc = push_string "lang" lang acc in
    let acc = push_string "dir" dir acc in
    let acc = push_string "role" role acc in
    let acc = push_string "style" style acc in
    let acc = push_int "tabindex" tabIndex acc in
    let acc = push_toggle "hidden" hidden acc in
    let acc = push_string "draggable" draggable acc in
    let acc = push_string "contenteditable" contentEditable acc in
    let acc = push_string "spellcheck" spellcheck acc in
    let acc = push_string "translate" translate acc in
    let acc = push_string "slot" slot acc in
    let acc = push_string "aria-label" aria_label acc in
    let acc = push_string "aria-labelledby" aria_labelledby acc in
    let acc = push_string "aria-describedby" aria_describedby acc in
    let acc = push_string "aria-hidden" aria_hidden acc in
    let acc = push_string "aria-expanded" aria_expanded acc in
    let acc = push_string "aria-controls" aria_controls acc in
    let acc = push_string "aria-current" aria_current acc in
    let acc = push_string "aria-pressed" aria_pressed acc in
    let acc = push_string "aria-selected" aria_selected acc in
    let acc = push_string "aria-checked" aria_checked acc in
    let acc = push_string "aria-disabled" aria_disabled acc in
    let acc = push_string "aria-live" aria_live acc in
    let acc = push_string "aria-haspopup" aria_haspopup acc in
    let acc = push_string "aria-invalid" aria_invalid acc in
    let acc = push_string "href" href acc in
    let acc = push_string "target" target acc in
    let acc = push_string "rel" rel acc in
    let acc = push_string "download" download acc in
    let acc = push_string "hreflang" hreflang acc in
    let acc = push_string "src" src acc in
    let acc = push_string "srcset" srcSet acc in
    let acc = push_string "sizes" sizes acc in
    let acc = push_string "alt" alt acc in
    let acc = push_string "width" width acc in
    let acc = push_string "height" height acc in
    let acc = push_string "loading" loading acc in
    let acc = push_string "decoding" decoding acc in
    let acc = push_string "crossorigin" crossOrigin acc in
    let acc = push_string "poster" poster acc in
    let acc = push_string "preload" preload acc in
    let acc = push_toggle "controls" controls acc in
    let acc = push_toggle "autoplay" autoplay acc in
    let acc = push_toggle "loop" loop acc in
    let acc = push_toggle "muted" muted acc in
    let acc = push_toggle "playsinline" playsInline acc in
    let acc = push_string "name" name acc in
    let acc = push_string "type" type_ acc in
    let acc = push_string "value" value acc in
    let acc = push_string "placeholder" placeholder acc in
    let acc = push_string "for" for_ acc in
    let acc = push_string "for" htmlFor acc in
    let acc = push_string "form" form acc in
    let acc = push_string "action" action acc in
    let acc = push_string "method" method_ acc in
    let acc = push_string "enctype" enctype acc in
    let acc = push_string "accept" accept acc in
    let acc = push_string "accept-charset" acceptCharset acc in
    let acc = push_string "autocomplete" autocomplete acc in
    let acc = push_string "pattern" pattern acc in
    let acc = push_string "min" min acc in
    let acc = push_string "max" max acc in
    let acc = push_string "step" step acc in
    let acc = push_int "minlength" minLength acc in
    let acc = push_int "maxlength" maxLength acc in
    let acc = push_int "size" size acc in
    let acc = push_int "rows" rows acc in
    let acc = push_int "cols" cols acc in
    let acc = push_string "wrap" wrap acc in
    let acc = push_string "list" list acc in
    let acc = push_string "inputmode" inputMode acc in
    let acc = push_string "enterkeyhint" enterKeyHint acc in
    let acc = push_string "label" label_ acc in
    let acc = push_toggle "disabled" disabled acc in
    let acc = push_toggle "required" required acc in
    let acc = push_toggle "readonly" readOnly acc in
    let acc = push_toggle "multiple" multiple acc in
    let acc = push_toggle "autofocus" autofocus acc in
    let acc = push_toggle "novalidate" noValidate acc in
    let acc = push_prop "checked" checked acc in
    let acc = push_prop "selected" selected acc in
    let acc = push_int "colspan" colSpan acc in
    let acc = push_int "rowspan" rowSpan acc in
    let acc = push_string "headers" headers acc in
    let acc = push_string "scope" scope acc in
    let acc = push_int "start" start acc in
    let acc = push_toggle "reversed" reversed acc in
    let acc = push_toggle "open" open_ acc in
    let acc = push_string "datetime" dateTime acc in
    let acc = push_string "cite" cite acc in
    let acc = push_string "viewBox" viewBox acc in
    let acc = push_string "xmlns" xmlns acc in
    let acc = push_string "d" d acc in
    let acc = push_string "fill" fill acc in
    let acc = push_string "fill-rule" fill_rule acc in
    let acc = push_string "fill-opacity" fill_opacity acc in
    let acc = push_string "stroke" stroke acc in
    let acc = push_string "stroke-width" stroke_width acc in
    let acc = push_string "stroke-linecap" stroke_linecap acc in
    let acc = push_string "stroke-linejoin" stroke_linejoin acc in
    let acc = push_string "stroke-dasharray" stroke_dasharray acc in
    let acc = push_string "stroke-dashoffset" stroke_dashoffset acc in
    let acc = push_string "opacity" opacity acc in
    let acc = push_string "transform" transform acc in
    let acc = push_string "cx" cx acc in
    let acc = push_string "cy" cy acc in
    let acc = push_string "r" r acc in
    let acc = push_string "rx" rx acc in
    let acc = push_string "ry" ry acc in
    let acc = push_string "x" x acc in
    let acc = push_string "y" y acc in
    let acc = push_string "x1" x1 acc in
    let acc = push_string "y1" y1 acc in
    let acc = push_string "x2" x2 acc in
    let acc = push_string "y2" y2 acc in
    let acc = push_string "points" points acc in
    let acc = push_string "offset" offset acc in
    let acc = push_string "stop-color" stop_color acc in
    let acc = push_string "preserveAspectRatio" preserveAspectRatio acc in
    let events = [] in
    let events = push_event "click" onClick events in
    let events = push_event "dblclick" onDblClick events in
    let events = push_event "contextmenu" onContextMenu events in
    let events = push_event "input" onInput events in
    let events = push_event "change" onChange events in
    let events = push_event "submit" onSubmit events in
    let events = push_event "reset" onReset events in
    let events = push_event "invalid" onInvalid events in
    let events = push_event "keydown" onKeyDown events in
    let events = push_event "keyup" onKeyUp events in
    let events = push_event "focus" onFocus events in
    let events = push_event "blur" onBlur events in
    let events = push_event "focusin" onFocusIn events in
    let events = push_event "focusout" onFocusOut events in
    let events = push_event "mousedown" onMouseDown events in
    let events = push_event "mouseup" onMouseUp events in
    let events = push_event "mouseenter" onMouseEnter events in
    let events = push_event "mouseleave" onMouseLeave events in
    let events = push_event "mousemove" onMouseMove events in
    let events = push_event "mouseover" onMouseOver events in
    let events = push_event "mouseout" onMouseOut events in
    let events = push_event "pointerdown" onPointerDown events in
    let events = push_event "pointerup" onPointerUp events in
    let events = push_event "pointermove" onPointerMove events in
    let events = push_event "pointerenter" onPointerEnter events in
    let events = push_event "pointerleave" onPointerLeave events in
    let events = push_event "pointerover" onPointerOver events in
    let events = push_event "pointerout" onPointerOut events in
    let events = push_event "pointercancel" onPointerCancel events in
    let events = push_event "touchstart" onTouchStart events in
    let events = push_event "touchmove" onTouchMove events in
    let events = push_event "touchend" onTouchEnd events in
    let events = push_event "touchcancel" onTouchCancel events in
    let events = push_event "wheel" onWheel events in
    let events = push_event "scroll" onScroll events in
    let events = push_event "dragstart" onDragStart events in
    let events = push_event "drag" onDrag events in
    let events = push_event "dragend" onDragEnd events in
    let events = push_event "dragenter" onDragEnter events in
    let events = push_event "dragover" onDragOver events in
    let events = push_event "dragleave" onDragLeave events in
    let events = push_event "drop" onDrop events in
    let events = push_event "copy" onCopy events in
    let events = push_event "cut" onCut events in
    let events = push_event "paste" onPaste events in
    let events = push_event "load" onLoad events in
    let events = push_event "error" onError events in
    let events = push_event "toggle" onToggle events in
    let events = push_event "close" onClose events in
    let events = push_event "animationstart" onAnimationStart events in
    let events = push_event "animationend" onAnimationEnd events in
    let events = push_event "transitionend" onTransitionEnd events in
    let events = push_event "play" onPlay events in
    let events = push_event "pause" onPause events in
    let events = push_event "ended" onEnded events in
    let events = push_event "timeupdate" onTimeUpdate events in
    let acc = match ref with Some r -> Attr_ref r :: acc | None -> acc in
    element ~attrs:(List.rev_append acc attrs) ~events:(List.rev events) tag children

  let a = create "a"
  let abbr = create "abbr"
  let address = create "address"
  let article = create "article"
  let aside = create "aside"
  let audio = create "audio"
  let blockquote = create "blockquote"
  let br = create "br"
  let button = create "button"
  let canvas = create "canvas"
  let caption = create "caption"
  let code = create "code"
  let col = create "col"
  let colgroup = create "colgroup"
  let dd = create "dd"
  let del = create "del"
  let details = create "details"
  let dfn = create "dfn"
  let dialog = create "dialog"
  let div = create "div"
  let dl = create "dl"
  let dt = create "dt"
  let em = create "em"
  let fieldset = create "fieldset"
  let figcaption = create "figcaption"
  let figure = create "figure"
  let footer = create "footer"
  let form = create "form"
  let h1 = create "h1"
  let h2 = create "h2"
  let h3 = create "h3"
  let h4 = create "h4"
  let h5 = create "h5"
  let h6 = create "h6"
  let header = create "header"
  let hr = create "hr"
  let iframe = create "iframe"
  let img = create "img"
  let input = create "input"
  let ins = create "ins"
  let kbd = create "kbd"
  let label = create "label"
  let legend = create "legend"
  let li = create "li"
  let main = create "main"
  let mark = create "mark"
  let menu = create "menu"
  let meter = create "meter"
  let nav = create "nav"
  let ol = create "ol"
  let optgroup = create "optgroup"
  let option = create "option"
  let output = create "output"
  let p = create "p"
  let picture = create "picture"
  let pre = create "pre"
  let progress = create "progress"
  let samp = create "samp"
  let section = create "section"
  let select = create "select"
  let small = create "small"
  let source = create "source"
  let span = create "span"
  let strong = create "strong"
  let sub = create "sub"
  let summary = create "summary"
  let sup = create "sup"
  let table = create "table"
  let tbody = create "tbody"
  let td = create "td"
  let textarea = create "textarea"
  let tfoot = create "tfoot"
  let th = create "th"
  let thead = create "thead"
  let time = create "time"
  let tr = create "tr"
  let ul = create "ul"
  let video = create "video"
  let wbr = create "wbr"
  let svg = create "svg"
  let g = create "g"
  let path = create "path"
  let circle = create "circle"
  let rect = create "rect"
  let line = create "line"
  let polyline = create "polyline"
  let polygon = create "polygon"
  let ellipse = create "ellipse"
  let defs = create "defs"
  let symbol = create "symbol"
  let use = create "use"
  let stop = create "stop"
  (* END GENERATED MLX PROPS *)
end

(* ----- mounting ----- *)

(* Render [view] into [container] under a fresh root owner. Returns a function
   that disposes everything the view created and removes its nodes. *)
let mount_disposable container view =
  let root = Owner.make ~parent:None () in
  let nodes = ref [] in
  insertion (fun () -> Owner.run_in root (fun () -> insert container None view nodes));
  fun () ->
    Owner.dispose root;
    List.iter (fun node -> Dom.remove_child container node) !nodes;
    nodes := []

(* Render [view] into [container]; it lives as long as the page. *)
let mount container view =
  let (_dispose : unit -> unit) = mount_disposable container view in
  ()

(* Mount into the element with the given [id]; a no-op if it isn't found. *)
let mount_by_id id view =
  match Dom.by_id id with Some container -> mount container view | None -> ()

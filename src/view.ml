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

type attr =
  | Attr_static of string * string
  | Attr_reactive of string * (unit -> string)
  | Attr_bool_static of string * bool
  | Attr_bool_reactive of string * (unit -> bool)
  (* Toggle an attribute's presence (e.g. [disabled]) from a boolean signal. *)
  | Attr_toggle of string * (unit -> bool)
  (* Set while [Some], removed while [None]. *)
  | Attr_optional of string * (unit -> string option)

type handler = string * (Dom.event -> unit)

type 'a value =
  | Static of 'a
  | Reactive of (unit -> 'a)

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

type 'item keyed_block = {
  key : string;
  item : 'item Signal.t;
  nodes : Dom.t list;
  (* Owns the row's effects; disposed when the row is dropped. *)
  owner : Owner.t;
}

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

let apply_attr el = function
  | Attr_static ("value", v) -> Dom.set_value el v
  | Attr_static (name, v) -> Dom.set_attribute el name v
  | Attr_reactive (name, f) ->
    if name = "value" then
      ignore (Effect.leaf (fun () -> Dom.set_value el (f ()); None))
    else ignore (Effect.leaf (fun () -> Dom.set_attribute el name (f ()); None))
  | Attr_bool_static ("checked", v) -> Dom.set_checked el v
  | Attr_bool_static (name, v) ->
    if v then Dom.set_attribute el name "" else Dom.remove_attribute el name
  | Attr_bool_reactive ("checked", f) ->
    ignore (Effect.leaf (fun () -> Dom.set_checked el (f ()); None))
  | Attr_optional (name, f) ->
    ignore
      (Effect.leaf (fun () ->
         (match f () with
          | Some v -> if name = "value" then Dom.set_value el v else Dom.set_attribute el name v
          | None -> Dom.remove_attribute el name);
         None))
  | Attr_bool_reactive (name, f) | Attr_toggle (name, f) ->
    ignore
      (Effect.leaf (fun () ->
         if f () then Dom.set_attribute el name "" else Dom.remove_attribute el name;
         None))

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

(* [build_row] needs [insert], which is defined below it in the same
   recursive group as the reconcilers; this ref breaks the cycle. *)
let insert_ref : (Dom.t -> Dom.t option -> t -> Dom.t list ref -> unit) ref =
  ref (fun _ _ _ _ -> ())

let dispose_keyed_block parent block =
  Owner.dispose block.owner;
  List.iter (fun node -> Dom.remove_child parent node) block.nodes

(* Build one keyed row under a fresh owner. The owner's parent is the current
   one (the list's reconciling effect), for context lookups; it is not
   registered there — the list disposes its rows itself. Rows render
   untracked, so a read in a row's render function never subscribes the whole
   list. *)
let build_row parent before view_of key item_signal =
  let owner = Owner.make () in
  let local_nodes = ref [] in
  Owner.run_in owner (fun () ->
    Signal.untrack (fun () -> insert_ref.contents parent before (view_of ()) local_nodes));
  { key; item = item_signal; nodes = List.rev !local_nodes; owner }

let node_is_followed_by node next =
  match Dom.next_sibling node with
  | Some sibling -> Dom.is_same_node sibling next
  | None -> false

let rec nodes_are_contiguous_before nodes before =
  match nodes with
  | [] -> true
  | [ node ] -> node_is_followed_by node before
  | node :: (next :: _ as rest) ->
    node_is_followed_by node next && nodes_are_contiguous_before rest before

let move_block_before parent block before =
  match block.nodes with
  | [] -> before
  | first :: _ ->
    if not (nodes_are_contiguous_before block.nodes before) then
      List.iter (fun node -> place parent (Some before) node) block.nodes;
    first

let rec reconcile_keyed :
  type item.
  Dom.t ->
  Dom.t ->
  item list ->
  (item -> string) ->
  (item Signal.t -> t) ->
  item keyed_block list ref ->
  unit =
 fun parent anchor items key render blocks ->
  let old_by_key = Hashtbl.create (List.length !blocks) in
  List.iter (fun block -> Hashtbl.replace old_by_key block.key block) !blocks;
  let seen_keys = Hashtbl.create (List.length items) in
  let create_block item item_key =
    let item_signal = Signal.make item in
    build_row parent (Some anchor) (fun () -> render item_signal) item_key item_signal
  in
  let keyed_items =
    map_list
      (fun item ->
        let item_key = key item in
        if Hashtbl.mem seen_keys item_key then
          failwith ("View.for_with_key: duplicate key " ^ item_key);
        Hashtbl.add seen_keys item_key ();
        (item_key, item))
      items
  in
  let next_blocks =
    map_list
      (fun (item_key, item) ->
        match Hashtbl.find_opt old_by_key item_key with
        | Some block ->
          Hashtbl.remove old_by_key item_key;
          Signal.set block.item item;
          block
        | None -> create_block item item_key)
      keyed_items
  in
  Hashtbl.iter (fun _ block -> dispose_keyed_block parent block) old_by_key;
  ignore (List.fold_left (fun before block -> move_block_before parent block before) anchor (List.rev next_blocks));
  blocks := next_blocks;

and reconcile_keyed_raw :
  type item.
  Dom.t ->
  Dom.t ->
  item list ->
  (item -> string) ->
  (item -> t) ->
  item keyed_block list ref ->
  unit =
 fun parent anchor items key render blocks ->
  let old_by_key = Hashtbl.create (List.length !blocks) in
  List.iter (fun block -> Hashtbl.replace old_by_key block.key block) !blocks;
  let seen_keys = Hashtbl.create (List.length items) in
  let create_block ?(before = anchor) item item_key =
    build_row parent (Some before) (fun () -> render item) item_key (Signal.make item)
  in
  let keyed_items =
    map_list
      (fun item ->
        let item_key = key item in
        if Hashtbl.mem seen_keys item_key then
          failwith ("View.for_with_key: duplicate key " ^ item_key);
        Hashtbl.add seen_keys item_key ();
        (item_key, item))
      items
  in
  let next_blocks =
    map_list
      (fun (item_key, item) ->
        match Hashtbl.find_opt old_by_key item_key with
        | Some block when item == Signal.peek block.item ->
          Hashtbl.remove old_by_key item_key;
          block
        | Some block ->
          Hashtbl.remove old_by_key item_key;
          let before =
            match block.nodes with
            | first :: _ -> first
            | [] -> anchor
          in
          let next_block = create_block ~before item item_key in
          dispose_keyed_block parent block;
          next_block
        | None -> create_block item item_key)
      keyed_items
  in
  Hashtbl.iter (fun _ block -> dispose_keyed_block parent block) old_by_key;
  ignore (List.fold_left (fun before block -> move_block_before parent block before) anchor (List.rev next_blocks));
  blocks := next_blocks;

(* Build [view] and insert its top-level nodes into [parent] (before [before],
   or appended when [before] is [None]). Top-level nodes are pushed onto [acc]
   so a [Dynamic] region can later remove exactly what it inserted. Effects
   created here register with the current owner. *)
and insert parent before view (acc : Dom.t list ref) =
  match view with
  | Empty -> ()
  | Text s ->
    let node = Dom.create_text_node s in
    place parent before node;
    acc := node :: !acc
  | Reactive_text f ->
    let node = Dom.create_text_node "" in
    ignore (Effect.leaf (fun () -> Dom.set_text_content node (f ()); None));
    place parent before node;
    acc := node :: !acc
  | Element { tag; attrs; events; children } ->
    let svg = !in_svg || tag = "svg" in
    let el = if svg then Dom.create_element_ns svg_namespace tag else Dom.create_element tag in
    List.iter (apply_attr el) attrs;
    List.iter (fun (name, h) -> Dom.add_event_listener el name h) events;
    (* Children are inserted directly into [el]; their own top-level nodes are
       irrelevant to our caller, so they go into a throwaway accumulator. *)
    let child_acc = ref [] in
    with_svg (svg && tag <> "foreignObject") (fun () ->
      List.iter (fun c -> insert el None c child_acc) children);
    place parent before el;
    acc := el :: !acc
  | Fragment views -> List.iter (fun v -> insert parent before v acc) views
  | Dynamic f ->
    (* The anchor stays put; the region's nodes live just before it and are
       swapped out wholesale whenever a dependency of [f] changes. The effect
       owns each pass: before a re-run it disposes everything the previous
       pass created, then the cleanup below removes the previous nodes. *)
    let anchor = Dom.create_comment "" in
    place parent before anchor;
    acc := anchor :: !acc;
    let region : Dom.t list ref = ref [] in
    let cleanup () =
      List.iter (fun node -> Dom.remove_child parent node) !region;
      region := []
    in
    let svg = !in_svg in
    Effect.run (fun () ->
      let local = ref [] in
      with_svg svg (fun () -> insert parent (Some anchor) (f ()) local);
      region := !local;
      Some cleanup)
  | Component body ->
    (* Runs now, at insertion: under its own owner (disposed with the current
       one) and untracked, so reads in the body never subscribe the region
       that inserted it. *)
    let owner = Owner.make_child () in
    Owner.run_in owner (fun () -> insert parent before (Signal.untrack body) acc)
  | Keyed { items; key; render } ->
    let anchor = Dom.create_comment "" in
    place parent before anchor;
    acc := anchor :: !acc;
    let blocks = ref [] in
    Owner.on_cleanup (fun () ->
      List.iter (dispose_keyed_block parent) !blocks;
      blocks := []);
    let svg = !in_svg in
    Effect.run (fun () ->
      with_svg svg (fun () -> reconcile_keyed parent anchor (items ()) key render blocks);
      None)
  | Keyed_raw { items; key; render } ->
    let anchor = Dom.create_comment "" in
    place parent before anchor;
    acc := anchor :: !acc;
    let blocks = ref [] in
    Owner.on_cleanup (fun () ->
      List.iter (dispose_keyed_block parent) !blocks;
      blocks := []);
    let svg = !in_svg in
    Effect.run (fun () ->
      with_svg svg (fun () -> reconcile_keyed_raw parent anchor (items ()) key render blocks);
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

  (* [className] wins over [class_] when both are given. *)
  let create tag ?class_ ?className
      ?id ?title ?lang ?dir ?role ?style ?tabIndex ?hidden ?draggable ?contentEditable ?spellcheck ?translate ?slot ?aria_label ?aria_labelledby ?aria_describedby ?aria_hidden ?aria_expanded ?aria_controls ?aria_current ?aria_pressed ?aria_selected ?aria_checked ?aria_disabled ?aria_live ?aria_haspopup ?aria_invalid ?href ?target ?rel ?download ?hreflang ?src ?srcSet ?sizes ?alt ?width ?height ?loading ?decoding ?crossOrigin ?poster ?preload ?controls ?autoplay ?loop ?muted ?playsInline ?name ?type_ ?value ?placeholder ?for_ ?htmlFor ?form ?action ?method_ ?enctype ?accept ?acceptCharset ?autocomplete ?pattern ?min ?max ?step ?minLength ?maxLength ?size ?rows ?cols ?wrap ?list ?inputMode ?enterKeyHint ?label_ ?disabled ?required ?readOnly ?multiple ?autofocus ?noValidate ?checked ?selected ?colSpan ?rowSpan ?headers ?scope ?start ?reversed ?open_ ?dateTime ?cite ?viewBox ?xmlns ?d ?fill ?fill_rule ?fill_opacity ?stroke ?stroke_width ?stroke_linecap ?stroke_linejoin ?stroke_dasharray ?stroke_dashoffset ?opacity ?transform ?cx ?cy ?r ?rx ?ry ?x ?y ?x1 ?y1 ?x2 ?y2 ?points ?offset ?stop_color ?preserveAspectRatio
      ?onClick ?onDblClick ?onContextMenu ?onInput ?onChange ?onSubmit ?onReset ?onInvalid ?onKeyDown ?onKeyUp ?onFocus ?onBlur ?onFocusIn ?onFocusOut ?onMouseDown ?onMouseUp ?onMouseEnter ?onMouseLeave ?onMouseMove ?onMouseOver ?onMouseOut ?onPointerDown ?onPointerUp ?onPointerMove ?onPointerEnter ?onPointerLeave ?onPointerOver ?onPointerOut ?onPointerCancel ?onTouchStart ?onTouchMove ?onTouchEnd ?onTouchCancel ?onWheel ?onScroll ?onDragStart ?onDrag ?onDragEnd ?onDragEnter ?onDragOver ?onDragLeave ?onDrop ?onCopy ?onCut ?onPaste ?onLoad ?onError ?onToggle ?onClose ?onAnimationStart ?onAnimationEnd ?onTransitionEnd ?onPlay ?onPause ?onEnded ?onTimeUpdate
      ?(attrs = []) ?(children = []) () =
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
  Owner.run_in root (fun () -> insert container None view nodes);
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

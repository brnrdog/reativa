(* A small, fine-grained reactive UI layer on top of {!Reativa} signals.

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

open Reativa

type attr =
  | Attr_static of string * string
  | Attr_reactive of string * (unit -> string)
  (* Toggle an attribute's presence (e.g. [disabled]) from a boolean signal. *)
  | Attr_toggle of string * (unit -> bool)

type handler = string * (Dom.event -> unit)

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

(* A [register] sink collects the disposers of every Effect created while
   building a subtree, so the nearest enclosing [Dynamic] can dispose them all
   before it re-renders. At the top level (see {!mount}) it simply drops them —
   those Effects live for the lifetime of the page. *)
type register = (unit -> unit) -> unit

let place parent before node =
  match before with
  | Some ref_node -> Dom.insert_before parent node ref_node
  | None -> Dom.append_child parent node

let apply_attr ~(register : register) el = function
  | Attr_static (name, v) -> Dom.set_attribute el name v
  | Attr_reactive (name, f) ->
    let d =
      Effect.run_with_disposer (fun () ->
        Dom.set_attribute el name (f ());
        None)
    in
    register d.dispose
  | Attr_toggle (name, f) ->
    let d =
      Effect.run_with_disposer (fun () ->
        if f () then Dom.set_attribute el name "" else Dom.remove_attribute el name;
        None)
    in
    register d.dispose

(* Build [view] and insert its top-level nodes into [parent] (before [before],
   or appended when [before] is [None]). Top-level nodes are pushed onto [acc]
   so a [Dynamic] region can later remove exactly what it inserted. *)
let rec insert ~(register : register) parent before view (acc : Dom.t list ref) =
  match view with
  | Empty -> ()
  | Text s ->
    let node = Dom.create_text_node s in
    place parent before node;
    acc := node :: !acc
  | Reactive_text f ->
    let node = Dom.create_text_node "" in
    let d =
      Effect.run_with_disposer (fun () ->
        Dom.set_text_content node (f ());
        None)
    in
    register d.dispose;
    place parent before node;
    acc := node :: !acc
  | Element { tag; attrs; events; children } ->
    let el = Dom.create_element tag in
    List.iter (apply_attr ~register el) attrs;
    List.iter (fun (name, h) -> Dom.add_event_listener el name h) events;
    (* Children are inserted directly into [el]; their own top-level nodes are
       irrelevant to our caller, so they go into a throwaway accumulator. *)
    let child_acc = ref [] in
    List.iter (fun c -> insert ~register el None c child_acc) children;
    place parent before el;
    acc := el :: !acc
  | Fragment views -> List.iter (fun v -> insert ~register parent before v acc) views
  | Dynamic f ->
    (* The anchor stays put; the region's nodes live just before it and are
       swapped out wholesale whenever a dependency of [f] changes. *)
    let anchor = Dom.create_comment "" in
    place parent before anchor;
    acc := anchor :: !acc;
    let region : Dom.t list ref = ref [] in
    let child_disposers : (unit -> unit) list ref = ref [] in
    let cleanup () =
      List.iter (fun dispose -> dispose ()) !child_disposers;
      child_disposers := [];
      List.iter (fun node -> Dom.remove_child parent node) !region;
      region := []
    in
    let child_register dispose = child_disposers := dispose :: !child_disposers in
    let d =
      Effect.run_with_disposer (fun () ->
        let local = ref [] in
        insert ~register:child_register parent (Some anchor) (f ()) local;
        region := !local;
        (* Returned as the Effect's cleanup: runs before each re-render and on
           dispose, tearing down the previous render's nodes and Effects. *)
        Some cleanup)
    in
    register d.dispose

(* ----- public constructors ----- *)

let empty = Empty
let text s = Text s
let int n = Text (string_of_int n)
let float f = Text (string_of_float f)
let dyn_text f = Reactive_text f
let dyn_int f = Reactive_text (fun () -> string_of_int (f ()))
let dyn_float f = Reactive_text (fun () -> string_of_float (f ()))
let fragment views = Fragment views

let element ?(attrs = []) ?(events = []) tag children =
  Element { tag; attrs; events; children }

(* A reactive region: [f] is re-run (and its subtree rebuilt) whenever a signal
   it reads changes. The building block behind {!show}, {!maybe} and {!for_}. *)
let dyn f = Dynamic f

(* ----- control flow (xote-style components, as plain functions) ----- *)

(* Render [child] while [cond ()] holds, otherwise [fallback]. *)
let show ?(fallback = Empty) cond child =
  Dynamic (fun () -> if cond () then child else fallback)

(* Render from the [Some] case of an option signal, otherwise [fallback]. *)
let maybe ?(fallback = Empty) get f =
  Dynamic (fun () -> match get () with Some x -> f x | None -> fallback)

(* Map a (reactive) list to a view. The whole list re-renders when [items]
   changes — keyed reconciliation is a future refinement. *)
let for_ items f = Dynamic (fun () -> Fragment (List.map f (items ())))

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
  let make name v = Attr_static (name, v)
  let reactive name f = Attr_reactive (name, f)
  let toggle name f = Attr_toggle (name, f)
  let class_ v = Attr_static ("class", v)
  let class_reactive f = Attr_reactive ("class", f)
  let id v = Attr_static ("id", v)
  let type_ v = Attr_static ("type", v)
  let value v = Attr_static ("value", v)
  let value_reactive f = Attr_reactive ("value", f)
  let placeholder v = Attr_static ("placeholder", v)
  let href v = Attr_static ("href", v)
  let disabled f = Attr_toggle ("disabled", f)
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

(* ----- mounting ----- *)

(* Render [view] into [container]. Top-level Effects are intentionally not
   tracked for disposal: a mounted app lives as long as the page. *)
let mount container view =
  insert ~register:(fun _ -> ()) container None view (ref [])

(* Mount into the element with the given [id]; a no-op if it isn't found. *)
let mount_by_id id view =
  match Dom.by_id id with Some container -> mount container view | None -> ()

(** Views: descriptions of DOM nodes, mounted once and updated in place. *)

(** A piece of UI. Build it with the functions below and {!mount} it. *)
type t

type attr
type handler = string * (Dom.event -> unit)

(** A value that is either fixed or read from signals. *)
type 'a value =
  | Static of 'a
  | Reactive of (unit -> 'a)

val static : 'a -> 'a value
val dynamic : (unit -> 'a) -> 'a value
val signal : 'a Signal.t -> 'a value
val map_value : ('a -> 'b) -> 'a value -> 'b value

(** A function reading the current value (tracked when it is reactive). *)
val value_getter : 'a value -> unit -> 'a

(** An element reference, for imperative access to a DOM node (focus,
    measurement, a third-party widget). Pass it as the [ref] prop of an mlx
    element, or as [Attr.ref_]. *)
module Ref : sig
  type t

  val make : unit -> t

  (** Calls [f] with the element as soon as it is created. *)
  val from_callback : (Dom.t -> unit) -> t

  (** The element, once created and until its owner is disposed. *)
  val current : t -> Dom.t option
end

(** {2 Lifecycle} *)

(** Run [f] once the insertion that is under way — the mount, region pass or
    list pass that is rendering the current component — has finished, so its
    nodes are in place. [f] runs untracked under the current owner, and not
    at all if that owner was disposed first. Outside any insertion it runs
    right away. *)
val on_mount : (unit -> unit) -> unit

(** Run [f] when the current owner (the component, row or region being
    rendered) is disposed. *)
val on_cleanup : (unit -> unit) -> unit

(** {2 Leaves and structure} *)

val empty : t
val text : string value -> t
val int : int value -> t
val float : float value -> t
val dyn_text : (unit -> string) -> t
val dyn_int : (unit -> int) -> t
val dyn_float : (unit -> float) -> t
val fragment : t list -> t
val element : ?attrs:attr list -> ?events:handler list -> string -> t list -> t

(** A component: [body] runs when the view is mounted, under its own owner
    and untracked. The mlx ppx wraps every component tag in this. *)
val component : (unit -> t) -> t

(** A region rebuilt wholesale whenever a signal it read changes. *)
val dyn : (unit -> t) -> t

val tracked : (unit -> t) -> t

(** Runtime coercion of a bare JSX child: a string, int, float, view, or a
    thunk of one of those (which becomes a tracked region). *)
val child : 'a -> t

(** {2 Templates}

    What the mlx ppx compiles element trees to: the static parts of a tree as
    an HTML string, parsed once and cloned for every instance, plus the
    "holes" where values go. Writing them by hand is possible but rarely
    worth it; mlx does it for you. *)

type view = t

module Template : sig
  type t
  type hole

  (** The skeleton, as HTML. Children are counted as the HTML parser builds
      them: write a text hole as a single space and a child hole as an empty
      comment ([<!---->]), and keep static text from touching a text hole. *)
  val make : string -> t

  (** A hole is addressed by child indices from the skeleton's root. *)
  val attr : int list -> attr -> hole

  val event : int list -> string -> (Dom.event -> unit) -> hole

  (** The node at the path is a text node; it shows the value. *)
  val text : int list -> string value -> hole

  (** The node at the path is a comment; the view replaces it. [svg] when the
      comment sits inside an <svg>. *)
  val child : ?svg:bool -> int list -> view -> hole
end

(** An instance of a template with its holes filled. *)
val template : Template.t -> Template.hole list -> t

(** {2 Boundaries, portals and suspense} *)

(** [error_boundary ~fallback child] renders [child]; an exception raised
    while rendering it, or later by an effect below it, replaces it with
    [fallback err reset]. [reset ()] renders [child] again. Errors raised by
    the fallback itself go to the next boundary up. *)
val error_boundary : fallback:(exn -> (unit -> unit) -> t) -> t -> t

module ErrorBoundary : sig
  val component : fallback:(exn -> (unit -> unit) -> t) -> children:t list -> unit -> t
  val createElement : unit -> children:t list -> fallback:(exn -> (unit -> unit) -> t) -> t
end

(** Render [child] into [target] (default: <body>), owned by this point of
    the tree: it is removed with it, and sees its context. *)
val portal : ?target:Dom.t -> t -> t

module Portal : sig
  val component : ?target:Dom.t -> children:t list -> unit -> t
  val createElement : ?target:Dom.t -> unit -> children:t list -> t
end

(** Show [fallback] while any {!Reativa.Resource} created below is loading;
    the child renders meanwhile, out of the document, and moves into place
    when nothing is pending. *)
val suspense : fallback:t -> t -> t

module Suspense : sig
  val component : fallback:t -> children:t list -> unit -> t
  val createElement : unit -> children:t list -> fallback:t -> t
end

(** {2 Control flow} *)

val show : ?fallback:t -> (unit -> bool) -> t -> t
val maybe : ?fallback:t -> (unit -> 'a option) -> ('a -> t) -> t

(** The whole list re-renders when [items] changes. *)
val for_ : (unit -> 'a list) -> ('a -> t) -> t

(** Rows are kept by key: a surviving row keeps its DOM and effects, and
    its signal receives the latest item for that key. *)
val for_with_key : (unit -> 'a list) -> key:('a -> string) -> ('a Signal.t -> t) -> t

val forWithKey : (unit -> 'a list) -> key:('a -> string) -> ('a Signal.t -> t) -> t

module Show : sig
  val component : ?fallback:t -> condition:bool value -> children:t list -> unit -> t
  val createElement : ?fallback:t -> unit -> children:t list -> condition:bool value -> t
end

module Maybe : sig
  val component : ?fallback:t -> value:'a option value -> render:('a -> t) -> unit -> t

  val createElement :
    ?fallback:t -> unit -> children:'b -> value:'a option value -> render:('a -> t) -> t
end

module ForEach : sig
  val component : ?key:('a -> string) -> items:'a list value -> render:('a -> t) -> unit -> t

  val createElement :
    ?key:('a -> string) -> unit -> children:'b -> items:'a list value -> render:('a -> t) -> t
end

(** {2 Element helpers} *)

val tag : string -> ?attrs:attr list -> ?events:handler list -> t list -> t
val div : ?attrs:attr list -> ?events:handler list -> t list -> t
val span : ?attrs:attr list -> ?events:handler list -> t list -> t
val p : ?attrs:attr list -> ?events:handler list -> t list -> t
val h1 : ?attrs:attr list -> ?events:handler list -> t list -> t
val h2 : ?attrs:attr list -> ?events:handler list -> t list -> t
val h3 : ?attrs:attr list -> ?events:handler list -> t list -> t
val ul : ?attrs:attr list -> ?events:handler list -> t list -> t
val ol : ?attrs:attr list -> ?events:handler list -> t list -> t
val li : ?attrs:attr list -> ?events:handler list -> t list -> t
val button : ?attrs:attr list -> ?events:handler list -> t list -> t
val a : ?attrs:attr list -> ?events:handler list -> t list -> t
val input : ?attrs:attr list -> ?events:handler list -> unit -> t
val label : ?attrs:attr list -> ?events:handler list -> t list -> t
val section : ?attrs:attr list -> ?events:handler list -> t list -> t

module Attr : sig
  val make : string -> string value -> attr
  val reactive : string -> (unit -> string) -> attr
  val toggle : string -> (unit -> bool) -> attr
  val class_ : string value -> attr
  val className : string value -> attr
  val class_reactive : (unit -> string) -> attr
  val className_reactive : (unit -> string) -> attr
  val id : string value -> attr
  val type_ : string value -> attr
  val value : string value -> attr
  val value_reactive : (unit -> string) -> attr
  val placeholder : string value -> attr
  val href : string value -> attr
  val disabled : (unit -> bool) -> attr

  (** A DOM property (live state) rather than an attribute. *)
  val bool_property : string -> bool value -> attr

  val checked : bool value -> attr

  (** Present with value [v] while [f ()] is [Some v], removed while [None]. *)
  val optional : string -> (unit -> string option) -> attr

  (** [data "id" v] is the attribute [data-id]. *)
  val data : string -> string value -> attr

  (** Fill a {!Ref.t} with the element. *)
  val ref_ : Ref.t -> attr
end

module On : sig
  val on : string -> (Dom.event -> unit) -> handler
  val click : (Dom.event -> unit) -> handler
  val input : (Dom.event -> unit) -> handler
  val change : (Dom.event -> unit) -> handler
  val keydown : (Dom.event -> unit) -> handler
  val submit : (Dom.event -> unit) -> handler
end

(** The targets of mlx's element lowering. Every element takes the same
    optional props; [attrs] appends further attributes. *)
module Mlx : sig
  val static : 'a -> 'a value
  val dynamic : (unit -> 'a) -> 'a value
  val signal : 'a Signal.t -> 'a value

  (* BEGIN GENERATED MLX SIGNATURE *)
  (* Generated by scripts/generate-mlx-props.mjs; edit its table. *)
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

  val create : string -> element
  val a : element
  val abbr : element
  val address : element
  val article : element
  val aside : element
  val audio : element
  val blockquote : element
  val br : element
  val button : element
  val canvas : element
  val caption : element
  val code : element
  val col : element
  val colgroup : element
  val dd : element
  val del : element
  val details : element
  val dfn : element
  val dialog : element
  val div : element
  val dl : element
  val dt : element
  val em : element
  val fieldset : element
  val figcaption : element
  val figure : element
  val footer : element
  val form : element
  val h1 : element
  val h2 : element
  val h3 : element
  val h4 : element
  val h5 : element
  val h6 : element
  val header : element
  val hr : element
  val iframe : element
  val img : element
  val input : element
  val ins : element
  val kbd : element
  val label : element
  val legend : element
  val li : element
  val main : element
  val mark : element
  val menu : element
  val meter : element
  val nav : element
  val ol : element
  val optgroup : element
  val option : element
  val output : element
  val p : element
  val picture : element
  val pre : element
  val progress : element
  val samp : element
  val section : element
  val select : element
  val small : element
  val source : element
  val span : element
  val strong : element
  val sub : element
  val summary : element
  val sup : element
  val table : element
  val tbody : element
  val td : element
  val textarea : element
  val tfoot : element
  val th : element
  val thead : element
  val time : element
  val tr : element
  val ul : element
  val video : element
  val wbr : element
  val svg : element
  val g : element
  val path : element
  val circle : element
  val rect : element
  val line : element
  val polyline : element
  val polygon : element
  val ellipse : element
  val defs : element
  val symbol : element
  val use : element
  val stop : element
  (* END GENERATED MLX SIGNATURE *)
end

(** {2 Mounting} *)

(** Render into a container for the lifetime of the page. *)
val mount : Dom.t -> t -> unit

(** Render into the element with this id; a no-op when there is none. *)
val mount_by_id : string -> t -> unit

(** Render, and return a function that disposes the view and removes its
    nodes. *)
val mount_disposable : Dom.t -> t -> unit -> unit

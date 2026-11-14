(* Test-only DOM inspection for the jsdom suites.

   [Reativa.Dom] binds only what the renderer needs. Tests also need to read
   the DOM back, fire events and count the operations the renderer performed.
   This module does that, once per backend: test/dom/probe/melange/probe.ml and
   test/dom/probe/jsoo/probe.ml both implement this signature, so the suites in
   test/dom/ compile unchanged against either. *)

type node = Reativa.Dom.t

val body : unit -> node

(* A fresh, empty <div> appended to <body>. *)
val container : unit -> node

val inner_html : node -> string
val text_content : node -> string
val child_count : node -> int
val first_child : node -> node option
val query : node -> string -> node option
val query_all : node -> string -> node list
val attribute : node -> string -> string option
val bool_property : node -> string -> bool
val string_property : node -> string -> string
val is_connected : node -> bool

(* Dispatch a bubbling [click] (a MouseEvent with button 0). *)
val click : node -> unit

(* Dispatch a bubbling event of the given type. *)
val dispatch : node -> string -> unit

(* Set [value] and dispatch a bubbling [input] event. *)
val type_text : node -> string -> unit

(* Number of calls to the given DOM method or setter since the last reset:
   "insertBefore", "appendChild", "removeChild", "cloneNode", "setAttribute",
   "removeAttribute", "createElement", "createElementNS", "createTextNode",
   "textContent", "data". Counted by test/dom/run.mjs. *)
val ops : string -> int

val reset_ops : unit -> unit

val set_timeout : int -> (unit -> unit) -> unit

(* Write a line to the console, the same way on both backends. *)
val print : string -> unit

(* Hand the totals to test/dom/run.mjs, which sets the exit code. *)
val report : failed:int -> total:int -> unit

(* A pending promise and the functions that settle it: [resolve v], or
   [reject message] with a JS Error. *)
val deferred : unit -> 'a Reativa.Promise.t * ('a -> unit) * (string -> unit)

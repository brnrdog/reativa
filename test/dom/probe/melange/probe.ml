(* Melange implementation of Probe (see ../probe.mli). *)

type node = Reativa.Dom.t

external body_ : node = "body" [@@mel.scope "document"]
let body () = body_

external create_element : string -> node = "createElement" [@@mel.scope "document"]
external append_child : node -> node -> unit = "appendChild" [@@mel.send]

let container () =
  let div = create_element "div" in
  append_child (body ()) div;
  div

external inner_html : node -> string = "innerHTML" [@@mel.get]
external text_content : node -> string = "textContent" [@@mel.get]
external child_nodes : node -> node array = "childNodes" [@@mel.get]
external length : node array -> int = "length" [@@mel.get]
let child_count n = length (child_nodes n)

external first_child_ : node -> node option = "firstChild" [@@mel.get] [@@mel.return nullable]
let first_child n = first_child_ n

external query_ : node -> string -> node option = "querySelector" [@@mel.send] [@@mel.return nullable]
let query n selector = query_ n selector

external query_all_ : node -> string -> node array = "querySelectorAll" [@@mel.send]
external array_from : node array -> node array = "from" [@@mel.scope "Array"]
let query_all n selector = Array.to_list (array_from (query_all_ n selector))

external attribute_ : node -> string -> string option = "getAttribute" [@@mel.send] [@@mel.return nullable]
let attribute n name = attribute_ n name

external get_bool : node -> string -> bool = "" [@@mel.get_index]
external get_string : node -> string -> string = "" [@@mel.get_index]
let bool_property n name = get_bool n name
let string_property n name = get_string n name

external is_connected : node -> bool = "isConnected" [@@mel.get]

type event
type event_init = { bubbles : bool; button : int }

external mouse_event : string -> event_init -> event = "MouseEvent" [@@mel.new]
external plain_event : string -> event_init -> event = "Event" [@@mel.new]
external dispatch_event : node -> event -> bool = "dispatchEvent" [@@mel.send]

let click n = ignore (dispatch_event n (mouse_event "click" { bubbles = true; button = 0 }))
let dispatch n kind = ignore (dispatch_event n (plain_event kind { bubbles = true; button = 0 }))

external set_value : node -> string -> unit = "value" [@@mel.set]

let type_text n value =
  set_value n value;
  dispatch n "input"

external ops : string -> int = "__reativaOps"
external reset_ops_ : unit -> unit = "__reativaResetOps"
let reset_ops () = reset_ops_ ()

external set_timeout_ : (unit -> unit) -> int -> unit = "setTimeout"
let set_timeout ms f = set_timeout_ f ms

external print : string -> unit = "log" [@@mel.scope "console"]

external report_ : int -> int -> unit = "__reativaReport"
let report ~failed ~total = report_ failed total

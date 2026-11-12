(* js_of_ocaml implementation of Probe (see ../probe.mli). *)

open Js_of_ocaml

type node = Reativa.Dom.t

(* [Reativa.Dom.t] is abstract; under this backend it is a JS value. *)
let js (n : node) : Js.Unsafe.any = Obj.magic n
let of_js (v : Js.Unsafe.any) : node = Obj.magic v
let global name : Js.Unsafe.any = Js.Unsafe.get Js.Unsafe.global name
let document () = global "document"
let str (s : string) = Js.Unsafe.inject (Js.string s)
let to_str (v : Js.Unsafe.any) : string = Js.to_string (Obj.magic v : Js.js_string Js.t)
let is_null (v : Js.Unsafe.any) = Js.Opt.test (Obj.magic v : Js.Unsafe.any Js.opt) = false

let body () = of_js (Js.Unsafe.get (document ()) "body")

let container () =
  let div = Js.Unsafe.meth_call (document ()) "createElement" [| str "div" |] in
  ignore (Js.Unsafe.meth_call (Js.Unsafe.get (document ()) "body") "appendChild" [| div |]);
  of_js div

let inner_html n = to_str (Js.Unsafe.get (js n) "innerHTML")
let text_content n = to_str (Js.Unsafe.get (js n) "textContent")
let child_count n : int = Js.Unsafe.get (Js.Unsafe.get (js n) "childNodes") "length"

let first_child n =
  let c = Js.Unsafe.get (js n) "firstChild" in
  if is_null c then None else Some (of_js c)

let query n selector =
  let r = Js.Unsafe.meth_call (js n) "querySelector" [| str selector |] in
  if is_null r then None else Some (of_js r)

let query_all n selector =
  let list = Js.Unsafe.meth_call (js n) "querySelectorAll" [| str selector |] in
  let len : int = Js.Unsafe.get list "length" in
  List.init len (fun i -> of_js (Js.Unsafe.meth_call list "item" [| Js.Unsafe.inject i |]))

let attribute n name =
  let r = Js.Unsafe.meth_call (js n) "getAttribute" [| str name |] in
  if is_null r then None else Some (to_str r)

let bool_property n name = Js.to_bool (Js.Unsafe.get (js n) name)
let string_property n name = to_str (Js.Unsafe.get (js n) name)
let is_connected n = Js.to_bool (Js.Unsafe.get (js n) "isConnected")

let make_event ctor kind =
  let init = Js.Unsafe.obj [| ("bubbles", Js.Unsafe.inject Js._true); ("button", Js.Unsafe.inject 0) |] in
  Js.Unsafe.new_obj (global ctor) [| str kind; init |]

let click n = ignore (Js.Unsafe.meth_call (js n) "dispatchEvent" [| make_event "MouseEvent" "click" |])
let dispatch n kind = ignore (Js.Unsafe.meth_call (js n) "dispatchEvent" [| make_event "Event" kind |])

let type_text n value =
  Js.Unsafe.set (js n) "value" (Js.string value);
  dispatch n "input"

let ops name : int = Js.Unsafe.fun_call (global "__reativaOps") [| str name |]
let reset_ops () = ignore (Js.Unsafe.fun_call (global "__reativaResetOps") [||])

let set_timeout ms f =
  ignore
    (Js.Unsafe.fun_call (global "setTimeout")
       [| Js.Unsafe.inject (Js.wrap_callback f); Js.Unsafe.inject ms |])

let print s = ignore (Js.Unsafe.meth_call (global "console") "log" [| str s |])

let report ~failed ~total =
  ignore
    (Js.Unsafe.fun_call (global "__reativaReport")
       [| Js.Unsafe.inject failed; Js.Unsafe.inject total |])

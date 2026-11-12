(* js_of_ocaml implementation of the Promise virtual module: a JS promise. *)

open Js_of_ocaml

type 'a t = Js.Unsafe.any

exception Rejected of string

let promise_ctor () = Js.Unsafe.get Js.Unsafe.global "Promise"
let resolve (v : 'a) : 'a t = Js.Unsafe.meth_call (promise_ctor ()) "resolve" [| Js.Unsafe.inject v |]

(* An OCaml exception is passed as the OCaml value itself. *)
let reject (e : exn) : 'a t = Js.Unsafe.meth_call (promise_ctor ()) "reject" [| Js.Unsafe.inject e |]

let describe (reason : Js.Unsafe.any) : string =
  let error_ctor = Js.Unsafe.get Js.Unsafe.global "Error" in
  if Js.to_bool (Js.Unsafe.fun_call (Js.Unsafe.pure_js_expr "(function (r, E) { return r instanceof E; })")
                   [| reason; error_ctor |])
  then Js.to_string (Js.Unsafe.get reason "message")
  else Js.to_string (Js.Unsafe.fun_call (Js.Unsafe.get Js.Unsafe.global "String") [| reason |])

let on_settled (p : 'a t) ~ok ~error =
  let on_ok = Js.wrap_callback (fun v -> ok (Obj.magic v)) in
  let on_error =
    Js.wrap_callback (fun (reason : Js.Unsafe.any) ->
      (* OCaml exceptions are blocks, which js_of_ocaml represents as arrays
         whose first element is the block tag; an exception's tag is 248. *)
      let is_exn =
        Js.to_bool (Js.Unsafe.fun_call (Js.Unsafe.get (Js.Unsafe.get Js.Unsafe.global "Array") "isArray") [| reason |])
        && (Js.Unsafe.get reason 0 : int) = 248
        || (Js.to_bool (Js.Unsafe.fun_call (Js.Unsafe.get (Js.Unsafe.get Js.Unsafe.global "Array") "isArray") [| reason |])
           && (Js.Unsafe.get reason 0 : int) = 0
           && Js.to_bool (Js.Unsafe.fun_call (Js.Unsafe.get (Js.Unsafe.get Js.Unsafe.global "Array") "isArray")
                            [| Js.Unsafe.get reason 1 |])
           && (Js.Unsafe.get (Js.Unsafe.get reason 1) 0 : int) = 248)
      in
      error (if is_exn then (Obj.magic reason : exn) else Rejected (describe reason)))
  in
  ignore (Js.Unsafe.meth_call p "then" [| Js.Unsafe.inject on_ok; Js.Unsafe.inject on_error |])

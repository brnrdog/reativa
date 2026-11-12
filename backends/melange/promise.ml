(* Melange implementation of the Promise virtual module: a JS promise. *)

type 'a t
type reason

exception Rejected of string

external resolve : 'a -> 'a t = "resolve" [@@mel.scope "Promise"]
external reject_reason : reason -> 'a t = "reject" [@@mel.scope "Promise"]
external then_ : 'a t -> ('a -> unit) -> (reason -> unit) -> unit = "then" [@@mel.send]

(* An OCaml exception travels through the promise as itself; anything else a
   JS rejection carries becomes [Rejected message]. *)
external is_ocaml_exn : reason -> bool = "isOcamlExn" [@@mel.module "./reativa_runtime.js"]
external describe : reason -> string = "describeReason" [@@mel.module "./reativa_runtime.js"]

let reject (e : exn) : 'a t = reject_reason (Obj.magic e)

let on_settled p ~ok ~error =
  then_ p ok (fun reason ->
    error (if is_ocaml_exn reason then (Obj.magic reason : exn) else Rejected (describe reason)))

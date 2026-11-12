(* The backend's JavaScript promises (a dune virtual module, like Dom and
   History): Melange's and js_of_ocaml's own representation, so
   {!Reativa.Resource} takes the promises a backend's APIs already return. *)

type 'a t

(* A JavaScript rejection reason that is not an OCaml exception, as its
   message (an Error's [message], or [String(reason)]). *)
exception Rejected of string

val resolve : 'a -> 'a t
val reject : exn -> 'a t

(* [on_settled p ~ok ~error]: call [ok] with the value, or [error] with the
   reason, once [p] settles (always asynchronously). *)
val on_settled : 'a t -> ok:('a -> unit) -> error:(exn -> unit) -> unit

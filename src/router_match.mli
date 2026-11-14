(** Path matching, independent of the browser. *)

type t = {
  pattern : string;
  pathname : string;
  params : (string * string) list;
}

(** [match_path ?decode pattern pathname]: [":name"] segments capture, a
    trailing ["*"] matches the rest. *)
val match_path : ?decode:(string -> string) -> string -> string -> t option

val param : t -> string -> string option

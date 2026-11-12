(** Client-side routing over the History API. *)

type state

type location = {
  href : string;
  origin : string;
  pathname : string;
  search : string;
  hash : string;
  state : state option;
}

(** Wrap any value as history state, and read it back. Reading it back at a
    different type than it was stored with is undefined. *)
val state : 'a -> state

val state_value : state -> 'a

(** The current location, as a signal kept in sync with the browser. *)
val location : unit -> location Signal.t

val start : unit -> unit
val current_signal : unit -> location Signal.t

(** pathname, search and hash. *)
val path : location -> string

val navigate : ?replace:bool -> ?state:state -> string -> unit -> unit
val replace : ?state:state -> string -> unit -> unit
val push : ?state:state -> string -> unit -> unit
val go : int -> unit
val back : unit -> unit
val forward : unit -> unit

(** An <a> that navigates in-app on a plain left click and leaves
    modified clicks, other targets and external links to the browser. *)
val link_value :
  ?replace:bool ->
  ?state:state ->
  ?target:string ->
  ?attrs:View.attr list ->
  ?events:View.handler list ->
  href:string View.value ->
  View.t list ->
  View.t

val link :
  ?replace:bool ->
  ?state:state ->
  ?target:string ->
  ?attrs:View.attr list ->
  ?events:View.handler list ->
  href:string ->
  View.t list ->
  View.t

type route_match = Router_match.t = {
  pattern : string;
  pathname : string;
  params : (string * string) list;
}

type route

val route : string -> (route_match -> View.t) -> route
val match_path : string -> string -> Router_match.t option
val param : Router_match.t -> string -> string option

(** Render the first route matching the current location. *)
val outlet : ?fallback:(location -> View.t) -> route list -> View.t

val is_active : ?exact:bool -> string -> bool
val redirect_value : ?replace:bool -> ?state:state -> string View.value -> View.t
val redirect : ?replace:bool -> ?state:state -> string -> View.t
val component : ?fallback:(location -> View.t) -> children:route list -> unit -> View.t
val createElement : ?fallback:(location -> View.t) -> unit -> children:route list -> View.t

module Route : sig
  val component :
    ?render:(route_match -> View.t) -> path:string -> children:View.t list -> unit -> route

  val createElement :
    ?render:(route_match -> View.t) -> unit -> children:View.t list -> path:string -> route
end

module Link : sig
  val component :
    ?replace:bool ->
    ?state:state ->
    ?target:string ->
    href:string View.value ->
    children:View.t list ->
    unit ->
    View.t

  val createElement :
    ?replace:bool ->
    ?state:state ->
    ?target:string ->
    unit ->
    children:View.t list ->
    href:string View.value ->
    View.t
end

module Redirect : sig
  val component : ?replace:bool -> ?state:state -> to_:string View.value -> unit -> View.t

  val createElement :
    ?replace:bool -> ?state:state -> unit -> children:'a -> to_:string View.value -> View.t
end

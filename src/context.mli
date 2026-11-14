(** Values scoped to a subtree.

    A context is a key with a default. A component provides a value for
    everything it renders, and anything below reads the nearest one:

    {[
      let theme = Context.make "light"

      module Badge = struct
        let component ~label =
          <span className=(Context.use theme)>(label)</span>
      end

      let app = Context.provider theme "dark" <Badge label="New" />
    ]}

    Lookups follow ownership, not the DOM: a portal's content sees the
    providers around the portal, and an effect sees the providers around the
    component that created it. To share state that changes, provide a signal:
    [Context.make (Signal.make 0)]. *)

type 'a t

(** A context whose lookups return [default] where nothing provides it. *)
val make : 'a -> 'a t

(** The value provided by the nearest enclosing provider, or the default.
    Call it while a component renders (or in an effect it creates). *)
val use : 'a t -> 'a

(** Provide a value to everything the current component renders.
    Raises [Invalid_argument] outside a component. *)
val provide : 'a t -> 'a -> unit

(** [provider context value child] renders [child] with [value] provided. *)
val provider : 'a t -> 'a -> View.t -> View.t

(** [<Context.Provider context value> ... </Context.Provider>]. The value is
    read once, when the provider renders. *)
module Provider : sig
  val component : context:'a t -> value:'a View.value -> children:View.t list -> unit -> View.t
  val createElement : unit -> children:View.t list -> context:'a t -> value:'a View.value -> View.t
end

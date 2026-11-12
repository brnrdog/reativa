(* Values scoped to a subtree, carried by the owner tree (see context.mli). *)

type 'a t = 'a Owner.key

let make default = Owner.new_key default
let use context = Owner.lookup context

let provide context value =
  match Owner.active () with
  | Some owner -> Owner.provide owner context value
  | None -> invalid_arg "Context.provide: no current owner (call it while a component renders)"

let provider context value child =
  View.component (fun () ->
    provide context value;
    child)

module Provider = struct
  let component ~context ~value ~children () =
    View.component (fun () ->
      provide context (Signal.untrack (View.value_getter value));
      View.fragment children)

  let createElement () ~children ~context ~value = component ~context ~value ~children ()
end

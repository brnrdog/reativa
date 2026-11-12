(* The link between View.Suspense and Resource (internal).

   A Suspense boundary provides a counter of pending work on its owner; a
   resource created anywhere below it finds the counter through the owner
   tree, increments it while a fetch is in flight and decrements it when the
   fetch settles. The boundary shows its fallback while the counter is above
   zero. *)

let key : int Signal.t option Owner.key = Owner.new_key None

(* The counter of the nearest enclosing Suspense, if any. *)
let current () = Owner.lookup key

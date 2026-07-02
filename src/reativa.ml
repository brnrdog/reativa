(* Public entrypoint for Reativa.

   The browser-facing [View] layer builds on the reactive primitives to mount
   real DOM nodes and update reactive regions in place.

   {[
     let count = Signal.make 0 in
     let doubled = Computed.make (fun () -> Signal.get count * 2) in
     Effect.run (fun () ->
       Printf.printf "doubled = %d\n" (Signal.get doubled);
       None);
     Signal.set count 5  (* prints "doubled = 10" *)
   ]} *)

module Signal = Signal
module Computed = Computed
module Effect = Effect
module Dom = Dom
module View = View
module Router_match = Router_match
module Router = Router
module Route = Router.Route
module Link = Router.Link
module Redirect = Router.Redirect

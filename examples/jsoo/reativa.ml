(* Public-API aggregator for the js_of_ocaml build of the demo.

   The real library's [src/reativa.ml] re-exports the same modules (plus the
   router). We reproduce a trimmed version here so the *unmodified* demo source
   ([demo/ui/todo.mlx], which does [open Reativa]) compiles against this backend
   with no changes. The Signal/Computed/Effect/View modules are the very same
   source files as the Melange build (pulled in verbatim by [copy_files] — see
   dune); only [Dom] is the js_of_ocaml implementation. *)

module Signal = Signal
module Computed = Computed
module Effect = Effect
module Dom = Dom
module View = View

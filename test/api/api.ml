(* Expands every public module so `ocamlc -i` prints the whole public
   signature. scripts/check-api.sh compares that print with reativa.api; a
   change to the public API shows up there as a diff to review and commit. *)

module Signal = struct include Reativa.Signal end
module Computed = struct include Reativa.Computed end
module Effect = struct include Reativa.Effect end
module Owner = struct include Reativa.Owner end
module Dom = struct include Reativa.Dom end
module View = struct include Reativa.View end
module Router_match = struct include Reativa.Router_match end
module Router = struct include Reativa.Router end
module Context = struct include Reativa.Context end
module Resource = struct include Reativa.Resource end
module Promise = struct include Reativa.Promise end

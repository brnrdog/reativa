(* Ownership: who disposes what.

   An owner collects the cleanups of everything created while it is current —
   effects, computeds, nested owners, [on_cleanup] callbacks — and runs them
   all when it is disposed. Owners form a tree through [parent], which is also
   the path that context lookups and error handlers walk.

   Who gets an owner:
   - every effect: it is current while the effect's body runs, and is reset
     (its cleanups run) before each re-run, so whatever one run created is
     gone before the next one starts;
   - every component (see [View.component]) and every keyed row;
   - the root of each [View.mount].

   An owner does not register itself with its parent. The parent pointer is
   only for lookups; whoever creates an owner decides who disposes it. That
   keeps short-lived children (a keyed row that is removed, a component in a
   region that re-renders) from leaving a closure behind in a long-lived
   parent. [make_child] is the attached variant, for the common case of an
   owner that should die with the current one. *)

type t = {
  parent : t option;
  mutable cleanups : (unit -> unit) list;
  (* Context values provided on this owner, keyed by context id. *)
  mutable contexts : (int * Obj.t) list;
  mutable error_handler : (exn -> unit) option;
  mutable disposed : bool;
}

let current : t option ref = ref None

let make ?(parent = !current) () =
  { parent; cleanups = []; contexts = []; error_handler = None; disposed = false }

let add_cleanup owner f =
  if owner.disposed then f () else owner.cleanups <- f :: owner.cleanups

(* Register [f] with the current owner. Outside any owner (module
   initialisation, a test), there is nothing to tie it to and it is dropped:
   what is created there lives as long as the program. *)
let on_cleanup f = match !current with Some owner -> add_cleanup owner f | None -> ()

(* Run the cleanups registered so far, most recent first, and keep the owner
   usable. A cleanup that raises does not stop the others; the first
   exception is re-raised once they have all run. *)
let reset owner =
  match owner.cleanups with
  | [] -> ()
  | cleanups ->
    owner.cleanups <- [];
    let failure = ref None in
    List.iter
      (fun f -> try f () with e -> if !failure = None then failure := Some e)
      cleanups;
    (match !failure with Some e -> raise e | None -> ())

let dispose owner =
  if not owner.disposed then begin
    owner.disposed <- true;
    reset owner
  end

let is_disposed owner = owner.disposed

let make_child () =
  let owner = make () in
  on_cleanup (fun () -> dispose owner);
  owner

(* Run [f] with [owner] current, restoring the previous owner afterwards (also
   when [f] raises). *)
let run owner f =
  let prev = !current in
  current := owner;
  match f () with
  | result ->
    current := prev;
    result
  | exception e ->
    current := prev;
    raise e

let run_in owner f = run (Some owner) f

(* ----- context ----- *)

type 'a key = { id : int; default : 'a }

let next_key = ref 0

let new_key default =
  incr next_key;
  { id = !next_key; default }

let provide owner key (value : 'a) =
  owner.contexts <- (key.id, Obj.repr value) :: List.remove_assoc key.id owner.contexts

(* The value provided by the nearest owner, starting at [from] and walking up;
   the key's default when none provides it. The [Obj] round trip is safe: a
   value is only ever stored under the id of a key of its own type. *)
let lookup ?(from = !current) (key : 'a key) : 'a =
  let rec walk = function
    | None -> key.default
    | Some owner -> (
      match List.assq_opt key.id owner.contexts with
      | Some value -> (Obj.obj value : 'a)
      | None -> walk owner.parent)
  in
  walk from

(* ----- errors ----- *)

let set_error_handler owner handler = owner.error_handler <- Some handler

(* Hand [e] to the nearest error handler at or above [from]. Re-raises it when
   nobody handles it, so an unhandled error still surfaces where it happened. *)
let handle_error ?(from = !current) e =
  let rec walk = function
    | None -> raise e
    | Some owner -> (
      match owner.error_handler with
      | Some handler when not owner.disposed -> handler e
      | _ -> walk owner.parent)
  in
  walk from

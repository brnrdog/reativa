(* Asynchronous data as a signal (see resource.mli). *)

type 'a state =
  | Loading of 'a option
  | Ready of 'a
  | Failed of exn

type 'a t = {
  state : 'a state Signal.t;
  trigger : int Signal.t;
  (* The fetch whose result is still wanted; older ones are ignored. *)
  mutable generation : int;
  mutable alive : bool;
  suspense : int Signal.t option;
  mutable counted : bool;
}

let value = function Ready v | Loading (Some v) -> Some v | Loading None | Failed _ -> None
let is_loading = function Loading _ -> true | Ready _ | Failed _ -> false
let error = function Failed e -> Some e | Loading _ | Ready _ -> None

(* Keep the enclosing Suspense's pending count in step with this resource. *)
let set_counted r counted =
  if r.counted <> counted then begin
    r.counted <- counted;
    match r.suspense with
    | Some counter -> Signal.update counter (fun n -> if counted then n + 1 else n - 1)
    | None -> ()
  end

let previous r = value (Signal.peek r.state)

let make fetcher =
  let r =
    {
      state = Signal.make (Loading None);
      trigger = Signal.make 0;
      generation = 0;
      alive = true;
      suspense = Suspense_scope.current ();
      counted = false;
    }
  in
  Owner.on_cleanup (fun () ->
    r.alive <- false;
    set_counted r false);
  (* The fetcher runs inside an effect: every signal it reads before
     returning its promise is a dependency, and a change starts a new fetch. *)
  Effect.run (fun () ->
    ignore (Signal.get r.trigger);
    r.generation <- r.generation + 1;
    let generation = r.generation in
    let settle state =
      if r.alive && generation = r.generation then
        Signal.batch (fun () ->
          Signal.set r.state state;
          set_counted r false)
    in
    (match fetcher () with
     | promise ->
       Signal.untrack (fun () ->
         Signal.batch (fun () ->
           Signal.set r.state (Loading (previous r));
           set_counted r true));
       Promise.on_settled promise
         ~ok:(fun v -> settle (Ready v))
         ~error:(fun e -> settle (Failed e))
     | exception e -> Signal.untrack (fun () -> settle (Failed e)));
    None);
  r

let state r = Signal.get r.state
let peek r = Signal.peek r.state
let refetch r = Signal.update r.trigger (fun n -> n + 1)

let mutate r v =
  r.generation <- r.generation + 1;
  Signal.batch (fun () ->
    Signal.set r.state (Ready v);
    set_counted r false)

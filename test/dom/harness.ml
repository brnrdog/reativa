(* A tiny test harness for the jsdom suites, shared by both backends.

   Tests are registered with [test] (synchronous) or [async] (finishes when it
   calls [done_]) and run in registration order by [run], which reports the
   totals to test/dom/run.mjs through [Probe.report]. Output is TAP-like:
   "ok - ..." / "not ok - ..." lines under "# suite" headers. *)

let failures = ref 0
let total = ref 0
let current = ref ""

let check name cond =
  incr total;
  if cond then Probe.print ("ok - " ^ name)
  else begin
    incr failures;
    Probe.print ("not ok - " ^ !current ^ ": " ^ name)
  end

let equal_string name ~expected actual =
  if expected = actual then check name true
  else check (Printf.sprintf "%s\n    expected: %S\n    actual:   %S" name expected actual) false

let equal_int name ~expected actual =
  if expected = actual then check name true
  else check (Printf.sprintf "%s (expected %d, got %d)" name expected actual) false

let equal_bool name ~expected actual =
  if expected = actual then check name true
  else check (Printf.sprintf "%s (expected %b, got %b)" name expected actual) false

(* Passes when [f] raises; [f]'s exception is swallowed. *)
let raises name f =
  match f () with
  | () -> check (name ^ " (did not raise)") false
  | exception _ -> check name true

type entry =
  | Suite of string
  | Sync of string * (unit -> unit)
  | Async of string * ((unit -> unit) -> unit)

let queue : entry list ref = ref []
let add e = queue := e :: !queue
let suite name = add (Suite name)
let test name f = add (Sync (name, f))
let async name f = add (Async (name, f))

let fail_with name exn =
  incr total;
  incr failures;
  Probe.print (Printf.sprintf "not ok - %s: raised %s" name (Printexc.to_string exn))

(* Render [view] into a fresh container attached to <body>. *)
let mount view =
  let c = Probe.container () in
  Reativa.View.mount c view;
  c

let html c = Probe.inner_html c

let async_timeout_ms = 5000

let run () =
  let entries = List.rev !queue in
  queue := [];
  let rec next = function
    | [] -> Probe.report ~failed:!failures ~total:!total
    | Suite name :: rest ->
      Probe.print ("# " ^ name);
      next rest
    | Sync (name, f) :: rest ->
      current := name;
      (try f () with exn -> fail_with name exn);
      next rest
    | Async (name, f) :: rest ->
      current := name;
      let finished = ref false in
      let finish () =
        if not !finished then begin
          finished := true;
          (* Continue on a fresh tick so a test's own callbacks unwind first. *)
          Probe.set_timeout 0 (fun () -> next rest)
        end
      in
      Probe.set_timeout async_timeout_ms (fun () ->
        if not !finished then begin
          check (name ^ " (timed out)") false;
          finish ()
        end);
      (try f finish with exn -> fail_with name exn; finish ())
  in
  next entries

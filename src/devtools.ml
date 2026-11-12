(* Devtools: what the reactive graph is doing (see devtools.mli). *)

type kind = Signal | Computed | Effect

type node_info = {
  id : int;
  kind : kind;
  name : string option;
  subscribers : int;
  dependencies : int list;
  disposed : bool;
}

type event =
  | Created of { id : int; kind : kind; name : string option }
  | Written of { id : int; name : string option; value : string }
  | Recomputed of { id : int; name : string option }
  | Ran of { id : int; name : string option }
  | Disposed of { id : int; name : string option }

type entry = {
  node : Core.node;
  kind : kind;
  mutable is_disposed : bool;
  mutable last_seq : int;  (* last write, recompute or run *)
  mutable last_value : string;
  mutable target : (Obj.t * string) option;
}

let entries : (int, entry) Hashtbl.t = Hashtbl.create 256
let history_buffer : event Queue.t = Queue.create ()
let history_limit = ref 1000
let subscribers : (int * (event -> unit)) list ref = ref []
let next_subscriber = ref 0
let seq = ref 0
let muted = ref 0

(* ----- previews ----- *)

let preview (v : 'a) =
  match Dom.classify v with
  | `String ->
    let s = (Obj.magic v : string) in
    if String.length s > 60 then Printf.sprintf "%S…" (String.sub s 0 60) else Printf.sprintf "%S" s
  | `Number | `Boolean -> Dom.display_string v
  | `Function -> "<fun>"
  | `Undefined -> "None"
  | `Object -> "<value>"
  | `Other -> "<value>"

(* ----- recording ----- *)

let kind_of (node : Core.node) =
  match node.kind with Core.Signal -> Signal | Core.Computed -> Computed | Core.Effect -> Effect

let emit event =
  if !muted = 0 then begin
    Queue.push event history_buffer;
    while Queue.length history_buffer > !history_limit do
      ignore (Queue.pop history_buffer)
    done;
    List.iter (fun (_, f) -> f event) !subscribers
  end

let entry_of (node : Core.node) =
  match Hashtbl.find_opt entries node.id with
  | Some e -> e
  | None ->
    let e = { node; kind = kind_of node; is_disposed = false; last_seq = 0; last_value = ""; target = None } in
    Hashtbl.replace entries node.id e;
    e

let touch e =
  incr seq;
  e.last_seq <- !seq

let hooks : Trace.hooks =
  {
    created =
      (fun node ->
        let e = entry_of node in
        touch e;
        emit (Created { id = node.id; kind = e.kind; name = node.name }));
    written =
      (fun node value ->
        let e = entry_of node in
        touch e;
        e.last_value <- preview value;
        emit (Written { id = node.id; name = node.name; value = e.last_value }));
    recomputed =
      (fun node ->
        touch (entry_of node);
        emit (Recomputed { id = node.id; name = node.name }));
    ran =
      (fun node ->
        touch (entry_of node);
        emit (Ran { id = node.id; name = node.name }));
    disposed =
      (fun node ->
        (entry_of node).is_disposed <- true;
        emit (Disposed { id = node.id; name = node.name }));
    bound = (fun node el what -> (entry_of node).target <- Some (el, what));
  }

let install ?(history = 1000) () =
  history_limit := history;
  Trace.install hooks

let uninstall () =
  Trace.uninstall ();
  Hashtbl.reset entries;
  Queue.clear history_buffer;
  subscribers := []

let installed () = !Trace.enabled

let subscribe f =
  incr next_subscriber;
  let id = !next_subscriber in
  subscribers := (id, f) :: !subscribers;
  fun () -> subscribers := List.filter (fun (i, _) -> i <> id) !subscribers

let mute f =
  incr muted;
  match f () with
  | r ->
    decr muted;
    r
  | exception e ->
    decr muted;
    raise e

let history () = List.of_seq (Queue.to_seq history_buffer)
let clear_history () = Queue.clear history_buffer

(* ----- inspection ----- *)

let dependencies (node : Core.node) =
  let rec walk acc = function None -> List.rev acc | Some (l : Core.link) -> walk (l.source.id :: acc) l.next_dep in
  walk [] node.first_dep

let subscriber_count (node : Core.node) =
  let rec walk n = function None -> n | Some (l : Core.link) -> walk (n + 1) l.next_sub in
  walk 0 node.first_sub

let info_of e =
  {
    id = e.node.id;
    kind = e.kind;
    name = e.node.name;
    subscribers = subscriber_count e.node;
    dependencies = dependencies e.node;
    disposed = e.is_disposed;
  }

let inspect id = Option.map info_of (Hashtbl.find_opt entries id)

let snapshot () =
  Hashtbl.fold (fun _ e acc -> if e.is_disposed then acc else info_of e :: acc) entries []
  |> List.sort (fun a b -> compare a.id b.id)

let value id = Option.map (fun e -> e.last_value) (Hashtbl.find_opt entries id)

(* ----- tracing one interaction ----- *)

type counts = { writes : int; recomputes : int; runs : int; created : int; disposed : int }
type trace = { events : event list; counts : counts }

let record f =
  let events = ref [] in
  let unsubscribe = subscribe (fun e -> events := e :: !events) in
  (match f () with
   | () -> unsubscribe ()
   | exception e ->
     unsubscribe ();
     raise e);
  let events = List.rev !events in
  let count p = List.length (List.filter p events) in
  {
    events;
    counts =
      {
        writes = count (function Written _ -> true | _ -> false);
        recomputes = count (function Recomputed _ -> true | _ -> false);
        runs = count (function Ran _ -> true | _ -> false);
        created = count (function Created _ -> true | _ -> false);
        disposed = count (function Disposed _ -> true | _ -> false);
      };
  }

(* ----- why ----- *)

type action = Written_by_user | Recomputed_from | Ran_after

type cause = {
  node : node_info;
  action : action;
  value : string option;
  because : cause option;
}

(* Why [id] last changed or ran: the dependency touched most recently before
   it, followed back to the signal write that started it. *)
let rec why id =
  match Hashtbl.find_opt entries id with
  | None -> None
  | Some e -> (
    match e.kind with
    | Signal -> Some { node = info_of e; action = Written_by_user; value = Some e.last_value; because = None }
    | Computed | Effect ->
      let latest =
        List.fold_left
          (fun best dep ->
            match (Hashtbl.find_opt entries dep, best) with
            | Some d, Some (b : entry) when d.last_seq > b.last_seq -> Some d
            | Some d, None -> Some d
            | _ -> best)
          None (dependencies e.node)
      in
      Some
        {
          node = info_of e;
          action = (match e.kind with Effect -> Ran_after | _ -> Recomputed_from);
          value = None;
          because = (match latest with Some d -> why d.node.id | None -> None);
        })

(* ----- the DOM ----- *)

(* An effect writes to [el] when its target is [el] or one of [el]'s own
   text children (a reactive text leaf writes its text node). *)
let writes_to (target : Dom.t) what (el : Dom.t) =
  Dom.is_same_node target el
  || String.equal what "text"
     && match Dom.parent_node target with Some parent -> Dom.is_same_node parent el | None -> false

let effects_writing (el : Dom.t) =
  Hashtbl.fold
    (fun _ e acc ->
      match e.target with
      | Some (target, what) when (not e.is_disposed) && writes_to (Obj.obj target) what el ->
        (e.node.id, what) :: acc
      | _ -> acc)
    entries []
  |> List.sort compare

let target_of id =
  match Hashtbl.find_opt entries id with
  | Some { target = Some (el, what); _ } -> Some ((Obj.obj el : Dom.t), what)
  | _ -> None

let rec root_signals cause =
  match cause.because with
  | None -> if cause.node.kind = Signal then [ cause.node.id ] else []
  | Some c -> root_signals c

let writers_of el =
  List.concat_map
    (fun (id, _) -> match why id with Some c -> root_signals c | None -> [])
    (effects_writing el)
  |> List.sort_uniq compare

(* Effects that can never run again: alive, but reading nothing. *)
let leaks () =
  Hashtbl.fold
    (fun _ e acc ->
      if e.kind = Effect && (not e.is_disposed) && Option.is_none e.node.first_dep then info_of e :: acc else acc)
    entries []
  |> List.sort (fun a b -> compare a.id b.id)

(* ----- JSON, for tools outside the page ----- *)

let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let json_name = function Some n -> json_string n | None -> "null"
let kind_name = function Signal -> "signal" | Computed -> "computed" | Effect -> "effect"
let json_list f l = "[" ^ String.concat "," (List.map f l) ^ "]"

let node_json (n : node_info) =
  Printf.sprintf {|{"id":%d,"kind":"%s","name":%s,"subscribers":%d,"dependencies":%s,"disposed":%b}|} n.id
    (kind_name n.kind) (json_name n.name) n.subscribers
    (json_list string_of_int n.dependencies)
    n.disposed

let event_json = function
  | Created { id; kind; name } ->
    Printf.sprintf {|{"type":"created","id":%d,"kind":"%s","name":%s}|} id (kind_name kind) (json_name name)
  | Written { id; name; value } ->
    Printf.sprintf {|{"type":"written","id":%d,"name":%s,"value":%s}|} id (json_name name) (json_string value)
  | Recomputed { id; name } -> Printf.sprintf {|{"type":"recomputed","id":%d,"name":%s}|} id (json_name name)
  | Ran { id; name } -> Printf.sprintf {|{"type":"ran","id":%d,"name":%s}|} id (json_name name)
  | Disposed { id; name } -> Printf.sprintf {|{"type":"disposed","id":%d,"name":%s}|} id (json_name name)

let rec cause_json c =
  Printf.sprintf {|{"node":%s,"action":"%s","value":%s,"because":%s}|} (node_json c.node)
    (match c.action with Written_by_user -> "written" | Recomputed_from -> "recomputed" | Ran_after -> "ran")
    (match c.value with Some v -> json_string v | None -> "null")
    (match c.because with Some b -> cause_json b | None -> "null")

let expose ?(name = "__reativaDevtools") () =
  Dom.expose_object name
    [|
      ("snapshot", Obj.repr (fun () -> json_list node_json (snapshot ())));
      ("history", Obj.repr (fun () -> json_list event_json (history ())));
      ("clearHistory", Obj.repr (fun () -> clear_history (); "null"));
      ("why", Obj.repr (fun (id : int) -> match why id with Some c -> cause_json c | None -> "null"));
      ( "whyElement",
        Obj.repr (fun (el : Dom.t) ->
          json_list
            (fun (id, what) ->
              Printf.sprintf {|{"effect":%d,"writes":%s,"cause":%s}|} id (json_string what)
                (match why id with Some c -> cause_json c | None -> "null"))
            (effects_writing el)) );
      ("leaks", Obj.repr (fun () -> json_list node_json (leaks ())));
    |]

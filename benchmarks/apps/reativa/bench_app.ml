(* Reativa benchmark application.

   Idiomatic fine-grained Reativa, mirroring the xote and SolidJS apps: the
   list is a signal, and each row owns a signal for its label so a label change
   writes one text node instead of re-rendering the row. Written against the
   plain View API (no mlx) so the same file builds with both backends. *)

open Reativa

type row = { id : int; label : string Signal.t }

(* Long lists: only tail-recursive list functions below, since js_of_ocaml
   runs with the browser's (small) stack. *)
let make_rows count =
  List.rev
    (List.fold_left (fun acc (r : Bench_data.raw) -> { id = r.id; label = Signal.make r.label } :: acc) [] (Bench_data.build count))

let rows : row list Signal.t = Signal.make []
let selected = Signal.make 0
let run () = Signal.set rows (make_rows 1000)
let run_lots () = Signal.set rows (make_rows 10000)
let add () = Signal.set rows (List.rev_append (List.rev (Signal.peek rows)) (make_rows 1000))
let clear () = Signal.set rows []

let update () =
  Signal.batch (fun () ->
    List.iteri
      (fun i row -> if i mod 10 = 0 then Signal.update row.label (fun l -> l ^ " !!!"))
      (Signal.peek rows))

let swap_rows () =
  let current = Array.of_list (Signal.peek rows) in
  if Array.length current > 998 then begin
    let first = current.(1) in
    current.(1) <- current.(998);
    current.(998) <- first;
    Signal.set rows (Array.to_list current)
  end

let remove id = Signal.set rows (List.filter (fun r -> r.id <> id) (Signal.peek rows))
let attr name value = View.Attr.make name (View.static value)
let cls value = attr "class" value

(* The row as the mlx ppx compiles it: the static markup is one template,
   parsed once and cloned per row, and only the four dynamic parts are filled
   in. Written out here (rather than in .mlx) so the app builds without the
   mlx toolchain; the ppx emits the same View.template call for

     <tr className=(if Signal.get selected = row.id then "danger" else "")>
       <td className="col-md-1">(row.id)</td>
       <td className="col-md-4">
         <a className="lbl" onClick=(fun _ -> Signal.set selected row.id)>(Signal.get row.label)</a>
       </td>
       <td className="col-md-1">
         <a className="remove" onClick=(fun _ -> remove row.id)>
           <span className="glyphicon glyphicon-remove" aria_hidden="true" />
         </a>
       </td>
       <td className="col-md-6" />
     </tr> *)
let row_template =
  View.Template.make
    ({|<tr><td class="col-md-1"> </td><td class="col-md-4"><a class="lbl"> </a></td>|}
    ^ {|<td class="col-md-1"><a class="remove"><span class="glyphicon glyphicon-remove" aria-hidden="true"></span></a></td>|}
    ^ {|<td class="col-md-6"></td></tr>|})

let render_row (row_signal : row Signal.t) =
  let row = Signal.peek row_signal in
  View.template row_template
    [
      View.Template.attr [ 0 ]
        (View.Attr.class_reactive (fun () -> if Signal.get selected = row.id then "danger" else ""));
      View.Template.text [ 0; 0; 0 ] (View.static (string_of_int row.id));
      View.Template.event [ 0; 1; 0 ] "click" (fun _ -> Signal.set selected row.id);
      View.Template.text [ 0; 1; 0; 0 ] (View.signal row.label);
      View.Template.event [ 0; 2; 0 ] "click" (fun _ -> remove row.id);
    ]

let button id label handler =
  View.element "button" ~attrs:[ attr "id" id ] ~events:[ View.On.click (fun _ -> handler ()) ]
    [ View.text (View.static label) ]

let app =
  View.element "div" ~attrs:[ cls "container" ]
    [
      View.element "div" ~attrs:[ cls "jumbotron" ]
        [
          View.element "h1" [ View.text (View.static "Reativa") ];
          View.element "div" ~attrs:[ cls "actions" ]
            [
              button "run" "Create 1,000 rows" run;
              button "runlots" "Create 10,000 rows" run_lots;
              button "add" "Append 1,000 rows" add;
              button "update" "Update every 10th row" update;
              button "clear" "Clear" clear;
              button "swaprows" "Swap Rows" swap_rows;
            ];
        ];
      View.element "table" ~attrs:[ attr "id" "main-table" ]
        [
          View.element "tbody" ~attrs:[ attr "id" "tbody" ]
            [ View.for_with_key (fun () -> Signal.get rows) ~key:(fun r -> string_of_int r.id) render_row ];
        ];
    ]

let () = View.mount_by_id "root" app

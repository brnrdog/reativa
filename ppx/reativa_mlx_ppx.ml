open Ppxlib

module Builder = Ast_builder.Default

let located ~loc txt = { Location.txt; loc }

let rec longident_last = function
  | Longident.Lident name -> Some name
  | Longident.Ldot (_, name) -> Some name
  | Longident.Lapply (_, ident) -> longident_last ident

let expression_ident_last expr =
  match expr.pexp_desc with
  | Pexp_ident { txt; _ } -> longident_last txt
  | _ -> None

let expression_ident_is name expr =
  match expression_ident_last expr with
  | Some found -> String.equal found name
  | None -> false

let expression_ident_is_any names expr =
  match expression_ident_last expr with
  | Some found -> List.exists (String.equal found) names
  | None -> false

let has_jsx_attribute attrs =
  List.exists
    (fun attr -> String.equal attr.attr_name.txt "JSX")
    attrs

let is_thunk expr =
  match expr.pexp_desc with
  | Pexp_function _ -> true
  | _ -> false

let is_value_wrapper expr =
  match expr.pexp_desc with
  | Pexp_apply (callee, [ (Nolabel, _) ]) ->
      expression_ident_is_any [ "static"; "dynamic"; "signal" ] callee
  | _ -> false

(* [Signal.get] (or [Reativa.Signal.get]) — the tracked read primitive.
   [Signal.peek] is deliberately excluded: peeking is an explicit request to
   *not* track, so peek-only expressions stay static. *)
let longident_is_signal_get = function
  | Longident.Ldot (prefix, "get") ->
      (match longident_last prefix with
       | Some "Signal" -> true
       | _ -> false)
  | _ -> false

exception Signal_read_found

(* Detect eager signal reads: any mention of [Signal.get] outside a nested
   [fun]. Reads inside a lambda only happen when that lambda is called, so they
   are not eager reads of the surrounding expression — thunking the outer
   expression would not track them (and event handlers must not be thunked). *)
let signal_read_iter =
  object
    inherit Ast_traverse.iter as super

    method! expression expr =
      match expr.pexp_desc with
      | Pexp_ident { txt; _ } when longident_is_signal_get txt ->
          raise Signal_read_found
      | Pexp_function _ -> ()
      | _ -> super#expression expr
  end

let reads_signal expr =
  match signal_read_iter#expression expr with
  | () -> false
  | exception Signal_read_found -> true

let wrap_call ~loc name arg =
  Builder.pexp_apply ~loc (Builder.evar ~loc name) [ (Nolabel, arg) ]

let thunk expr =
  let loc = { expr.pexp_loc with loc_ghost = true } in
  let unit_pattern =
    Builder.ppat_construct ~loc (located ~loc (Longident.Lident "()")) None
  in
  Builder.pexp_fun ~loc Nolabel None unit_pattern expr

let wrap_value expr =
  if is_value_wrapper expr then
    expr
  else if is_thunk expr then
    wrap_call ~loc:expr.pexp_loc "dynamic" expr
  else if reads_signal expr then
    (* Eager signal read: auto-thunk so the read is tracked and the value
       updates in place — [Signal.get s] becomes [dynamic (fun () -> Signal.get s)]. *)
    wrap_call ~loc:expr.pexp_loc "dynamic" (thunk expr)
  else
    wrap_call ~loc:expr.pexp_loc "static" expr

let inferred_value_labels =
  [
    "aria_label";
    "className";
    "class_";
    "checked";
    "condition";
    "disabled";
    "href";
    "id";
    "items";
    "placeholder";
    "style";
    "to_";
    "type_";
    "value";
  ]

let should_infer_label = function
  | Labelled label | Optional label ->
      List.exists (String.equal label) inferred_value_labels
  | Nolabel -> false

let view_value_call ~loc name arg =
  Builder.pexp_apply ~loc
    (Builder.pexp_ident ~loc
       (located ~loc (Longident.Ldot (Longident.Lident "View", name))))
    [ (Nolabel, arg) ]

(* Bare scalar JSX children: [<p>"Hello"</p>] instead of
   [<p>(View.text "Hello")</p>]. Literal strings, ints and floats become the
   corresponding [View.text]/[View.int]/[View.float] static leaves. *)
let infer_bare_child expr =
  let loc = { expr.pexp_loc with loc_ghost = true } in
  match expr.pexp_desc with
  | Pexp_constant (Pconst_string _) ->
      view_value_call ~loc "text" (wrap_value expr)
  | Pexp_constant (Pconst_integer (_, None)) ->
      view_value_call ~loc "int" (wrap_value expr)
  | Pexp_constant (Pconst_float (_, None)) ->
      view_value_call ~loc "float" (wrap_value expr)
  | _ -> expr

let rec map_list_literal f expr =
  match expr.pexp_desc with
  | Pexp_construct
      ( ({ txt = Longident.Lident "::"; _ } as cons),
        Some ({ pexp_desc = Pexp_tuple [ head; tail ]; _ } as cell) ) ->
      let cell =
        { cell with pexp_desc = Pexp_tuple [ f head; map_list_literal f tail ] }
      in
      { expr with pexp_desc = Pexp_construct (cons, Some cell) }
  | _ -> expr

let infer_jsx_arg (label, expr) =
  match label with
  | Labelled "children" | Optional "children" ->
      (label, map_list_literal infer_bare_child expr)
  | _ when should_infer_label label -> (label, wrap_value expr)
  | _ -> (label, expr)

let is_view_value_constructor expr =
  match expr.pexp_desc with
  | Pexp_ident { txt = Longident.Ldot (Longident.Lident "View", name); _ } ->
      List.exists (String.equal name) [ "text"; "int"; "float" ]
  | _ -> false

let infer_view_value_call expr =
  match expr.pexp_desc with
  | Pexp_apply (callee, [ (Nolabel, arg) ]) when is_view_value_constructor callee ->
      { expr with pexp_desc = Pexp_apply (callee, [ (Nolabel, wrap_value arg) ]) }
  | _ -> expr

let var_name = function
  | { ppat_desc = Ppat_var { txt; _ }; _ } -> Some txt
  | _ -> None

let binding_named name binding =
  match var_name binding.pvb_pat with Some txt -> String.equal txt name | None -> false

let item_defines_value name item =
  match item.pstr_desc with
  | Pstr_value (_, bindings) -> List.exists (binding_named name) bindings
  | _ -> false

let rec expr_accepts_children expr =
  match expr.pexp_desc with
  | Pexp_function (params, _, body) ->
      let param_accepts_children param =
        match param.pparam_desc with
        | Pparam_val (Labelled "children", _, _)
        | Pparam_val (Optional "children", _, _) ->
            true
        | _ -> false
      in
      List.exists param_accepts_children params
      ||
      (match body with
       | Pfunction_body body -> expr_accepts_children body
       | Pfunction_cases _ -> false)
  | Pexp_constraint (body, _)
  | Pexp_coerce (body, _, _)
  | Pexp_newtype (_, body) ->
      expr_accepts_children body
  | _ -> false

let component_accepts_children structure =
  let binding_accepts_children binding =
    binding_named "component" binding && expr_accepts_children binding.pvb_expr
  in
  List.exists
    (fun item ->
      match item.pstr_desc with
      | Pstr_value (_, bindings) -> List.exists binding_accepts_children bindings
      | _ -> false)
    structure

let create_element_item ~loc ~forward_children =
  let unit_pattern =
    Builder.ppat_construct ~loc (located ~loc (Longident.Lident "()")) None
  in
  let children_pattern =
    if forward_children then
      Builder.ppat_var ~loc (located ~loc "children")
    else
      Builder.ppat_any ~loc
  in
  let component = Builder.evar ~loc "component" in
  let body =
    if forward_children then
      Builder.pexp_apply ~loc component
        [ (Labelled "children", Builder.evar ~loc "children") ]
    else
      component
  in
  let expr =
    Builder.pexp_fun ~loc Nolabel None unit_pattern
      (Builder.pexp_fun ~loc (Labelled "children") None children_pattern body)
  in
  let binding =
    Builder.value_binding ~loc
      ~pat:(Builder.ppat_var ~loc (located ~loc "createElement"))
      ~expr
  in
  Builder.pstr_value ~loc Nonrecursive [ binding ]

let append_create_element_if_component ~loc structure =
  let has_component = List.exists (item_defines_value "component") structure in
  let has_create_element =
    List.exists (item_defines_value "createElement") structure
  in
  if (not has_component) || has_create_element then
    structure
  else
    let forward_children = component_accepts_children structure in
    structure @ [ create_element_item ~loc ~forward_children ]

let mapper =
  object
    inherit Ast_traverse.map as super

    method! expression expr =
      let expr = super#expression expr in
      let expr = infer_view_value_call expr in
      match expr.pexp_desc with
      | Pexp_apply (callee, args) when has_jsx_attribute expr.pexp_attributes ->
          { expr with pexp_desc = Pexp_apply (callee, List.map infer_jsx_arg args) }
      | _ -> expr

    method! module_expr expr =
      let expr = super#module_expr expr in
      match expr.pmod_desc with
      | Pmod_structure structure ->
          let structure =
            append_create_element_if_component ~loc:expr.pmod_loc structure
          in
          { expr with pmod_desc = Pmod_structure structure }
      | _ -> expr
  end

let () =
  Driver.register_transformation "reativa_mlx_ppx" ~impl:mapper#structure

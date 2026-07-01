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

let wrap_call ~loc name arg =
  Builder.pexp_apply ~loc (Builder.evar ~loc name) [ (Nolabel, arg) ]

let wrap_value expr =
  if is_value_wrapper expr then
    expr
  else if is_thunk expr then
    wrap_call ~loc:expr.pexp_loc "dynamic" expr
  else
    wrap_call ~loc:expr.pexp_loc "static" expr

let inferred_value_labels =
  [
    "aria_label";
    "className";
    "class_";
    "checked";
    "disabled";
    "href";
    "id";
    "placeholder";
    "style";
    "type_";
    "value";
  ]

let should_infer_label = function
  | Labelled label | Optional label ->
      List.exists (String.equal label) inferred_value_labels
  | Nolabel -> false

let infer_jsx_arg (label, expr) =
  if should_infer_label label then
    (label, wrap_value expr)
  else
    (label, expr)

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

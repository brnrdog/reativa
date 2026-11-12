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

(* An [onXxx] prop is an event handler: a function, never a value. *)
let is_event_label label =
  String.length label > 2
  && String.equal (String.sub label 0 2) "on"
  && match label.[2] with 'A' .. 'Z' -> true | _ -> false

(* On an HTML/SVG element every prop is a value except event handlers and the
   [attrs]/[ref] escape hatches, so new props in View.Mlx need no change here.
   On a component tag only the built-in components' value props are wrapped:
   other props keep whatever type the component declares. *)
let should_infer_label ~element = function
  | Labelled label | Optional label ->
      if element then
        not (is_event_label label || List.mem label [ "children"; "attrs"; "ref"; "key" ])
      else List.exists (String.equal label) inferred_value_labels
  | Nolabel -> false

let view_value_call ~loc name arg =
  Builder.pexp_apply ~loc
    (Builder.pexp_ident ~loc
       (located ~loc (Longident.Ldot (Longident.Lident "View", name))))
    [ (Nolabel, arg) ]

(* A call whose callee lives directly in [View] (View.text, View.show, ...)
   already produces a view; leave it alone so it stays fully typed. *)
let is_view_application expr =
  match expr.pexp_desc with
  | Pexp_apply (callee, _) ->
      (match callee.pexp_desc with
       | Pexp_ident { txt = Longident.Ldot (Longident.Lident "View", _); _ } ->
           true
       | _ -> false)
  | _ -> false

(* Bare JSX children need no value component at all:

   - literal strings/ints/floats become static [View.text]/[View.int]/
     [View.float] leaves at compile time;
   - nested JSX elements and explicit [View.*] calls pass through untouched
     (they are already views, and stay fully typed);
   - inside HTML element tags only: a thunk, or an expression that eagerly
     reads a signal, becomes a tracked [View.child] region that re-renders
     when its reads change, and anything else goes through [View.child]'s
     runtime coercion so a plain [string]/[int]/[float] value — or a view held
     in a variable — renders directly.

   Component tags ([<Router>], [<View.Show>], ...) get the literal wrapping
   only: their children are not necessarily views (e.g. [Router]'s children
   are routes), so non-literal children keep their own types. *)
let infer_child ~element expr =
  let loc = { expr.pexp_loc with loc_ghost = true } in
  match expr.pexp_desc with
  | Pexp_constant (Pconst_string _) ->
      view_value_call ~loc "text" (wrap_value expr)
  | Pexp_constant (Pconst_integer (_, None)) ->
      view_value_call ~loc "int" (wrap_value expr)
  | Pexp_constant (Pconst_float (_, None)) ->
      view_value_call ~loc "float" (wrap_value expr)
  | _ when not element -> expr
  | Pexp_apply _ when has_jsx_attribute expr.pexp_attributes -> expr
  | _ when is_view_application expr -> expr
  | _ when is_thunk expr -> view_value_call ~loc "child" expr
  | _ when reads_signal expr -> view_value_call ~loc "child" (thunk expr)
  | _ -> view_value_call ~loc "child" expr

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

(* A lowercase-ident callee is an HTML element tag ([<div>], [<span>], ...);
   components lower to [Module.createElement] applications instead. *)
let is_element_callee callee =
  match callee.pexp_desc with
  | Pexp_ident { txt = Longident.Lident name; _ } ->
      String.length name > 0
      && (match name.[0] with 'a' .. 'z' | '_' -> true | _ -> false)
  | _ -> false

let infer_jsx_arg ~element (label, expr) =
  match label with
  | Labelled "children" | Optional "children" ->
      (label, map_list_literal (infer_child ~element) expr)
  | _ when should_infer_label ~element label -> (label, wrap_value expr)
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

(* The labelled parameters of a [component] function, in order, read off its
   syntax: [fun ~name ?(size = 1) ~children -> ...]. [None] when they cannot
   be read (the binding is not literally a function, or takes a positional
   argument other than a trailing [()]), in which case [createElement] falls
   back to applying [component] directly. The second component of the result
   says whether the function ends in a [()] parameter. *)
let component_params expr =
  let is_unit_pattern pat =
    match pat.ppat_desc with
    | Ppat_construct ({ txt = Longident.Lident "()"; _ }, None) -> true
    | _ -> false
  in
  let rec collect acc expr =
    match expr.pexp_desc with
    | Pexp_function (params, _, body) -> (
        let rec take acc = function
          | [] -> Some (acc, false)
          | { pparam_desc = Pparam_newtype _; _ } :: rest -> take acc rest
          | [ { pparam_desc = Pparam_val (Nolabel, None, pat); _ } ] when is_unit_pattern pat ->
              Some (acc, true)
          | { pparam_desc = Pparam_val (Nolabel, _, _); _ } :: _ -> None
          | { pparam_desc = Pparam_val (label, _, _); _ } :: rest -> take (label :: acc) rest
        in
        match take acc params with
        | None -> None
        | Some (acc, true) -> Some (acc, true)
        | Some (acc, false) -> (
            match body with
            | Pfunction_body body -> collect acc body
            (* [function] cases take a positional argument. *)
            | Pfunction_cases _ -> None))
    | Pexp_constraint (body, _) | Pexp_coerce (body, _, _) | Pexp_newtype (_, body) ->
        collect acc body
    | _ -> if acc = [] then None else Some (acc, false)
  in
  match collect [] expr with
  | Some (labels, trailing_unit) -> Some (List.rev labels, trailing_unit)
  | None -> None

let component_binding structure =
  List.find_map
    (fun item ->
      match item.pstr_desc with
      | Pstr_value (_, bindings) -> List.find_opt (binding_named "component") bindings
      | _ -> None)
    structure

let unit_pattern ~loc = Builder.ppat_construct ~loc (located ~loc (Longident.Lident "()")) None
let unit_expr ~loc = Builder.pexp_construct ~loc (located ~loc (Longident.Lident "()")) None

(* The eager form, for components whose parameters cannot be read:
   [let createElement () ~children = component ~children]. *)
let eager_create_element ~loc ~forward_children =
  let children_pattern =
    if forward_children then Builder.ppat_var ~loc (located ~loc "children")
    else Builder.ppat_any ~loc
  in
  let component = Builder.evar ~loc "component" in
  let body =
    if forward_children then
      Builder.pexp_apply ~loc component [ (Labelled "children", Builder.evar ~loc "children") ]
    else component
  in
  Builder.pexp_fun ~loc Nolabel None (unit_pattern ~loc)
    (Builder.pexp_fun ~loc (Labelled "children") None children_pattern body)

(* The lazy form. For [let component = fun ~name ?size ~children -> ...]:

     let createElement ~children:reativa__children ~name:reativa__name
         ?size:reativa__size () =
       View.component (fun () ->
         component ~name:reativa__name ?size:reativa__size
           ~children:reativa__children)

   so the body runs when the view is mounted, under its own owner and
   untracked (see [View.component]). Every prop is forwarded explicitly — an
   optional one as an option — and [()] comes last so optional props can be
   left out at the call site. Parameter names are prefixed so a prop can be
   called anything, [component] included. *)
let lazy_create_element ~loc ~labels ~trailing_unit ~forward_children =
  let var name = "reativa__" ^ name in
  let props =
    List.filter_map
      (function
        | (Labelled name | Optional name) when String.equal name "children" -> None
        | Labelled name -> Some (Labelled name, name)
        | Optional name -> Some (Optional name, name)
        | Nolabel -> None)
      labels
  in
  let forwarded =
    List.map (fun (label, name) -> (label, Builder.evar ~loc (var name))) props
    @ (if forward_children then [ (Labelled "children", Builder.evar ~loc (var "children")) ] else [])
    @ if trailing_unit then [ (Nolabel, unit_expr ~loc) ] else []
  in
  let call = Builder.pexp_apply ~loc (Builder.evar ~loc "component") forwarded in
  let body =
    Builder.pexp_apply ~loc
      (Builder.pexp_ident ~loc (located ~loc (Longident.Ldot (Longident.Lident "View", "component"))))
      [ (Nolabel, Builder.pexp_fun ~loc Nolabel None (unit_pattern ~loc) call) ]
  in
  let with_unit = Builder.pexp_fun ~loc Nolabel None (unit_pattern ~loc) body in
  let with_props =
    List.fold_right
      (fun (label, name) acc ->
        Builder.pexp_fun ~loc label None (Builder.ppat_var ~loc (located ~loc (var name))) acc)
      props with_unit
  in
  let children_pattern =
    if forward_children then Builder.ppat_var ~loc (located ~loc (var "children"))
    else Builder.ppat_any ~loc
  in
  Builder.pexp_fun ~loc (Labelled "children") None children_pattern with_props

let create_element_item ~loc structure =
  let forward_children = component_accepts_children structure in
  let expr =
    match component_binding structure with
    | Some binding -> (
        match component_params binding.pvb_expr with
        | Some (labels, trailing_unit) ->
            lazy_create_element ~loc ~labels ~trailing_unit ~forward_children
        | None -> eager_create_element ~loc ~forward_children)
    | None -> eager_create_element ~loc ~forward_children
  in
  let binding =
    Builder.value_binding ~loc ~pat:(Builder.ppat_var ~loc (located ~loc "createElement")) ~expr
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
    structure @ [ create_element_item ~loc structure ]

let mapper =
  object
    inherit Ast_traverse.map as super

    method! expression expr =
      let expr = super#expression expr in
      let expr = infer_view_value_call expr in
      match expr.pexp_desc with
      | Pexp_apply (callee, args) when has_jsx_attribute expr.pexp_attributes ->
          let element = is_element_callee callee in
          { expr with
            pexp_desc = Pexp_apply (callee, List.map (infer_jsx_arg ~element) args) }
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

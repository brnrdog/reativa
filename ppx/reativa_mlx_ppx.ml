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

(* Names in the current file that read a signal when applied: aliases of
   [Signal.get] ([let get = Signal.get]) and local helpers whose body reads
   one ([let label () = "Hi " ^ Signal.get name]), found by
   [collect_reactive_names] before the file is rewritten. Calling one is an
   eager read just like [Signal.get] itself: without this, [<p>(label ())</p>]
   would render once and never update. Shadowing is ignored, so a name can be
   over-approximated, which only costs an extra tracked region. *)
let reactive_names : (string, unit) Hashtbl.t = Hashtbl.create 16

let is_reactive_call callee =
  match callee.pexp_desc with
  | Pexp_ident { txt = Longident.Lident name; _ } -> Hashtbl.mem reactive_names name
  | _ -> false

(* Detect eager signal reads: any mention of [Signal.get], or a call to a name
   in [reactive_names], outside a nested [fun]. Reads inside a lambda only
   happen when that lambda is called, so they are not eager reads of the
   surrounding expression — thunking the outer expression would not track them
   (and event handlers must not be thunked). *)
let signal_read_iter =
  object
    inherit Ast_traverse.iter as super

    method! expression expr =
      match expr.pexp_desc with
      | Pexp_ident { txt; _ } when longident_is_signal_get txt ->
          raise Signal_read_found
      | Pexp_apply (callee, _) when is_reactive_call callee -> raise Signal_read_found
      | Pexp_function _ -> ()
      | _ -> super#expression expr
  end

let reads_signal expr =
  match signal_read_iter#expression expr with
  | () -> false
  | exception Signal_read_found -> true

(* The body of a function, past the parameters of its own [fun] only: a
   helper that returns a callback ([let h () = fun _ -> Signal.get s]) does
   not read when [h ()] is evaluated, only when the callback runs. *)
let rec function_body expr =
  match expr.pexp_desc with
  | Pexp_function (_, _, Pfunction_body body) -> Some body
  | Pexp_function (_, _, Pfunction_cases _) -> Some expr
  | Pexp_constraint (e, _) | Pexp_coerce (e, _, _) | Pexp_newtype (_, e) -> function_body e
  | _ -> None

let is_signal_get_alias expr =
  match expr.pexp_desc with
  | Pexp_ident { txt; _ } -> longident_is_signal_get txt
  | _ -> false

(* Every [let name = ...] in the file, at any depth. *)
let collect_bindings structure =
  let acc = ref [] in
  let iter =
    object
      inherit Ast_traverse.iter as super

      method! value_binding vb =
        (match vb.pvb_pat.ppat_desc with
         | Ppat_var { txt; _ } -> acc := (txt, vb.pvb_expr) :: !acc
         | _ -> ());
        super#value_binding vb
    end
  in
  iter#structure structure;
  !acc

(* Fill [reactive_names] for [structure]: aliases first, then helpers, to a
   fixpoint so a helper calling a helper counts too. For a [function] with
   cases, any case reading a signal makes it reactive. *)
let collect_reactive_names structure =
  Hashtbl.reset reactive_names;
  let bindings = collect_bindings structure in
  List.iter
    (fun (name, expr) -> if is_signal_get_alias expr then Hashtbl.replace reactive_names name ())
    bindings;
  let rec fixpoint () =
    let changed = ref false in
    List.iter
      (fun (name, expr) ->
        if not (Hashtbl.mem reactive_names name) then
          match function_body expr with
          | Some body ->
              let reads =
                match body.pexp_desc with
                | Pexp_function (_, _, Pfunction_cases (cases, _, _)) ->
                    List.exists (fun c -> reads_signal c.pc_rhs) cases
                | _ -> reads_signal body
              in
              if reads then begin
                Hashtbl.replace reactive_names name ();
                changed := true
              end
          | None -> ())
      bindings;
    if !changed then fixpoint ()
  in
  fixpoint ()

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
       | Pexp_ident { txt = Longident.Ldot (Longident.Lident "View", _); _ }
       | Pexp_ident
           { txt = Longident.Ldot (Longident.Ldot (Longident.Lident "Reativa", "View"), _); _ } ->
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

(* ----- templates -----

   An element tree whose structure is known at compile time is compiled to a
   template: its static parts (tags, literal attributes, literal text) become
   an HTML string parsed once at run time and cloned per instance, and every
   dynamic part becomes a typed "hole" filled after cloning (see
   [View.Template]). The skeleton is hoisted to the top of the file, one
   binding per distinct HTML string.

   An element is left to the [View.Mlx] path — and becomes a child hole of its
   parent's template, if any — whenever compiling it could change what the
   user wrote: an unknown prop (so the type error stays), or markup the HTML
   parser would restructure (text inside table sections, a <tr> directly in a
   <table>, a block element inside a <p>, an <a> inside an <a>, ...). *)

let templates_enabled = ref true

let attribute_table =
  let t = Hashtbl.create 128 in
  List.iter (fun (label, name, kind) -> Hashtbl.replace t label (name, kind)) Mlx_prop_table.attributes;
  t

let event_table =
  let t = Hashtbl.create 64 in
  List.iter (fun (label, event) -> Hashtbl.replace t label event) Mlx_prop_table.events;
  t

let element_table =
  let t = Hashtbl.create 128 in
  List.iter (fun tag -> Hashtbl.replace t tag ()) Mlx_prop_table.elements;
  t

let void_elements = [ "area"; "br"; "col"; "embed"; "hr"; "img"; "input"; "source"; "track"; "wbr" ]
let table_sections = [ "table"; "thead"; "tbody"; "tfoot"; "tr" ]

(* Never compiled: their content model makes the parser rewrite what it
   reads (select keeps only options; textarea and iframe hold raw text). *)
let opaque_elements = [ "select"; "option"; "optgroup"; "textarea"; "iframe"; "colgroup"; "col" ]

(* Elements that close an open <p> when they start. *)
let closes_p =
  [ "address"; "article"; "aside"; "blockquote"; "details"; "dialog"; "div"; "dl"; "fieldset";
    "figcaption"; "figure"; "footer"; "form"; "h1"; "h2"; "h3"; "h4"; "h5"; "h6"; "header";
    "hr"; "main"; "menu"; "nav"; "ol"; "p"; "pre"; "section"; "table"; "ul" ]

(* Elements the parser closes when the same element starts inside them. *)
let no_self_nesting = [ "a"; "button"; "form"; "li"; "dt"; "dd"; "p"; "h1"; "h2"; "h3"; "h4"; "h5"; "h6" ]

exception Not_templatable

(* Markup for a template is emitted as a plain OCaml string literal, which
   Melange reads byte by byte. So everything outside ASCII, written as
   {js|...|js} for its characters or not, goes into the markup as an HTML
   character reference: the literal stays ASCII, and the template parser turns
   the reference back into the character, the same on every backend. *)
let escape ~quote s =
  let b = Buffer.create (String.length s) in
  let rec go i =
    if i < String.length s then
      match s.[i] with
      | '&' -> Buffer.add_string b "&amp;"; go (i + 1)
      | '<' -> Buffer.add_string b "&lt;"; go (i + 1)
      | '>' -> Buffer.add_string b "&gt;"; go (i + 1)
      | '"' when quote -> Buffer.add_string b "&quot;"; go (i + 1)
      | c when Char.code c < 128 -> Buffer.add_char b c; go (i + 1)
      | _ ->
          (* An invalid sequence decodes to U+FFFD, as a browser would show it. *)
          let d = Stdlib.String.get_utf_8_uchar s i in
          Printf.bprintf b "&#x%X;" (Stdlib.Uchar.to_int (Stdlib.Uchar.utf_decode_uchar d));
          go (i + Stdlib.Uchar.utf_decode_length d)
  in
  go 0;
  Buffer.contents b

let escape_text s = escape ~quote:false s
let escape_attribute s = escape ~quote:true s

type tnode =
  | Ttext of string
  | Telement of string * string list * tnode list
  | Tplaceholder

let rec render_node b = function
  | Ttext s -> Buffer.add_string b (escape_text s)
  | Tplaceholder -> Buffer.add_string b "<!---->"
  | Telement (tag, attrs, children) ->
      Buffer.add_char b '<';
      Buffer.add_string b tag;
      List.iter
        (fun a ->
          Buffer.add_char b ' ';
          Buffer.add_string b a)
        attrs;
      Buffer.add_char b '>';
      if not (List.mem tag void_elements) then begin
        List.iter (render_node b) children;
        Buffer.add_string b "</";
        Buffer.add_string b tag;
        Buffer.add_char b '>'
      end

(* Skeletons found in the current file, hoisted by [rewrite]. *)
let hoisted : (string * string) list ref = ref []
let hoisted_by_html : (string, string) Hashtbl.t = Hashtbl.create 16

(* The hoisted bindings are ordinary top-level values, so a module without an
   interface exports them, and opening it brings them into scope. Their names
   carry the module's own name ("__reativa_template_card_0" in card.mlx), so
   an [open Card] further down another file cannot shadow that file's. *)
let unit_prefix = ref ""

let prefix_of_file fname =
  match Stdlib.Filename.basename fname with
  | "" | "_none_" -> ""
  | base ->
      let name = Stdlib.Filename.remove_extension base in
      Stdlib.String.map
        (fun c ->
          match c with
          | 'a' .. 'z' | '0' .. '9' | '_' -> c
          | 'A' .. 'Z' -> Stdlib.Char.lowercase_ascii c
          | _ -> '_')
        name
      ^ "_"

let hoist html =
  match Hashtbl.find_opt hoisted_by_html html with
  | Some name -> name
  | None ->
      let name = Printf.sprintf "__reativa_template_%s%d" !unit_prefix (List.length !hoisted) in
      hoisted := (name, html) :: !hoisted;
      Hashtbl.replace hoisted_by_html html name;
      name

let element_parts expr =
  match expr.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Lident tag; _ }; _ }, args)
    when has_jsx_attribute expr.pexp_attributes
         && String.length tag > 0
         && (match tag.[0] with 'a' .. 'z' -> true | _ -> false) ->
      Some (tag, args)
  | _ -> None

let rec list_items expr =
  match expr.pexp_desc with
  | Pexp_construct ({ txt = Longident.Lident "[]"; _ }, None) -> Some []
  | Pexp_construct ({ txt = Longident.Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ hd; tl ]; _ }) -> (
      match list_items tl with Some rest -> Some (hd :: rest) | None -> None)
  | _ -> None

let is_unit expr =
  match expr.pexp_desc with
  | Pexp_construct ({ txt = Longident.Lident "()"; _ }, None) -> true
  | _ -> false

let reativa_ident ~loc path =
  Builder.pexp_ident ~loc (located ~loc (Longident.parse ("Reativa.View." ^ path)))

(* [static]/[dynamic] wrapping, as [wrap_value], but fully qualified so the
   generated holes do not depend on what the file opened. *)
let wrap_value_qualified expr =
  let loc = { expr.pexp_loc with loc_ghost = true } in
  let call name arg = Builder.pexp_apply ~loc (reativa_ident ~loc name) [ (Nolabel, arg) ] in
  if is_value_wrapper expr then expr
  else if is_thunk expr then call "dynamic" expr
  else if reads_signal expr then call "dynamic" (thunk expr)
  else call "static" expr

(* The attribute text for a literal prop value, if it is one. *)
let static_attribute name kind expr =
  if String.equal name "value" then None
  else
    match (kind, expr.pexp_desc) with
    | Mlx_prop_table.String, Pexp_constant (Pconst_string (s, _, _)) ->
        Some [ Printf.sprintf "%s=\"%s\"" name (escape_attribute s) ]
    | Mlx_prop_table.Int, Pexp_constant (Pconst_integer (s, None)) -> (
        match int_of_string_opt s with
        | Some n -> Some [ Printf.sprintf "%s=\"%d\"" name n ]
        | None -> None)
    | Mlx_prop_table.Toggle, Pexp_construct ({ txt = Longident.Lident "true"; _ }, None) -> Some [ name ]
    | Mlx_prop_table.Toggle, Pexp_construct ({ txt = Longident.Lident "false"; _ }, None) -> Some []
    | _ -> None

(* Compile [expr] (an element) to a template instance, or raise
   [Not_templatable]. [map] rewrites the expressions that go into holes. *)
let compile_template ~map ~infer_child expr =
  let loc = { expr.pexp_loc with loc_ghost = true } in
  let holes = ref [] in
  let add_hole e = holes := e :: !holes in
  let path_expr path = Builder.elist ~loc (List.map (Builder.eint ~loc) path) in
  let apply name args = Builder.pexp_apply ~loc (reativa_ident ~loc ("Template." ^ name)) args in
  let str s = Builder.estring ~loc s in
  let rec element ~ancestors ~svg ~path (tag, args) =
    if not (Hashtbl.mem element_table tag) then raise Not_templatable;
    if List.mem tag opaque_elements then raise Not_templatable;
    if List.mem tag no_self_nesting && List.mem tag ancestors then raise Not_templatable;
    (match ancestors with
     | "p" :: _ when List.mem tag closes_p -> raise Not_templatable
     | "table" :: _ when String.equal tag "tr" -> raise Not_templatable
     | _ -> ());
    let svg = svg || String.equal tag "svg" in
    let has_class_name = List.exists (function Labelled "className", _ -> true | _ -> false) args in
    let statics = ref [] and children = ref None in
    let p = path_expr path in
    List.iter
      (fun (label, arg) ->
        match label with
        | Nolabel -> if not (is_unit arg) then raise Not_templatable
        | Labelled "children" -> children := Some arg
        | Labelled "attrs" -> add_hole (apply "attrs" [ (Nolabel, p); (Nolabel, map arg) ])
        | Labelled "ref" ->
            let attr = Builder.pexp_apply ~loc (reativa_ident ~loc "Attr.ref_") [ (Nolabel, map arg) ] in
            add_hole (apply "attr" [ (Nolabel, p); (Nolabel, attr) ])
        | Labelled "class_" when has_class_name -> ()
        | Labelled l when is_event_label l -> (
            match Hashtbl.find_opt event_table l with
            | Some event -> add_hole (apply "event" [ (Nolabel, p); (Nolabel, str event); (Nolabel, map arg) ])
            | None -> raise Not_templatable)
        | Labelled l -> (
            match Hashtbl.find_opt attribute_table l with
            | None -> raise Not_templatable
            | Some (name, kind) -> (
                match static_attribute name kind arg with
                | Some rendered -> statics := List.rev_append rendered !statics
                | None ->
                    let fn =
                      match kind with
                      | Mlx_prop_table.String -> "string_prop"
                      | Mlx_prop_table.Int -> "int_prop"
                      | Mlx_prop_table.Toggle -> "toggle_prop"
                      | Mlx_prop_table.Property -> "bool_prop"
                    in
                    add_hole
                      (apply fn [ (Nolabel, p); (Nolabel, str name); (Nolabel, wrap_value_qualified (map arg)) ])))
        | Optional _ -> raise Not_templatable)
      args;
    let child_nodes =
      match !children with
      | None -> []
      | Some list_expr -> (
          match list_items list_expr with
          | Some [] -> []
          | Some items ->
              if List.mem tag void_elements then raise Not_templatable;
              compile_children ~parent:tag ~ancestors:(tag :: ancestors)
                ~svg:(svg && not (String.equal tag "foreignObject")) ~path items
          | None ->
              if List.mem tag void_elements then raise Not_templatable;
              (* A list built at run time: one hole for all of it. *)
              let view =
                Builder.pexp_apply ~loc (reativa_ident ~loc "fragment") [ (Nolabel, map list_expr) ]
              in
              add_hole (child_hole ~svg (path @ [ 0 ]) view);
              [ Tplaceholder ])
    in
    Telement (tag, List.rev !statics, child_nodes)
  and child_hole ~svg path view =
    let svg_arg =
      if svg then [ (Labelled "svg", Builder.pexp_construct ~loc (located ~loc (Longident.Lident "true")) None) ]
      else []
    in
    apply "child" (svg_arg @ [ (Nolabel, path_expr path); (Nolabel, view) ])
  and compile_children ~parent ~ancestors ~svg ~path items =
    let index = ref 0 and nodes = ref [] and text = Buffer.create 16 in
    let flush () =
      if Buffer.length text > 0 then begin
        nodes := Ttext (Buffer.contents text) :: !nodes;
        incr index;
        Buffer.clear text
      end
    in
    let placeholder view =
      flush ();
      add_hole (child_hole ~svg (path @ [ !index ]) view);
      nodes := Tplaceholder :: !nodes;
      incr index
    in
    List.iter
      (fun item ->
        let literal_text =
          match item.pexp_desc with
          | Pexp_constant (Pconst_string (s, _, _)) -> Some s
          | Pexp_constant (Pconst_integer (s, None)) -> Option.map string_of_int (int_of_string_opt s)
          | _ -> None
        in
        match literal_text with
        | Some s ->
            (* The parser moves text out of table sections. *)
            if List.mem parent table_sections && String.length s > 0 then raise Not_templatable;
            Buffer.add_string text s
        | None -> (
            match element_parts item with
            | Some parts -> (
                flush ();
                let saved = !holes in
                match element ~ancestors ~svg ~path:(path @ [ !index ]) parts with
                | node ->
                    nodes := node :: !nodes;
                    incr index
                | exception Not_templatable ->
                    holes := saved;
                    placeholder (map item))
            | None -> placeholder (infer_child (map item))))
      items;
    flush ();
    List.rev !nodes
  in
  match element_parts expr with
  | None -> raise Not_templatable
  | Some parts ->
      let root = element ~ancestors:[] ~svg:false ~path:[ 0 ] parts in
      let b = Buffer.create 64 in
      render_node b root;
      let name = hoist (Buffer.contents b) in
      Builder.pexp_apply ~loc (reativa_ident ~loc "template")
        [ (Nolabel, Builder.evar ~loc name); (Nolabel, Builder.elist ~loc (List.rev !holes)) ]

let mapper =
  object (self)
    inherit Ast_traverse.map as super

    method! expression expr =
      let templated =
        if !templates_enabled && Option.is_some (element_parts expr) then
          match
            compile_template ~map:self#expression ~infer_child:(infer_child ~element:true) expr
          with
          | compiled -> Some compiled
          | exception Not_templatable -> None
        else None
      in
      match templated with
      | Some compiled -> compiled
      | None ->
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

let hoisted_bindings () =
  List.rev_map
    (fun (name, html) ->
      let loc = Location.none in
      let binding =
        Builder.value_binding ~loc
          ~pat:(Builder.ppat_var ~loc (located ~loc name))
          ~expr:(Builder.pexp_apply ~loc (reativa_ident ~loc "Template.make") [ (Nolabel, Builder.estring ~loc html) ])
      in
      (* A file with an interface does not export these; never warn about them. *)
      let silence =
        Builder.attribute ~loc ~name:(located ~loc "ocaml.warning")
          ~payload:(PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc "-32") [] ])
      in
      Builder.pstr_value ~loc Nonrecursive [ { binding with pvb_attributes = [ silence ] } ])
    !hoisted

(* [open Reativa.View.Mlx] is what makes mlx element tags resolve; once those
   elements compile to templates nothing in the file may use it any more, and
   the unused-open warning (an error in dev builds) would fire on code that
   did nothing wrong. Opens of a module named Mlx get that warning off. *)
let silence_mlx_opens =
  let warning loc =
    Builder.attribute ~loc ~name:(located ~loc "ocaml.warning")
      ~payload:(PStr [ Builder.pstr_eval ~loc (Builder.estring ~loc "-33") [] ])
  in
  let is_mlx (od : open_declaration) =
    match od.popen_expr.pmod_desc with
    | Pmod_ident { txt; _ } -> longident_last txt = Some "Mlx"
    | _ -> false
  in
  let silence (od : open_declaration) =
    { od with popen_attributes = warning od.popen_loc :: od.popen_attributes }
  in
  object
    inherit Ast_traverse.map as super

    method! structure_item item =
      let item = super#structure_item item in
      match item.pstr_desc with
      | Pstr_open od when is_mlx od -> { item with pstr_desc = Pstr_open (silence od) }
      | _ -> item

    method! expression expr =
      let expr = super#expression expr in
      match expr.pexp_desc with
      | Pexp_open (od, body) when is_mlx od -> { expr with pexp_desc = Pexp_open (silence od, body) }
      | _ -> expr
  end

let rewrite structure =
  collect_reactive_names structure;
  unit_prefix :=
    (match structure with item :: _ -> prefix_of_file item.pstr_loc.loc_start.pos_fname | [] -> "");
  hoisted := [];
  Hashtbl.reset hoisted_by_html;
  let structure = mapper#structure structure in
  hoisted_bindings () @ silence_mlx_opens#structure structure

(* For tests of the element path: rewrite without compiling templates. *)
let rewrite_without_templates structure =
  templates_enabled := false;
  match rewrite structure with
  | result ->
      templates_enabled := true;
      result
  | exception e ->
      templates_enabled := true;
      raise e

let () =
  Driver.add_arg "-no-templates" (Arg.Clear templates_enabled)
    ~doc:" compile mlx elements with View.Mlx instead of templates"

let () = Driver.register_transformation "reativa_mlx_ppx" ~impl:rewrite

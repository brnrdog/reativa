open Ppxlib

module B = Ast_builder.Default

type attr_value =
  | Attr_string of string
  | Attr_expr of string
  | Attr_bool

type attr = {
  name : string;
  value : attr_value;
}

type node = {
  tag : string;
  attrs : attr list;
  children : child list;
}

and child =
  | Element of node
  | Text of string
  | Expr of string

let is_name_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let parse_error ~loc fmt = Location.raise_errorf ~loc fmt

let parse_jsx ~loc source =
  let len = String.length source in
  let pos = ref 0 in
  let peek () = if !pos < len then Some source.[!pos] else None in
  let starts_with s =
    let s_len = String.length s in
    !pos + s_len <= len && String.sub source !pos s_len = s
  in
  let bump () = incr pos in
  let consume char =
    match peek () with
    | Some c when Char.equal c char -> bump ()
    | _ -> parse_error ~loc "expected '%c' in JSX input" char
  in
  let rec skip_space () =
    match peek () with
    | Some (' ' | '\n' | '\r' | '\t') ->
      bump ();
      skip_space ()
    | _ -> ()
  in
  let parse_name () =
    let start = !pos in
    while !pos < len && is_name_char source.[!pos] do
      incr pos
    done;
    if !pos = start then parse_error ~loc "expected JSX name";
    String.sub source start (!pos - start)
  in
  let parse_quoted quote =
    consume quote;
    let start = !pos in
    while !pos < len && not (Char.equal source.[!pos] quote) do
      incr pos
    done;
    if !pos >= len then parse_error ~loc "unterminated JSX string attribute";
    let value = String.sub source start (!pos - start) in
    consume quote;
    value
  in
  let parse_expr () =
    consume '{';
    let start = !pos in
    let depth = ref 1 in
    while !pos < len && !depth > 0 do
      match source.[!pos] with
      | '{' ->
        incr depth;
        incr pos
      | '}' ->
        decr depth;
        if !depth > 0 then incr pos
      | _ -> incr pos
    done;
    if !depth <> 0 then parse_error ~loc "unterminated JSX expression";
    let value = String.sub source start (!pos - start) |> String.trim in
    consume '}';
    value
  in
  let parse_attr () =
    let name = parse_name () in
    skip_space ();
    let value =
      match peek () with
      | Some '=' ->
        bump ();
        skip_space ();
        begin
          match peek () with
          | Some '"' -> Attr_string (parse_quoted '"')
          | Some '\'' -> Attr_string (parse_quoted '\'')
          | Some '{' -> Attr_expr (parse_expr ())
          | _ -> parse_error ~loc "expected JSX attribute value"
        end
      | _ -> Attr_bool
    in
    { name; value }
  in
  let rec parse_children closing_tag =
    let rec loop acc =
      if !pos >= len then parse_error ~loc "missing closing tag for <%s>" closing_tag;
      if starts_with ("</" ^ closing_tag ^ ">") then begin
        pos := !pos + String.length closing_tag + 3;
        List.rev acc
      end else
        match peek () with
        | Some '<' -> loop (Element (parse_element ()) :: acc)
        | Some '{' -> loop (Expr (parse_expr ()) :: acc)
        | Some _ ->
          let start = !pos in
          while
            !pos < len
            && not (Char.equal source.[!pos] '<')
            && not (Char.equal source.[!pos] '{')
          do
            incr pos
          done;
          let text = String.sub source start (!pos - start) |> String.trim in
          if String.equal text "" then loop acc else loop (Text text :: acc)
        | None -> parse_error ~loc "missing closing tag for <%s>" closing_tag
    in
    loop []
  and parse_element () =
    consume '<';
    if starts_with "/" then parse_error ~loc "unexpected closing JSX tag";
    let tag = parse_name () in
    let rec parse_attrs acc =
      skip_space ();
      if starts_with "/>" then begin
        pos := !pos + 2;
        { tag; attrs = List.rev acc; children = [] }
      end else if starts_with ">" then begin
        bump ();
        { tag; attrs = List.rev acc; children = parse_children tag }
      end else parse_attrs (parse_attr () :: acc)
    in
    parse_attrs []
  in
  skip_space ();
  let root = parse_element () in
  skip_space ();
  if !pos <> len then parse_error ~loc "unexpected content after JSX root";
  root

let parse_ocaml_expr ~loc source =
  try Parse.expression (Lexing.from_string source) with
  | Syntaxerr.Error _ -> parse_error ~loc "invalid OCaml expression in JSX: %s" source
  | Lexer.Error _ -> parse_error ~loc "invalid OCaml expression in JSX: %s" source
  | _ -> parse_error ~loc "invalid OCaml expression in JSX: %s" source

let lid ~loc name = { txt = Longident.parse name; loc }
let ident ~loc name = B.pexp_ident ~loc (lid ~loc name)
let str ~loc value = B.estring ~loc value
let list ~loc values = B.elist ~loc values
let unit ~loc = [%expr ()]

let apply ~loc fn args = B.pexp_apply ~loc fn args

let attr_helper = function
  | "class" -> Some "Reativa_ui.View.Attr.class_"
  | "id" -> Some "Reativa_ui.View.Attr.id"
  | "type" -> Some "Reativa_ui.View.Attr.type_"
  | "value" -> Some "Reativa_ui.View.Attr.value"
  | "placeholder" -> Some "Reativa_ui.View.Attr.placeholder"
  | "href" -> Some "Reativa_ui.View.Attr.href"
  | _ -> None

let reactive_attr_helper = function
  | "class" -> Some "Reativa_ui.View.Attr.class_reactive"
  | "value" -> Some "Reativa_ui.View.Attr.value_reactive"
  | "disabled" -> Some "Reativa_ui.View.Attr.disabled"
  | _ -> None

let event_helper = function
  | "onClick" -> Some "Reativa_ui.View.On.click"
  | "onInput" -> Some "Reativa_ui.View.On.input"
  | "onChange" -> Some "Reativa_ui.View.On.change"
  | "onKeyDown" -> Some "Reativa_ui.View.On.keydown"
  | "onSubmit" -> Some "Reativa_ui.View.On.submit"
  | _ -> None

let is_event_name name =
  String.length name > 2
  && Char.equal name.[0] 'o'
  && Char.equal name.[1] 'n'
  && Char.uppercase_ascii name.[2] = name.[2]

let lower_event_name name =
  let raw = String.sub name 2 (String.length name - 2) in
  String.lowercase_ascii raw

let lower_attr ~loc { name; value } =
  match value with
  | Attr_string value ->
    begin
      match attr_helper name with
      | Some helper -> apply ~loc (ident ~loc helper) [ (Nolabel, str ~loc value) ]
      | None ->
        apply
          ~loc
          (ident ~loc "Reativa_ui.View.Attr.make")
          [ (Nolabel, str ~loc name); (Nolabel, str ~loc value) ]
    end
  | Attr_expr source ->
    let expr = parse_ocaml_expr ~loc source in
    begin
      match reactive_attr_helper name with
      | Some helper -> apply ~loc (ident ~loc helper) [ (Nolabel, expr) ]
      | None ->
        apply
          ~loc
          (ident ~loc "Reativa_ui.View.Attr.reactive")
          [ (Nolabel, str ~loc name); (Nolabel, expr) ]
    end
  | Attr_bool ->
    apply
      ~loc
      (ident ~loc "Reativa_ui.View.Attr.make")
      [ (Nolabel, str ~loc name); (Nolabel, str ~loc "") ]

let lower_event ~loc { name; value } =
  let handler =
    match value with
    | Attr_expr source -> parse_ocaml_expr ~loc source
    | Attr_string _ | Attr_bool -> parse_error ~loc "event %s needs an OCaml expression" name
  in
  match event_helper name with
  | Some helper -> apply ~loc (ident ~loc helper) [ (Nolabel, handler) ]
  | None ->
    apply
      ~loc
      (ident ~loc "Reativa_ui.View.On.on")
      [ (Nolabel, str ~loc (lower_event_name name)); (Nolabel, handler) ]

let tag_helper = function
  | "div" | "span" | "p" | "h1" | "h2" | "h3" | "ul" | "ol" | "li" | "button" | "a"
  | "label" | "section" as tag -> Some ("Reativa_ui.View." ^ tag)
  | _ -> None

let rec lower_child ~loc = function
  | Text value -> apply ~loc (ident ~loc "Reativa_ui.View.text") [ (Nolabel, str ~loc value) ]
  | Expr source -> parse_ocaml_expr ~loc source
  | Element node -> lower_node ~loc node

and lower_node ~loc { tag; attrs; children } =
  let event_attrs, view_attrs = List.partition (fun attr -> is_event_name attr.name) attrs in
  let args = [] in
  let args =
    match view_attrs with
    | [] -> args
    | attrs -> (Labelled "attrs", list ~loc (List.map (lower_attr ~loc) attrs)) :: args
  in
  let args =
    match event_attrs with
    | [] -> args
    | attrs -> (Labelled "events", list ~loc (List.map (lower_event ~loc) attrs)) :: args
  in
  match tag with
  | "input" ->
    apply ~loc (ident ~loc "Reativa_ui.View.input") (List.rev ((Nolabel, unit ~loc) :: args))
  | _ ->
    let children = list ~loc (List.map (lower_child ~loc) children) in
    let fn =
      match tag_helper tag with
      | Some helper -> ident ~loc helper
      | None -> apply ~loc (ident ~loc "Reativa_ui.View.element") [ (Nolabel, str ~loc tag) ]
    in
    apply ~loc fn (List.rev ((Nolabel, children) :: args))

let expand ~ctxt source =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in
  parse_jsx ~loc source |> lower_node ~loc

let extension =
  Extension.V3.declare
    "reativa.jsx"
    Extension.Context.expression
    Ast_pattern.(single_expr_payload (estring __))
    expand

let () = Driver.register_transformation "reativa_jsx_ppx" ~extensions:[ extension ]

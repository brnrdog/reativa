type t = {
  pattern : string;
  pathname : string;
  params : (string * string) list;
}

let hex_value = function
  | '0' .. '9' as c -> Some (Char.code c - Char.code '0')
  | 'a' .. 'f' as c -> Some (Char.code c - Char.code 'a' + 10)
  | 'A' .. 'F' as c -> Some (Char.code c - Char.code 'A' + 10)
  | _ -> None

(* Percent-decode [%XX] escapes byte by byte.

   This is the *portable* decoder, and it is only fully correct where an OCaml
   string is a byte string — i.e. natively. [Char.chr] emits one string element
   per escape, which is a byte natively but a UTF-16 code unit under Melange
   and js_of_ocaml, where OCaml strings are JS strings. So "%C3%A9" decodes to
   the two bytes of UTF-8 "é" natively (correct) but to "Ã©" in a browser.

   No pure-OCaml decoder can be correct on both: producing "é" in a browser
   needs a string element above 255, which OCaml's [string]/[Char] API cannot
   express. Percent-decoding is therefore a backend concern — see
   {!Dom.decode_uri_component} and the [?decode] parameter of {!match_path},
   through which {!Router} supplies the browser's own [decodeURIComponent].

   Keeping this as the default means {!match_path} stays pure and natively
   testable. *)
let decode_component value =
  let len = String.length value in
  let buffer = Buffer.create len in
  let rec loop index =
    if index >= len then Buffer.contents buffer
    else
      match value.[index] with
      | '%' when index + 2 < len -> begin
        match (hex_value value.[index + 1], hex_value value.[index + 2]) with
        | Some hi, Some lo ->
          Buffer.add_char buffer (Char.chr ((hi * 16) + lo));
          loop (index + 3)
        | _ ->
          Buffer.add_char buffer value.[index];
          loop (index + 1)
      end
      | ch ->
        Buffer.add_char buffer ch;
        loop (index + 1)
  in
  loop 0

let split_path value =
  value |> String.split_on_char '/'
  |> List.filter (fun segment -> String.length segment > 0)

let add_param ~decode name value params = (name, decode value) :: params

(* [match_path ?decode pattern pathname] matches a concrete [pathname] against
   a route [pattern], capturing [:name] segments and a trailing [*] wildcard.

   [?decode] percent-decodes captured parameters. It defaults to
   {!decode_component}, which is correct for byte strings (natively) but
   mangles non-ASCII escapes where OCaml strings are JS strings — so {!Router}
   overrides it with the browser's [decodeURIComponent]. Matching itself is
   unaffected: only captured values are decoded, and pattern/segment
   comparison is exact. *)
let match_path ?(decode = decode_component) pattern pathname =
  let rec loop params pattern_segments path_segments =
    match (pattern_segments, path_segments) with
    | [], [] -> Some (List.rev params)
    | [ "*" ], rest ->
      Some (List.rev (add_param ~decode "*" (String.concat "/" rest) params))
    | pattern :: patterns, value :: values when String.length pattern > 0 && pattern.[0] = ':' ->
      let name = String.sub pattern 1 (String.length pattern - 1) in
      if name = "" then None else loop (add_param ~decode name value params) patterns values
    | pattern :: patterns, value :: values when pattern = value -> loop params patterns values
    | _ -> None
  in
  match loop [] (split_path pattern) (split_path pathname) with
  | None -> None
  | Some params -> Some { pattern; pathname; params }

let param route_match name = List.assoc_opt name route_match.params

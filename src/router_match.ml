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

let add_param name value params = (name, decode_component value) :: params

let match_path pattern pathname =
  let rec loop params pattern_segments path_segments =
    match (pattern_segments, path_segments) with
    | [], [] -> Some (List.rev params)
    | [ "*" ], rest -> Some (List.rev (add_param "*" (String.concat "/" rest) params))
    | pattern :: patterns, value :: values when String.length pattern > 0 && pattern.[0] = ':' ->
      let name = String.sub pattern 1 (String.length pattern - 1) in
      if name = "" then None else loop (add_param name value params) patterns values
    | pattern :: patterns, value :: values when pattern = value -> loop params patterns values
    | _ -> None
  in
  match loop [] (split_path pattern) (split_path pathname) with
  | None -> None
  | Some params -> Some { pattern; pathname; params }

let param route_match name = List.assoc_opt name route_match.params

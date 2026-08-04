open Reativa

let failures = ref 0
let total = ref 0

let check name cond =
  incr total;
  if cond then Printf.printf "  ok   %s\n" name
  else begin
    incr failures;
    Printf.printf "  FAIL %s\n" name
  end

let check_param name matched key want =
  check name (Router_match.param matched key = Some want)

let test_match_path () =
  print_endline "Router.match_path";
  check "root matches root" (Option.is_some (Router_match.match_path "/" "/"));
  check "root does not match nested" (Option.is_none (Router_match.match_path "/" "/docs"));
  begin
    match Router_match.match_path "/users/:id" "/users/42" with
    | Some matched ->
      check_param "captures dynamic segment" matched "id" "42";
      check "preserves pattern" (matched.pattern = "/users/:id")
    | None -> check "captures dynamic segment" false
  end;
  begin
    match Router_match.match_path "/files/*" "/files/a/b/c.txt" with
    | Some matched -> check_param "captures wildcard rest" matched "*" "a/b/c.txt"
    | None -> check "captures wildcard rest" false
  end;
  begin
    match Router_match.match_path "/search/:term" "/search/hello%20world" with
    | Some matched -> check_param "decodes params" matched "term" "hello world"
    | None -> check "decodes params" false
  end;
  check "static mismatch rejected" (Option.is_none (Router_match.match_path "/posts/:id" "/users/42"));
  check "extra segment rejected" (Option.is_none (Router_match.match_path "/posts/:id" "/posts/42/edit"))

(* Percent-decoding of captured parameters.

   The escapes below are all ASCII, so the default byte-level decoder and the
   browser's decodeURIComponent agree on them — these assertions hold on every
   backend. Non-ASCII is deliberately not asserted here: see
   [test_decode_is_injectable] and the note in router_match.ml. *)
let test_decode_component () =
  print_endline "Router.match_path (decoding)";
  let param_of pattern path key =
    match Router_match.match_path pattern path with
    | Some matched -> Router_match.param matched key
    | None -> None
  in
  check "decodes %20 to a space" (param_of "/s/:q" "/s/a%20b" "q" = Some "a b");
  check "decodes an encoded slash" (param_of "/s/:q" "/s/a%2Fb" "q" = Some "a/b");
  check "decodes an encoded percent" (param_of "/s/:q" "/s/100%25" "q" = Some "100%");
  check "decodes lowercase hex" (param_of "/s/:q" "/s/a%2fb" "q" = Some "a/b");
  (* Malformed escapes are passed through rather than raising: a bad URL should
     not take down the router. *)
  check "passes through a non-hex escape" (param_of "/s/:q" "/s/a%ZZb" "q" = Some "a%ZZb");
  check "passes through a truncated escape" (param_of "/s/:q" "/s/ab%2" "q" = Some "ab%2");
  check "passes through a trailing percent" (param_of "/s/:q" "/s/ab%" "q" = Some "ab%");
  check "decodes the wildcard capture"
    (param_of "/files/*" "/files/my%20dir/a.txt" "*" = Some "my dir/a.txt");
  (* Only captured values are decoded — matching compares raw segments. *)
  check "does not decode before matching"
    (Option.is_none (Router_match.match_path "/a b" "/a%20b"))

(* The decoder is a parameter precisely because percent-decoding is not
   representable portably in OCaml: the default is correct for byte strings
   (natively), while Router supplies the browser's decodeURIComponent, which is
   the only thing that decodes non-ASCII correctly where OCaml strings are JS
   strings. Assert the seam itself, which is testable on any backend. *)
let test_decode_is_injectable () =
  print_endline "Router.match_path (~decode)";
  let shouty value = String.uppercase_ascii value in
  begin
    match Router_match.match_path ~decode:shouty "/s/:q" "/s/hello" with
    | Some matched -> check_param "uses the supplied decoder" matched "q" "HELLO"
    | None -> check "uses the supplied decoder" false
  end;
  begin
    match Router_match.match_path ~decode:shouty "/files/*" "/files/a/b" with
    | Some matched -> check_param "uses it for the wildcard too" matched "*" "A/B"
    | None -> check "uses it for the wildcard too" false
  end;
  (* Natively an OCaml string is a byte string, so the default decoder yields
     the UTF-8 *bytes* of "é" — which is the correct native answer, and exactly
     why browsers need their own decoder instead of this one. *)
  begin
    match Router_match.match_path "/s/:q" "/s/caf%C3%A9" with
    | Some matched ->
      check "default decoder yields UTF-8 bytes natively"
        (Router_match.param matched "q" = Some "caf\xc3\xa9")
    | None -> check "default decoder yields UTF-8 bytes natively" false
  end

let () =
  test_match_path ();
  test_decode_component ();
  test_decode_is_injectable ();
  Printf.printf "\n%d/%d router checks passed\n" (!total - !failures) !total;
  if !failures > 0 then exit 1

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

let () =
  test_match_path ();
  Printf.printf "\n%d/%d router checks passed\n" (!total - !failures) !total;
  if !failures > 0 then exit 1

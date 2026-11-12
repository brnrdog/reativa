(* The benchmark's deterministic row data, ported from shared/data.js.

   Same word lists, same xorshift32 sequence, same id counter, so every app
   renders byte-identical labels. The arithmetic is written to give the same
   result whether [int] has 31/32 bits (Melange, js_of_ocaml) or 63 (native):
   [u32] masks to 32 bits where ints are wider and is the identity where they
   are not, and [umod] reduces the unsigned value in two 16-bit halves so a
   negative 32-bit int is never fed to [mod]. *)

let adjectives =
  [| "pretty"; "large"; "big"; "small"; "tall"; "short"; "long"; "handsome"; "plain";
     "quaint"; "clean"; "elegant"; "easy"; "angry"; "crazy"; "helpful"; "mushy"; "odd";
     "unsightly"; "adorable"; "important"; "inexpensive"; "cheap"; "expensive"; "fancy" |]

let colours =
  [| "red"; "yellow"; "blue"; "green"; "pink"; "brown"; "purple"; "brown"; "white";
     "black"; "orange" |]

let nouns =
  [| "table"; "chair"; "house"; "bbq"; "desk"; "car"; "pony"; "cookie"; "sandwich";
     "burger"; "pizza"; "mouse"; "keyboard" |]

let seed = 0x2545f491
let state = ref seed
let next_id = ref 1
(* 2^32 - 1 with 63-bit ints, -1 (all bits) with 32-bit ones; spelled as a
   shift so no backend sees an out-of-range literal. *)
let mask32 = ((1 lsl 31) lsl 1) - 1
let u32 x = x land mask32

let umod x m =
  let hi = (x lsr 16) land 0xFFFF and lo = x land 0xFFFF in
  ((hi mod m * (65536 mod m)) + lo) mod m

let next_random max =
  let s = !state in
  let s = u32 (s lxor (s lsl 13)) in
  let s = s lxor (s lsr 17) in
  let s = u32 (s lxor (s lsl 5)) in
  state := s;
  umod s max

let reset () =
  state := seed;
  next_id := 1

type raw = { id : int; label : string }

let build count =
  List.init count (fun _ ->
    let a = adjectives.(next_random (Array.length adjectives)) in
    let c = colours.(next_random (Array.length colours)) in
    let n = nouns.(next_random (Array.length nouns)) in
    let id = !next_id in
    incr next_id;
    { id; label = a ^ " " ^ c ^ " " ^ n })

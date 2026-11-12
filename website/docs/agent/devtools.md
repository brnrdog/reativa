# Devtools and reativa-lens

## Summary

`Reativa.Devtools` records what the reactive graph does — writes, recomputes, effect runs, creations, disposals — and explains why a node changed. `reativa-lens` drives a compiled app under jsdom and reports per interaction; it is also an MCP server for agents.

## Availability

New in 2.0.

## Rules

1. Call `Devtools.install ()` before creating what you want to see; nodes created earlier are not tracked.
2. Until installed, the cost is one boolean test per instrumentation point; apps that never reference `Devtools` do not ship it.
3. Name signals (`~name`) to read reports; unnamed nodes appear by id.
4. For reativa-lens the app must also call `Devtools.expose ()` and mount into `<div id="app">`.

## API

```ocaml
Devtools.install : ?history:int -> unit -> unit
Devtools.record : (unit -> unit) -> Devtools.trace        (* events + counts *)
Devtools.why : int -> Devtools.cause option               (* chain back to the write *)
Devtools.effects_writing : Dom.t -> (int * string) list
Devtools.writers_of : Dom.t -> int list
Devtools.snapshot / inspect / history / subscribe / leaks / expose
```

```
reativa-lens run app.bc.js --act "click #inc" --act "type #name Ada" --why "#greeting"
reativa-lens mcp      # tool: reativa_lens_run {bundle, actions, why, snapshot}
```

## Patterns

Assert the cost of an interaction in a test:

```ocaml
let trace = Devtools.record (fun () -> Signal.set count 1) in
assert (trace.counts.runs = 1)
```

## Verify

`reativa-lens run` exits 1 if the page raised an error; every report ends with `Devtools.leaks`.

## Related

signals.md, ownership.md

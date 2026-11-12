# reativa-lens

Drive a Reativa app headlessly and see, for every interaction, what it wrote,
what recomputed and ran, which DOM nodes changed, and why an element shows
what it shows. A command-line tool for people and an MCP server for coding
agents, both over [`Reativa.Devtools`](../src/devtools.mli).

```
$ reativa-lens run _build/default/app.bc.js --act "click #inc" --act "click #inc" --why "#value"
> click #inc
  1 write(s) (count=1), 1 recompute(s), 1 effect run(s), 0 created, 0 disposed
  DOM: p#value text
> click #inc
  1 write(s) (count=2), 1 recompute(s), 1 effect run(s), 0 created, 0 disposed
  DOM: p#value text
why #value:
  text <- effect #4
    computed label (recomputed)
    <- signal count (written = 2)
no leaks: every live effect reads something
```

## Preparing the app

The lens loads the **compiled** app — a Melange ES module entry
(`_build/default/.../output/.../app.js`) or a js_of_ocaml script
(`app.bc.js`) — into a jsdom page with an empty `<div id="app">`. The app
installs and exposes the devtools before it mounts:

```ocaml
let () =
  Reativa.Devtools.install ();
  Reativa.Devtools.expose ();
  Reativa.View.mount_by_id "app" app
```

Name the signals you want to read about (`Signal.make ~name:"count" 0`,
`Computed.make ~name:"label" ...`); unnamed ones appear by id. A dev-only
entry point is a good place for these two lines, so production bundles leave
the devtools out.

## CLI

```
reativa-lens run <bundle> [--act "<action>"]... [--why <selector>]... [--snapshot] [--json] [--root <id>]
reativa-lens mcp
```

| Action | Does |
| --- | --- |
| `click <selector>` | dispatches a bubbling click |
| `type <selector> <text>` | sets `value`, dispatches `input` and `change` |
| `key <selector> <Key>` | dispatches a `keydown` with that key |
| `wait <ms>` | lets timers and promises run |

`--why` explains each selector after the actions: the effects writing the
element (or its text), and the chain back to the signal write that produced
the current value. `--snapshot` lists the live signals and computeds with
their subscriber counts. Every report ends with the leak check: effects that
read nothing and so can never run again. `--json` prints the raw report. The
exit status is 1 when the page raised an error.

## MCP server

`reativa-lens mcp` serves one tool, `reativa_lens_run`, over stdio (newline-
delimited JSON-RPC), with the same inputs as `run`: `bundle`, `actions`,
`why`, `snapshot`, `root`. Register it with your agent, for example:

```json
{ "mcpServers": { "reativa-lens": { "command": "node", "args": ["<repo>/lens/bin/reativa-lens.mjs", "mcp"] } } }
```

## Tests

```sh
npm --prefix lens install
REATIVA_JSOO=enabled opam exec -- dune build lens/test/fixture/app.bc.js
node lens/test/run.mjs
```

`npm run lens:test` in the repository root does all three; CI runs it in the
js_of_ocaml job.

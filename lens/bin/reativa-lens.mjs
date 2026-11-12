#!/usr/bin/env node
// reativa-lens: drive a Reativa app headlessly and report what happened.
//
//   reativa-lens run <bundle> [--act "<action>"]... [--why <selector>]... [--snapshot] [--json]
//   reativa-lens mcp
//
// <bundle> is the compiled app: a Melange ES module entry (output/.../app.js)
// or a js_of_ocaml script (app.bc.js). The app must call
// Reativa.Devtools.install () and Reativa.Devtools.expose () before it mounts,
// and mounts into <div id="app"> (--root <id> to change).
//
// Actions: click <selector> | type <selector> <text> | key <selector> <Key> | wait <ms>

import { lens } from "../src/api.mjs";
import { serve } from "../src/mcp.mjs";

const USAGE = `usage:
  reativa-lens run <bundle> [--act "<action>"]... [--why <selector>]... [--snapshot] [--json] [--root <id>]
  reativa-lens mcp

actions: click <selector> | type <selector> <text> | key <selector> <Key> | wait <ms>`;

const [command, ...args] = process.argv.slice(2);

if (command === "mcp") {
  serve();
} else if (command === "run" && args.length > 0) {
  const options = { bundle: args[0], actions: [], why: [] };
  let json = false;
  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--act") options.actions.push(args[++i]);
    else if (arg === "--why") options.why.push(args[++i]);
    else if (arg === "--snapshot") options.snapshot = true;
    else if (arg === "--root") options.rootId = args[++i];
    else if (arg === "--json") json = true;
    else {
      console.error(`unknown option ${arg}\n\n${USAGE}`);
      process.exit(2);
    }
  }
  try {
    const { report, text } = await lens(options);
    console.log(json ? JSON.stringify(report, null, 2) : text);
    process.exit(report.errors.length ? 1 : 0);
  } catch (e) {
    console.error(`reativa-lens: ${e.message}`);
    process.exit(1);
  }
} else {
  console.error(USAGE);
  process.exit(command ? 2 : 0);
}

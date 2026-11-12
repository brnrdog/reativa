// Drives the fixture app through the CLI and the MCP server and checks the
// reports. Needs the fixture built first:
//   REATIVA_JSOO=enabled dune build lens/test/fixture/app.bc.js
// then: node lens/test/run.mjs [path to app.bc.js]

import { spawn, spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const bin = resolve(here, "../bin/reativa-lens.mjs");
const bundle = resolve(process.argv[2] ?? resolve(here, "../../_build/default/lens/test/fixture/app.bc.js"));

let failures = 0;
const check = (name, cond, detail = "") => {
  console.log(`${cond ? "ok" : "not ok"} - ${name}${cond ? "" : `\n${detail}`}`);
  if (!cond) failures++;
};

// CLI
const cli = spawnSync(
  process.execPath,
  [bin, "run", bundle, "--act", "click #inc", "--act", "click #toggle", "--why", "#value", "--snapshot"],
  { encoding: "utf8" },
);
const out = cli.stdout;
check("cli exits 0", cli.status === 0, cli.stderr + out);
check("reports the write", out.includes("1 write(s) (count=1)"), out);
check("reports the recompute and the run", /1 recompute\(s\), 1 effect run\(s\)/.test(out), out);
check("reports the DOM change", out.includes("p#value text"), out);
check("the toggle creates the panel", out.includes("> click #toggle") && out.includes("body children") === false, out);
check("why names the chain", /text <- effect #\d+\n\s+computed label \(recomputed\)\n\s+<- signal count \(written = 1\)/.test(out), out);
check("snapshot lists the signals", out.includes("signal count: ") && out.includes("computed label: "), out);

const json = spawnSync(process.execPath, [bin, "run", bundle, "--act", "click #inc", "--json"], { encoding: "utf8" });
const report = JSON.parse(json.stdout);
check("json report", report.acts[0].events.some((e) => e.type === "written" && e.name === "count"), json.stdout);

// MCP
const server = spawn(process.execPath, [bin, "mcp"], { stdio: ["pipe", "pipe", "inherit"] });
const responses = [];
let buffer = "";
server.stdout.on("data", (chunk) => {
  buffer += chunk;
  let i;
  while ((i = buffer.indexOf("\n")) >= 0) {
    responses.push(JSON.parse(buffer.slice(0, i)));
    buffer = buffer.slice(i + 1);
  }
});
const send = (m) => server.stdin.write(`${JSON.stringify(m)}\n`);
send({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18" } });
send({ jsonrpc: "2.0", method: "notifications/initialized" });
send({ jsonrpc: "2.0", id: 2, method: "tools/list" });
send({
  jsonrpc: "2.0",
  id: 3,
  method: "tools/call",
  params: { name: "reativa_lens_run", arguments: { bundle, actions: ["click #inc"], why: ["#value"] } },
});
const deadline = Date.now() + 15000;
while (responses.length < 3 && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
server.kill();
const byId = Object.fromEntries(responses.map((r) => [r.id, r]));
check("mcp initialize", byId[1]?.result?.serverInfo?.name === "reativa-lens", JSON.stringify(byId[1]));
check("mcp lists the tool", byId[2]?.result?.tools?.[0]?.name === "reativa_lens_run", JSON.stringify(byId[2]));
const text = byId[3]?.result?.content?.[0]?.text ?? "";
check("mcp runs the lens", text.includes("count=1") && text.includes("signal count (written = 1)"), text);

console.log(failures ? `\n${failures} failure(s)` : "\nlens ok");
process.exit(failures ? 1 : 0);

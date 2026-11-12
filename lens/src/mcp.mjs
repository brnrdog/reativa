// The MCP server: the same lens as the CLI, as tools an agent can call.
// Newline-delimited JSON-RPC 2.0 over stdio.

import { createInterface } from "node:readline";
import { lens } from "./api.mjs";

const TOOLS = [
  {
    name: "reativa_lens_run",
    description:
      "Load a compiled Reativa app (a Melange ES module entry or a js_of_ocaml .bc.js) under jsdom, " +
      "perform actions, and report for each what was written, recomputed and run and which DOM nodes " +
      "changed; then explain, for each selector in `why`, which signal write produced its current value. " +
      "The app must call Reativa.Devtools.install () and expose () before mounting into <div id=\"app\">.",
    inputSchema: {
      type: "object",
      properties: {
        bundle: { type: "string", description: "Path to the compiled app entry" },
        actions: {
          type: "array",
          items: { type: "string" },
          description: "click <selector> | type <selector> <text> | key <selector> <Key> | wait <ms>",
        },
        why: { type: "array", items: { type: "string" }, description: "CSS selectors to explain" },
        snapshot: { type: "boolean", description: "Also list the live signals and computeds" },
        root: { type: "string", description: "Id of the mount element (default app)" },
      },
      required: ["bundle"],
    },
  },
];

function reply(id, result) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, result })}\n`);
}

function fail(id, code, message) {
  process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } })}\n`);
}

async function handle(message) {
  const { id, method, params } = message;
  if (method === "initialize") {
    return reply(id, {
      protocolVersion: params?.protocolVersion ?? "2025-06-18",
      capabilities: { tools: {} },
      serverInfo: { name: "reativa-lens", version: "0.1.0" },
    });
  }
  if (method === "notifications/initialized" || id === undefined) return;
  if (method === "ping") return reply(id, {});
  if (method === "tools/list") return reply(id, { tools: TOOLS });
  if (method === "tools/call") {
    const { name, arguments: input = {} } = params ?? {};
    if (name !== "reativa_lens_run") return fail(id, -32602, `unknown tool ${name}`);
    try {
      const { text } = await lens({
        bundle: input.bundle,
        actions: input.actions ?? [],
        why: input.why ?? [],
        snapshot: Boolean(input.snapshot),
        rootId: input.root,
      });
      return reply(id, { content: [{ type: "text", text }] });
    } catch (e) {
      return reply(id, { content: [{ type: "text", text: e.message }], isError: true });
    }
  }
  return fail(id, -32601, `method not found: ${method}`);
}

export function serve() {
  const lines = createInterface({ input: process.stdin });
  // One request at a time: each run owns the process-wide jsdom globals.
  let queue = Promise.resolve();
  lines.on("line", (line) => {
    if (!line.trim()) return;
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return fail(null, -32700, "parse error");
    }
    queue = queue.then(() => handle(message)).catch((e) => fail(message.id ?? null, -32603, e.message));
  });
}

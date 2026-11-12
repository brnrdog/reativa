// One request in, one report out: used by the CLI and the MCP server.

import { openSession } from "./session.mjs";
import { formatAct, formatLeaks, formatSnapshot, formatWhy } from "./format.mjs";

export async function lens({ bundle, actions = [], why = [], snapshot = false, rootId, html }) {
  const session = await openSession(bundle, { rootId, html });
  try {
    const results = [];
    for (const action of actions) results.push(await session.act(action));
    const report = {
      acts: results,
      why: why.map((selector) => ({ selector, bindings: session.whyElement(selector) })),
      snapshot: snapshot ? session.snapshot() : null,
      leaks: session.leaks(),
      errors: session.errors,
    };
    const text = [
      ...results.map(formatAct),
      ...report.why.map((w) => formatWhy(w.selector, w.bindings)),
      ...(snapshot ? [formatSnapshot(report.snapshot)] : []),
      formatLeaks(report.leaks),
      ...(report.errors.length ? [`errors: ${report.errors.join("; ")}`] : []),
    ].join("\n");
    return { report, text };
  } finally {
    session.close();
  }
}

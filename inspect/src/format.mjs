// Plain-text reports for people (the CLI) and agents (the MCP server).

const label = (n) => (n.name ? `${n.kind} ${n.name}` : `${n.kind} #${n.id}`);

export function formatAct({ action, events, changed }) {
  const count = (type) => events.filter((e) => e.type === type).length;
  const writes = events
    .filter((e) => e.type === "written")
    .map((e) => `${e.name ?? `#${e.id}`}=${e.value}`);
  const lines = [`> ${action}`];
  lines.push(
    `  ${count("written")} write(s)${writes.length ? ` (${writes.join(", ")})` : ""}, ` +
      `${count("recomputed")} recompute(s), ${count("ran")} effect run(s), ` +
      `${count("created")} created, ${count("disposed")} disposed`,
  );
  lines.push(changed.length ? `  DOM: ${changed.join("; ")}` : "  DOM: no change");
  return lines.join("\n");
}

export function formatCause(cause, indent = "  ") {
  const out = [];
  for (let c = cause; c; c = c.because) {
    const verb = c.action === "written" ? `written${c.value !== null ? ` = ${c.value}` : ""}` : c.action;
    out.push(`${indent}${out.length ? "<- " : ""}${label(c.node)} (${verb})`);
  }
  return out.join("\n");
}

export function formatWhy(selector, bindings) {
  if (bindings.length === 0) return `why ${selector}: no reactive binding writes this element`;
  return [
    `why ${selector}:`,
    ...bindings.map((b) => `  ${b.writes} <- effect #${b.effect}\n${formatCause(b.cause?.because, "    ")}`),
  ].join("\n");
}

export function formatSnapshot(nodes) {
  const by = (k) => nodes.filter((n) => n.kind === k);
  const lines = [`${by("signal").length} signals, ${by("computed").length} computeds, ${by("effect").length} effects`];
  for (const n of nodes.filter((n) => n.kind !== "effect")) {
    lines.push(`  ${label(n)}: ${n.subscribers} subscriber(s)`);
  }
  return lines.join("\n");
}

export function formatLeaks(leaks) {
  return leaks.length === 0
    ? "no leaks: every live effect reads something"
    : `${leaks.length} effect(s) read nothing and can never run again: ${leaks.map(label).join(", ")}`;
}

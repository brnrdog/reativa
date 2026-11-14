// Publishes the agent layer of the docs next to the built site:
//   _site/docs/<slug>.md   one Markdown page per registry entry
//   _site/llms.txt         an index of them, for agents (llmstxt.org)
// Run after `vite build` (npm run docs:build does).

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pages, VERSION } from "../website/docs.pages.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = resolve(root, process.argv[2] ?? "_site");
const base = process.env.DOCS_BASE_URL ?? "https://brnrdog.github.io/reativa";

mkdirSync(join(out, "docs"), { recursive: true });
for (const page of pages) {
  const body = readFileSync(join(root, "website", "docs", "agent", page.file), "utf8");
  writeFileSync(join(out, "docs", `${page.slug}.md`), body);
}

const sections = [...new Set(pages.map((p) => p.section))];
const lines = [
  "# reativa",
  "",
  `> Fine-grained reactive web interfaces for OCaml and ReasonML (version ${VERSION}). Signals drive in-place DOM updates; no virtual DOM. Compiles with Melange or js_of_ocaml.`,
  "",
  "These pages are the agent layer of the documentation: complete rules, APIs, patterns, anti-patterns and edge cases, with code that compiles against the current release. Read the Glossary first.",
  "",
];
for (const section of sections) {
  lines.push(`## ${section}`, "");
  for (const p of pages.filter((p) => p.section === section)) {
    lines.push(`- [${p.title}](${base}/docs/${p.slug}.md): ${p.summary}${p.isNew ? ` (new in ${VERSION})` : ""}`);
  }
  lines.push("");
}
writeFileSync(join(out, "llms.txt"), lines.join("\n"));
console.log(`wrote ${pages.length} agent pages and llms.txt into ${out}`);

// Lets every route of the site load directly on GitHub Pages, which serves
// files and knows nothing of the app's router. Run after `vite build`
// (npm run docs:build does):
//
//   _site/<route>.html and _site/<route>/index.html   copies of index.html,
//       so /reativa/docs/learn/signals answers 200 with the app, with or
//       without a trailing slash
//   _site/404.html   the app again, for any other path: it shows its own
//       "not found" page
//
// The routes come from website/docs.pages.mjs, the same registry the app's
// sidebar and routes are generated from.

import { copyFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { docs, otherRoutes } from "../website/docs.pages.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = resolve(root, process.argv[2] ?? "_site");
const index = join(out, "index.html");
if (!existsSync(index)) {
  console.error(`build-site-routes: ${index} not found; run vite build first`);
  process.exit(1);
}

const routes = [...otherRoutes, ...docs.flatMap((section) => section.pages.map((page) => page.path))];
let written = 0;
for (const route of routes) {
  if (route === "/") continue;
  const rel = route.replace(/^\//, "");
  for (const file of [join(out, `${rel}.html`), join(out, rel, "index.html")]) {
    mkdirSync(dirname(file), { recursive: true });
    copyFileSync(index, file);
    written += 1;
  }
}
copyFileSync(index, join(out, "404.html"));
console.log(`wrote ${written} route pages and 404.html into ${out}`);

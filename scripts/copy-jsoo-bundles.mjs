// Copy the js_of_ocaml demo bundles out of _build and next to their index.html.
//
// The demos load `./todo.bundle.js` / `./router_demo.bundle.js` as plain
// scripts, while dune writes `*.bc.js` under _build — without this copy the
// served page never sees a rebuild.
//
// Usage:
//   node scripts/copy-jsoo-bundles.mjs            copy once
//   node scripts/copy-jsoo-bundles.mjs --watch    copy, then re-copy on change

import { copyFile, mkdir, stat } from "node:fs/promises";
import { watch } from "node:fs";
import { dirname, relative, resolve } from "node:path";

const buildDir = resolve("_build/default/examples/jsoo");

const bundles = [
  { from: resolve(buildDir, "todo.bc.js"), to: resolve("examples/jsoo/todo.bundle.js") },
  {
    from: resolve(buildDir, "router_demo.bc.js"),
    to: resolve("examples/jsoo/router/router_demo.bundle.js"),
  },
];

const watchMode = process.argv.slice(2).includes("--watch");

async function copyBundle({ from, to }) {
  try {
    await mkdir(dirname(to), { recursive: true });
    await copyFile(from, to);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") {
      // In watch mode the first build may not have produced it yet.
      if (!watchMode) {
        console.error(`Missing ${relative(process.cwd(), from)} — run the dune build first.`);
      }
      return false;
    }

    throw error;
  }
}

async function copyAll() {
  const results = await Promise.all(bundles.map(copyBundle));
  return results.every(Boolean);
}

const copiedEverything = await copyAll();

if (!watchMode) {
  process.exit(copiedEverything ? 0 : 1);
}

// Debounced: dune rewrites a bundle in several steps, and fs.watch reports each
// of them.
let pending = null;

function scheduleCopy() {
  clearTimeout(pending);
  pending = setTimeout(() => {
    copyAll().catch((error) => console.error(`Copy failed: ${error.message}`));
  }, 100);
}

async function watchBuildDir() {
  try {
    await stat(buildDir);
  } catch {
    // dune has not created it yet; poll until it appears.
    setTimeout(watchBuildDir, 500);
    return;
  }

  const watcher = watch(buildDir, (_event, filename) => {
    if (filename && filename.toString().endsWith(".bc.js")) {
      scheduleCopy();
    }
  });

  watcher.on("error", (error) => {
    console.error(`Unable to watch ${relative(process.cwd(), buildDir)}: ${error.message}`);
  });

  console.log(`Watching ${relative(process.cwd(), buildDir)} for js_of_ocaml bundles.`);
}

await watchBuildDir();

/*
 * Builds every benchmark app into `dist/<app>` with production settings.
 *
 *   reativa       the OCaml app compiled by Melange, bundled with Vite
 *   reativa-jsoo  the same OCaml app linked by js_of_ocaml (release profile)
 *   xote          the ReScript app in apps/xote, against xote from npm
 *   solid         the SolidJS app in apps/solid
 *
 * The JS bundles all go through the same Vite version, target and minifier so
 * the payload comparison only reflects framework code. The js_of_ocaml script
 * is minified by Vite's minifier too (see buildJsoo).
 *
 * Usage:
 *   node build.mjs [--apps reativa,solid] [--root <reativa checkout>] [--as <name>]
 *
 * `--root` builds the reativa apps from another checkout (CI uses it for the
 * base commit) and `--as` renames the output directory, e.g. `reativa-base`.
 * The reativa apps need the dune build first: `npm run build` in the
 * checkout's benchmarks/ does it.
 */

import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "vite";

const here = path.dirname(fileURLToPath(import.meta.url));

const TARGET = "es2022";

export const APPS = ["reativa", "reativa-jsoo", "xote", "solid"];

async function pluginsFor(app) {
  if (app === "solid") {
    const { default: solid } = await import("vite-plugin-solid");
    return [solid()];
  }
  return [];
}

const viteOutput = {
  entryFileNames: "assets/[name].js",
  chunkFileNames: "assets/[name].js",
  assetFileNames: "assets/[name][extname]",
};

async function viteBuild({ root, outDir, plugins = [], alias = {} }) {
  await rm(outDir, { recursive: true, force: true });
  await build({
    root,
    base: "./",
    logLevel: "warn",
    plugins,
    resolve: { alias },
    define: { "process.env.NODE_ENV": '"production"' },
    server: { fs: { strict: false } },
    build: {
      outDir,
      emptyOutDir: true,
      target: TARGET,
      minify: true,
      sourcemap: false,
      modulePreload: { polyfill: false },
      reportCompressedSize: false,
      rollupOptions: { output: viteOutput },
    },
  });
}

/* Run dune in a reativa checkout. Release profile: js_of_ocaml only does
 * whole-program dead-code elimination there, and it matches what users ship. */
function dune(root, targets, env = {}) {
  const opamExec = process.env.REATIVA_NO_OPAM ? [] : ["opam", "exec", "--"];
  const [cmd, ...args] = [...opamExec, "dune", "build", "--profile", "release", ...targets];
  execFileSync(cmd, args, { cwd: root, stdio: "inherit", env: { ...process.env, ...env } });
}

async function buildReativa(root, name) {
  if (!process.env.REATIVA_SKIP_DUNE) dune(root, ["@benchmarks/apps/reativa/bench"]);
  const melangeOut = path.join(
    root,
    "_build/default/benchmarks/apps/reativa/output/benchmarks/apps/reativa/bench_app.js",
  );
  await viteBuild({
    root: path.join(here, "apps", "reativa"),
    outDir: path.join(here, "dist", name),
    alias: { "@reativa-bench-app": melangeOut },
  });
}

async function buildJsoo(root, name) {
  if (!process.env.REATIVA_SKIP_DUNE) {
    dune(root, ["benchmarks/apps/reativa/jsoo/bench_app.bc.js"], { REATIVA_JSOO: "enabled" });
  }
  const outDir = path.join(here, "dist", name);
  const assets = path.join(outDir, "assets");
  await rm(outDir, { recursive: true, force: true });
  await mkdir(assets, { recursive: true });

  const script = await readFile(
    path.join(root, "_build/default/benchmarks/apps/reativa/jsoo/bench_app.bc.js"),
    "utf8",
  );
  /* Same minifier as the Vite apps, so payload sizes compare like for like. */
  await writeFile(path.join(assets, "bench_app.js"), await minifyWithVite(script));
  await copyFile(path.join(here, "shared", "bench.css"), path.join(assets, "bench.css"));
  await copyFile(path.join(here, "apps", "reativa-jsoo", "index.html"), path.join(outDir, "index.html"));
}

/* Vite's library build doubles as a minifier for a prebuilt script. */
async function minifyWithVite(code) {
  const tmp = path.join(here, "dist", ".jsoo-minify");
  await rm(tmp, { recursive: true, force: true });
  await mkdir(tmp, { recursive: true });
  const entry = path.join(tmp, "entry.js");
  await writeFile(entry, code);
  await build({
    root: tmp,
    logLevel: "warn",
    build: {
      outDir: path.join(tmp, "out"),
      target: TARGET,
      minify: true,
      lib: { entry, formats: ["iife"], name: "ReativaBench", fileName: () => "out.js" },
      reportCompressedSize: false,
    },
  });
  const out = await readFile(path.join(tmp, "out", "out.js"), "utf8");
  await rm(tmp, { recursive: true, force: true });
  return out;
}

async function buildXote() {
  execFileSync("npx", ["rescript"], { cwd: here, stdio: "inherit" });
  await viteBuild({ root: path.join(here, "apps", "xote"), outDir: path.join(here, "dist", "xote") });
}

async function buildApp(app, { root, as }) {
  const name = as ?? app;
  if (app === "reativa") await buildReativa(root, name);
  else if (app === "reativa-jsoo") await buildJsoo(root, name);
  else if (app === "xote") await buildXote();
  else
    await viteBuild({
      root: path.join(here, "apps", app),
      outDir: path.join(here, "dist", name),
      plugins: await pluginsFor(app),
    });
  console.log(`built ${name}`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const flag = (name) => {
    const i = args.indexOf(name);
    return i === -1 ? undefined : args[i + 1];
  };
  const selected = flag("--apps")?.split(",") ?? APPS;
  const root = path.resolve(flag("--root") ?? path.join(here, ".."));
  const as = flag("--as");

  for (const app of selected) {
    if (!APPS.includes(app)) throw new Error(`Unknown app: ${app}`);
    await buildApp(app, { root, as: as && selected.length === 1 ? as : undefined });
  }
  console.log(`\nBuilt ${selected.join(", ")} into benchmarks/dist/`);
}

export { buildApp };

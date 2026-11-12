// Runs a compiled DOM test suite under jsdom.
//
//   node test/dom/run.mjs <compiled suite>
//
// The suite is the same OCaml source (test/dom/*.ml) compiled by one backend:
// Melange emits ES modules (loaded with import()), js_of_ocaml links one
// classic script (*.bc.js, evaluated as a script). Before loading it, this
// file installs a jsdom window as the global environment, and wraps the DOM
// methods the renderer calls so a test can count them (Probe.ops).
//
// The suite reports through globalThis.__reativaReport(failed, total) when its
// last test has finished; the process exits non-zero if anything failed, if a
// suite throws while loading, or if it never reports.

import { JSDOM } from "jsdom";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";
import vm from "node:vm";

const file = process.argv[2];
if (!file) {
  console.error("usage: node test/dom/run.mjs <compiled suite>");
  process.exit(2);
}

const dom = new JSDOM("<!doctype html><html><head></head><body></body></html>", {
  url: "http://localhost/",
  pretendToBeVisual: true,
});
const { window } = dom;

const globals = [
  "window", "document", "navigator", "location", "history",
  "Node", "Element", "HTMLElement", "SVGElement", "Text", "Comment",
  "DocumentFragment", "HTMLTemplateElement", "HTMLInputElement",
  "Event", "MouseEvent", "KeyboardEvent", "InputEvent", "CustomEvent",
  "PopStateEvent", "MutationObserver", "getComputedStyle",
  "requestAnimationFrame", "cancelAnimationFrame",
];
for (const name of globals) {
  if (window[name] !== undefined) {
    const value =
      typeof window[name] === "function" && /^[a-z]/.test(name)
        ? window[name].bind(window)
        : window[name];
    // Some (navigator, on newer Node) exist as getter-only globals already.
    Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
  }
}

// ----- DOM operation counters -----

const ops = Object.create(null);
const count = (name) => {
  ops[name] = (ops[name] || 0) + 1;
};
const wrapMethod = (proto, name) => {
  const original = proto[name];
  proto[name] = function (...args) {
    count(name);
    return original.apply(this, args);
  };
};
const wrapSetter = (proto, name, label) => {
  const desc = Object.getOwnPropertyDescriptor(proto, name);
  Object.defineProperty(proto, name, {
    ...desc,
    set(value) {
      count(label);
      desc.set.call(this, value);
    },
  });
};
wrapMethod(window.Node.prototype, "insertBefore");
wrapMethod(window.Node.prototype, "appendChild");
wrapMethod(window.Node.prototype, "removeChild");
wrapMethod(window.Node.prototype, "cloneNode");
wrapMethod(window.Element.prototype, "remove");
wrapMethod(window.CharacterData.prototype, "remove");
wrapMethod(window.Element.prototype, "setAttribute");
wrapMethod(window.Element.prototype, "removeAttribute");
wrapMethod(window.Document.prototype, "createElement");
wrapMethod(window.Document.prototype, "createElementNS");
wrapMethod(window.Document.prototype, "createTextNode");
wrapSetter(window.Node.prototype, "textContent", "textContent");
wrapSetter(window.CharacterData.prototype, "data", "data");

globalThis.__reativaOps = (name) => ops[name] || 0;
globalThis.__reativaResetOps = () => {
  for (const key of Object.keys(ops)) delete ops[key];
};

// ----- reporting -----

let reported = null;
const finished = new Promise((resolveFinished) => {
  globalThis.__reativaReport = (failed, total) => {
    reported = { failed, total };
    resolveFinished();
  };
});

let uncaught = 0;
const onUncaught = (err) => {
  uncaught += 1;
  console.error("not ok - uncaught:", err && err.stack ? err.stack : err);
};
process.on("uncaughtException", onUncaught);
process.on("unhandledRejection", onUncaught);
window.addEventListener("error", (event) => onUncaught(event.error ?? event.message));

// ----- load the suite -----

const path = resolve(file);
try {
  if (path.endsWith(".bc.js")) {
    // js_of_ocaml: one classic script. Evaluated in this context so it sees
    // the globals above, exactly as a <script> tag would. Its runtime detects
    // Node and expects a CommonJS `require` for its file-system device.
    globalThis.require = createRequire(path);
    vm.runInThisContext(readFileSync(path, "utf8"), { filename: path });
  } else {
    await import(pathToFileURL(path).href);
  }
} catch (err) {
  onUncaught(err);
}

const timeoutMs = Number(process.env.REATIVA_DOM_TEST_TIMEOUT_MS || 20000);
let timer;
await Promise.race([
  finished,
  new Promise((resolveTimeout) => {
    timer = setTimeout(resolveTimeout, timeoutMs);
  }),
]);
clearTimeout(timer);

if (reported === null) {
  console.error(`not ok - the suite never reported (timed out after ${timeoutMs} ms)`);
  process.exit(1);
}
const { failed, total } = reported;
console.log(`\n${total - failed}/${total} checks passed${uncaught ? `, ${uncaught} uncaught error(s)` : ""}`);
process.exit(failed > 0 || uncaught > 0 ? 1 : 0);

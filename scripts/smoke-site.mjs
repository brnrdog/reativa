// Smoke test for the documentation site: loads the compiled app (the Melange
// output, before bundling) into jsdom and visits every route.
//
//   node scripts/smoke-site.mjs [--snapshots]
//
// For each route it checks that nothing raised, that the right page rendered
// (the docs page title, the home hero, the examples, or the not-found page),
// and that the sidebar marks the current page. It also clicks an in-app link
// to check that the router follows it without a reload.
//
// With --snapshots, it prints each page's HTML, gzipped and base64-encoded,
// one line per route ("SNAPSHOT <route> <data>"), so the rendered pages can
// be looked at from a CI log.

import { JSDOM } from "jsdom";
import { gzipSync } from "node:zlib";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { docs, otherRoutes } from "../website/docs.pages.mjs";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const entry = join(root, "_build/default/website/src/output/website/src/app.js");
const snapshots = process.argv.includes("--snapshots");
const base = "/reativa";

const dom = new JSDOM('<!doctype html><html lang="en"><head><title>reativa</title></head><body><div id="app"></div></body></html>', {
  url: `http://localhost${base}/`,
  pretendToBeVisual: true,
});
const { window } = dom;

// What jsdom does not implement, and the page calls.
window.scrollTo = () => {};
window.Element.prototype.scrollIntoView = function () {};

const errors = [];
window.addEventListener("error", (event) => errors.push(String(event.error ?? event.message)));
process.on("uncaughtException", (error) => errors.push(String(error?.stack ?? error)));
process.on("unhandledRejection", (error) => errors.push(String(error?.stack ?? error)));

for (const name of [
  "window", "document", "navigator", "location", "history", "localStorage",
  "Node", "Element", "HTMLElement", "SVGElement", "Text", "Comment",
  "DocumentFragment", "HTMLTemplateElement", "HTMLInputElement",
  "Event", "MouseEvent", "KeyboardEvent", "InputEvent", "CustomEvent",
  "PopStateEvent", "MutationObserver", "getComputedStyle",
  "requestAnimationFrame", "cancelAnimationFrame",
]) {
  if (window[name] === undefined) continue;
  const value =
    typeof window[name] === "function" && /^[a-z]/.test(name) ? window[name].bind(window) : window[name];
  Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
}

// When a page fails, name the template it was filling: each template's
// skeleton is cloned right before its holes are resolved, so the last clone
// of a template's content is the one to look at.
const sources = new WeakMap();
const contentGetter = Object.getOwnPropertyDescriptor(window.HTMLTemplateElement.prototype, "content").get;
Object.defineProperty(window.HTMLTemplateElement.prototype, "content", {
  configurable: true,
  get() {
    const fragment = contentGetter.call(this);
    if (!sources.has(fragment)) sources.set(fragment, this.innerHTML);
    return fragment;
  },
});
let lastCloned = "";
const cloneNode = window.Node.prototype.cloneNode;
window.Node.prototype.cloneNode = function (deep) {
  const copy = cloneNode.call(this, deep);
  if (sources.has(this)) lastCloned = sources.get(this);
  return copy;
};

const tick = () => new Promise((resolve) => setTimeout(resolve, 0));
const $ = (selector) => window.document.querySelector(selector);
const text = (selector) => $(selector)?.textContent.trim() ?? "";

let failed = 0;
const check = (route, ok, what) => {
  if (!ok) {
    failed += 1;
    console.log(`FAIL ${route}: ${what}`);
  }
};

await import(pathToFileURL(entry).href);
await tick();

const visit = async (route) => {
  window.history.pushState({}, "", base + (route === "/" ? "/" : route));
  window.dispatchEvent(new window.PopStateEvent("popstate", { state: {} }));
  await tick();
  await tick();
};

const docPages = docs.flatMap((section) => section.pages);
const routes = [...otherRoutes, ...docPages.map((p) => p.path), "/docs/no-such-page"];

for (const route of routes) {
  const before = errors.length;
  await visit(route);
  const page = docPages.find((p) => p.path === route);
  if (page) {
    check(route, text(".docs-title").startsWith(page.heading ?? page.title), `title is "${text(".docs-title")}"`);
    check(route, text(".sidebar-link.is-active").startsWith(page.title), `active sidebar link is "${text(".sidebar-link.is-active")}"`);
    check(route, window.document.querySelectorAll(".docs-content > *").length > 1, "page body is empty");
    check(route, window.document.title.startsWith(page.heading ?? page.title), `document title is "${window.document.title}"`);
  } else if (route === "/") {
    check(route, text(".hero h1").startsWith("Web interfaces in OCaml"), "home hero missing");
  } else if (route === "/examples") {
    check(route, window.document.querySelectorAll(".example").length === 5, "expected 5 examples");
  } else {
    check(route, $(".not-found") !== null, "not-found page missing");
  }
  check(route, errors.length === before, `raised: ${errors.slice(before).join(" | ")}`);
  if (errors.length !== before) console.log(`last template cloned on ${route}: ${lastCloned}`);
  if (snapshots) {
    const html = gzipSync(window.document.documentElement.outerHTML).toString("base64");
    console.log(`SNAPSHOT ${route} ${html}`);
  }
}

// A click on an in-app link navigates without leaving the page.
await visit("/docs");
const link = $(`.sidebar-link[href="${base}/docs/learn/lists"]`);
check("click", link !== null, "no sidebar link to Lists");
if (link) {
  link.dispatchEvent(new window.MouseEvent("click", { bubbles: true, cancelable: true, button: 0 }));
  await tick();
  await tick();
  check("click", window.location.pathname === `${base}/docs/learn/lists`, `pathname is ${window.location.pathname}`);
  check("click", text(".docs-title").startsWith("Lists"), `title is "${text(".docs-title")}"`);
}

// The syntax switch flips every code panel on the page.
await visit("/docs/learn/signals");
const reasonBtn = [...window.document.querySelectorAll(".syntax-opt")].find((b) => b.textContent === "ReasonML");
reasonBtn?.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
await tick();
const panels = window.document.querySelectorAll(".docs-content .code-panel");
check("syntax", panels.length > 0 && [...panels].every((p) => p.classList.contains("is-reason")), "code panels did not switch to ReasonML");

if (errors.length) console.log(`errors:\n${errors.join("\n")}`);
console.log(`${routes.length} routes visited, ${failed} failure(s)`);
process.exit(failed || errors.length ? 1 : 0);

// A headless session: a jsdom window, the app bundle loaded into it, and the
// devtools the app exposed (Reativa.Devtools.expose) to read what happened.

import { JSDOM } from "jsdom";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import vm from "node:vm";

const GLOBALS = [
  "window", "document", "navigator", "location", "history",
  "Node", "Element", "HTMLElement", "SVGElement", "Text", "Comment",
  "DocumentFragment", "HTMLTemplateElement", "HTMLInputElement",
  "Event", "MouseEvent", "KeyboardEvent", "InputEvent", "CustomEvent",
  "PopStateEvent", "MutationObserver", "getComputedStyle",
  "requestAnimationFrame", "cancelAnimationFrame",
];

const tick = () => new Promise((r) => setTimeout(r, 0));

export async function openSession(bundle, { rootId = "app", html } = {}) {
  const page =
    html ?? `<!doctype html><html><head></head><body><div id="${rootId}"></div></body></html>`;
  const dom = new JSDOM(page, { url: "http://localhost/", pretendToBeVisual: true });
  const { window } = dom;
  for (const name of GLOBALS) {
    if (window[name] === undefined) continue;
    const value = typeof window[name] === "function" && /^[a-z]/.test(name) ? window[name].bind(window) : window[name];
    Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
  }
  const errors = [];
  window.addEventListener("error", (e) => errors.push(String(e.error ?? e.message)));

  const path = resolve(bundle);
  if (path.endsWith(".bc.js")) {
    globalThis.require = createRequire(path);
    vm.runInThisContext(readFileSync(path, "utf8"), { filename: path });
  } else {
    await import(pathToFileURL(path).href);
  }
  await tick();

  const devtools = globalThis.__reativaDevtools;
  if (!devtools) {
    throw new Error(
      "the app did not expose its devtools: call Reativa.Devtools.install () and Reativa.Devtools.expose () before mounting",
    );
  }
  const json = (s) => JSON.parse(s);
  const query = (selector) => {
    const el = window.document.querySelector(selector);
    if (!el) throw new Error(`no element matches ${selector}`);
    return el;
  };

  // Which DOM nodes an interaction changed: a MutationObserver over the body.
  const changes = [];
  const observer = new window.MutationObserver((records) => {
    for (const r of records) changes.push(r);
  });
  observer.observe(window.document.body, { subtree: true, childList: true, attributes: true, characterData: true });

  const describe = (node) => {
    const el = node.nodeType === 1 ? node : node.parentElement;
    if (!el) return "(detached)";
    let label = el.tagName.toLowerCase();
    if (el.id) label += `#${el.id}`;
    else if (el.classList.length) label += `.${[...el.classList].join(".")}`;
    return label;
  };

  async function perform(action) {
    const [verb, ...rest] = action.trim().split(/\s+/);
    if (verb === "click") {
      query(rest.join(" ")).dispatchEvent(new window.MouseEvent("click", { bubbles: true, button: 0 }));
    } else if (verb === "type") {
      // type <selector> <text...>
      const [selector, ...words] = rest;
      const el = query(selector);
      el.value = words.join(" ");
      el.dispatchEvent(new window.Event("input", { bubbles: true }));
      el.dispatchEvent(new window.Event("change", { bubbles: true }));
    } else if (verb === "key") {
      // key <selector> <Key>
      const [selector, key] = rest;
      query(selector).dispatchEvent(new window.KeyboardEvent("keydown", { key, bubbles: true }));
    } else if (verb === "wait") {
      await new Promise((r) => setTimeout(r, Number(rest[0] ?? 0)));
    } else {
      throw new Error(`unknown action "${action}" (use click, type, key or wait)`);
    }
    await tick();
  }

  return {
    window,
    errors,
    snapshot: () => json(devtools.snapshot()),
    leaks: () => json(devtools.leaks()),
    why: (id) => json(devtools.why(id)),
    whyElement: (selector) => json(devtools.whyElement(query(selector))),
    html: (selector) => (selector ? query(selector).outerHTML : window.document.body.innerHTML),

    // Run one action and report the events and DOM changes it caused.
    async act(action) {
      devtools.clearHistory();
      changes.length = 0;
      await perform(action);
      observer.takeRecords().forEach((r) => changes.push(r));
      const events = json(devtools.history());
      const changed = [];
      for (const r of changes) {
        const what =
          r.type === "attributes" ? `@${r.attributeName}` : r.type === "characterData" ? "text" : "children";
        const entry = `${describe(r.target)} ${what}`;
        if (!changed.includes(entry)) changed.push(entry);
      }
      return { action, events, changed };
    },
    close() {
      observer.disconnect();
      window.close();
    },
  };
}

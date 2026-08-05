// Playground editor.
//
// The editor is a textarea with a highlighted <pre> layered underneath it (the
// same highlighter the docs page uses). Running a program posts the buffer and
// the chosen backend to the dev server, which builds it and returns the
// JavaScript that run produced; the preview frame is reloaded and either
// imports it (Melange) or runs it as a script (js_of_ocaml). When the compile
// endpoint is missing — the published site is static — the page falls back to
// read-only.

import { highlightOCaml } from "../src/highlight.js";
import { EXAMPLES, DEFAULT_EXAMPLE } from "./examples.js";

const COMPILE_URL = "/__playground/compile";
const STATUS_URL = "/__playground/status";
const STORAGE_KEY = "reativa-playground-code";
const BACKEND_KEY = "reativa-playground-backend";

// Mirrors the server's table; the live list replaces it once the status probe
// answers, so the static site still shows what the backends are.
const FALLBACK_BACKENDS = [
  { id: "melange", label: "Melange" },
  { id: "jsoo", label: "js_of_ocaml" },
];

const source = document.getElementById("pg-source");
const highlight = document.getElementById("pg-highlight");
const gutter = document.getElementById("pg-gutter");
const examplesSelect = document.getElementById("pg-examples");
const backendsEl = document.getElementById("pg-backends");
const runButton = document.getElementById("pg-run");
const resetButton = document.getElementById("pg-reset");
const shareButton = document.getElementById("pg-share");
const statusEl = document.getElementById("pg-status");
const busyEl = document.getElementById("pg-busy");
const frame = document.getElementById("pg-frame");
const consoleEl = document.getElementById("pg-console");
const consoleCount = document.getElementById("pg-console-count");
const errorEl = document.getElementById("pg-error");
const errorTitle = document.getElementById("pg-error-title");
const errorBody = document.getElementById("pg-error-body");
const errorClose = document.getElementById("pg-error-close");
const offlineEl = document.getElementById("pg-offline");
const previewTab = document.getElementById("pg-tab-preview");
const consoleTab = document.getElementById("pg-tab-console");
const themeButton = document.getElementById("pg-theme");

let compileAvailable = true;
let backends = FALLBACK_BACKENDS;
let backend = FALLBACK_BACKENDS[0].id;
let running = false;
let pendingBundle = null;
let pendingRunId = null;
let lastResult = null;
let logs = [];

// ---------------------------------------------------------------------------
// Sharing: the program travels in the URL fragment, UTF-8 safe.
// ---------------------------------------------------------------------------

function encodeCode(code) {
  const bytes = new TextEncoder().encode(code);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeCode(encoded) {
  const padded = encoded.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (ch) => ch.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function codeFromHash() {
  const match = /(?:^|[#&])code=([^&]+)/.exec(window.location.hash);
  if (!match) return null;
  try {
    return decodeCode(match[1]);
  } catch (error) {
    return null;
  }
}

function initialCode() {
  const shared = codeFromHash();
  if (shared) return shared;
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) return stored;
  } catch (error) {
    /* private mode — fall through to the default example */
  }
  return DEFAULT_EXAMPLE.code;
}

function initialBackend() {
  const match = /(?:^|[#&])backend=([a-z_]+)/.exec(window.location.hash);
  if (match && FALLBACK_BACKENDS.some((item) => item.id === match[1])) {
    return match[1];
  }
  try {
    const stored = localStorage.getItem(BACKEND_KEY);
    if (stored && FALLBACK_BACKENDS.some((item) => item.id === stored)) return stored;
  } catch (error) {
    /* private mode — fall through to the default backend */
  }
  return FALLBACK_BACKENDS[0].id;
}

// ---------------------------------------------------------------------------
// Backend picker
// ---------------------------------------------------------------------------

function backendLabel(id) {
  const found = backends.find((item) => item.id === id);
  return found ? found.label : id;
}

function paintBackends() {
  backendsEl.replaceChildren(
    ...backends.map((item) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = item.id === backend ? "pg-seg-opt is-active" : "pg-seg-opt";
      // Nothing to compile with on the static site, so the picker only reports
      // which backends exist.
      button.disabled = !compileAvailable;
      button.textContent = item.label;
      button.setAttribute("aria-pressed", String(item.id === backend));
      button.addEventListener("click", () => selectBackend(item.id));
      return button;
    }),
  );
}

function selectBackend(id) {
  if (id === backend) return;
  backend = id;
  try {
    localStorage.setItem(BACKEND_KEY, id);
  } catch (error) {
    /* the choice just won't survive a reload */
  }
  paintBackends();
  if (compileAvailable) run();
}

// ---------------------------------------------------------------------------
// Editor
// ---------------------------------------------------------------------------

function paint() {
  // A trailing newline keeps the last line's highlight box from collapsing.
  highlight.replaceChildren(highlightOCaml(source.value + "\n"));

  const lines = source.value.split("\n").length;
  if (gutter.childElementCount !== lines) {
    const numbers = [];
    for (let i = 1; i <= lines; i += 1) numbers.push(i);
    gutter.replaceChildren(
      ...numbers.map((n) => {
        const div = document.createElement("div");
        div.textContent = String(n);
        return div;
      }),
    );
  }
  syncScroll();
}

function syncScroll() {
  highlight.parentElement.scrollTop = source.scrollTop;
  highlight.parentElement.scrollLeft = source.scrollLeft;
  gutter.scrollTop = source.scrollTop;
}

function save() {
  try {
    localStorage.setItem(STORAGE_KEY, source.value);
  } catch (error) {
    /* nothing to do — the buffer just won't survive a reload */
  }
}

function setCode(code, { focus = false } = {}) {
  source.value = code;
  paint();
  save();
  if (focus) source.focus();
}

function insert(text) {
  // execCommand keeps the browser's native undo stack intact.
  if (!document.execCommand || !document.execCommand("insertText", false, text)) {
    const { selectionStart, selectionEnd } = source;
    source.setRangeText(text, selectionStart, selectionEnd, "end");
  }
  paint();
  save();
}

function lineStart(index) {
  return source.value.lastIndexOf("\n", index - 1) + 1;
}

function onKeyDown(event) {
  const isRun = (event.metaKey || event.ctrlKey) && event.key === "Enter";
  if (isRun) {
    event.preventDefault();
    run();
    return;
  }

  if (event.key === "Tab") {
    event.preventDefault();
    if (!event.shiftKey) {
      insert("  ");
      return;
    }
    const start = lineStart(source.selectionStart);
    const dedent = source.value.slice(start, start + 2) === "  " ? 2 : 0;
    if (dedent === 0) return;
    const caret = source.selectionStart;
    source.setSelectionRange(start, start + dedent);
    if (!document.execCommand || !document.execCommand("delete")) {
      source.setRangeText("", start, start + dedent, "end");
    }
    source.setSelectionRange(caret - dedent, caret - dedent);
    paint();
    save();
    return;
  }

  if (event.key === "Enter" && !event.shiftKey) {
    const start = lineStart(source.selectionStart);
    const line = source.value.slice(start, source.selectionStart);
    const indent = (/^\s*/.exec(line) || [""])[0];
    if (indent) {
      event.preventDefault();
      insert("\n" + indent);
    }
  }
}

// ---------------------------------------------------------------------------
// Panes
// ---------------------------------------------------------------------------

function showTab(name) {
  const isConsole = name === "console";
  previewTab.classList.toggle("is-active", !isConsole);
  consoleTab.classList.toggle("is-active", isConsole);
  frame.hidden = isConsole;
  consoleEl.hidden = !isConsole;
}

function setStatus(text, tone = "") {
  statusEl.textContent = text;
  statusEl.dataset.tone = tone;
}

function setBusy(state) {
  running = state;
  busyEl.hidden = !state;
  runButton.disabled = state || !compileAvailable;
}

function showError(title, body) {
  errorTitle.textContent = title;
  errorBody.textContent = body;
  errorEl.hidden = false;
}

function clearError() {
  errorEl.hidden = true;
}

function clearConsole() {
  logs = [];
  consoleEl.replaceChildren();
  consoleCount.hidden = true;
}

function appendLog(level, text) {
  logs.push({ level, text });
  const line = document.createElement("div");
  line.className = "pg-log pg-log-" + level;
  line.textContent = text;
  consoleEl.appendChild(line);
  consoleEl.scrollTop = consoleEl.scrollHeight;
  consoleCount.hidden = false;
  consoleCount.textContent = String(logs.length);
}

// ---------------------------------------------------------------------------
// Compile & run
// ---------------------------------------------------------------------------

function reloadFrame(runId) {
  // A fresh document per run: no leftover DOM, no module-level state. The run
  // id travels in the URL and comes back in the frame's "ready" message, so a
  // late ready from the previous document can't claim this bundle.
  frame.src = "./preview.html?run=" + runId;
}

function postToFrame(message) {
  const target = frame.contentWindow;
  if (!target) return;
  target.postMessage(
    Object.assign({ source: "reativa-playground" }, message),
    window.location.origin,
  );
}

async function run() {
  if (running || !compileAvailable) return;

  clearError();
  clearConsole();
  setBusy(true);
  setStatus("Compiling…");

  let result;
  try {
    const response = await fetch(COMPILE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code: source.value, backend }),
    });
    result = await response.json();
  } catch (error) {
    setBusy(false);
    setOffline();
    setStatus("No compiler", "error");
    showError(
      "The playground server is not reachable",
      "Run the playground locally with:\n\n  npm run playground\n\n" +
        String(error && error.message ? error.message : error),
    );
    return;
  }

  setBusy(false);

  if (!result || !result.ok) {
    const stage = (result && result.stage) || "build";
    const titles = {
      input: "Nothing to compile",
      toolchain: "Toolchain missing",
      build: "Build failed",
      bundle: "Bundling failed",
      server: "Playground server error",
    };
    setStatus("Failed", "error");
    showError(titles[stage] || "Build failed", (result && result.error) || "Unknown error.");
    return;
  }

  pendingBundle = { js: result.js, format: result.format };
  pendingRunId = String(Date.now());
  lastResult = result;
  setStatus(`Running · ${backendLabel(result.backend || backend)}`);
  showTab("preview");
  reloadFrame(pendingRunId);
}

function formatSize(bytes) {
  if (!bytes) return "";
  const kb = bytes / 1024;
  return kb >= 1000 ? `${(kb / 1024).toFixed(1)} MB` : `${Math.round(kb)} KB`;
}

function currentTheme() {
  return document.documentElement.getAttribute("data-theme") || "light";
}

window.addEventListener("message", (event) => {
  if (event.origin !== window.location.origin) return;
  const data = event.data;
  if (!data || data.source !== "reativa-playground-preview") return;

  if (data.type === "ready") {
    if (pendingBundle && data.runId === pendingRunId) {
      postToFrame({
        type: "run",
        js: pendingBundle.js,
        format: pendingBundle.format,
        theme: currentTheme(),
      });
      pendingBundle = null;
      pendingRunId = null;
    } else {
      postToFrame({ type: "theme", theme: currentTheme() });
    }
    return;
  }

  if (data.type === "log") {
    appendLog(data.level === "error" ? "error" : data.level, data.text);
    return;
  }

  if (data.type === "runtime-error") {
    appendLog("error", data.text);
    setStatus("Runtime error", "error");
    showTab("console");
    return;
  }

  if (data.type === "mounted") {
    const size = lastResult ? ` · ${formatSize(lastResult.bytes)}` : "";
    setStatus(`Mounted · ${backendLabel(backend)}${size}`, "ok");
    statusEl.title = lastResult
      ? "Size of the JavaScript this run produced — dev profile, unminified."
      : "";
  }
});

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

function setOffline() {
  compileAvailable = false;
  offlineEl.hidden = false;
  paintBackends();
  runButton.disabled = true;
  runButton.title = "Run the playground locally: npm run playground";
}

async function probeCompiler() {
  try {
    const response = await fetch(STATUS_URL, { cache: "no-store" });
    if (!response.ok) throw new Error("unavailable");
    const payload = await response.json();
    if (!payload || !payload.ok) throw new Error("unavailable");
    if (Array.isArray(payload.backends) && payload.backends.length) {
      backends = payload.backends;
      if (!backends.some((item) => item.id === backend)) backend = backends[0].id;
      paintBackends();
    }
  } catch (error) {
    setOffline();
    setStatus("Read-only");
  }
}

for (const example of EXAMPLES) {
  const option = document.createElement("option");
  option.value = example.id;
  option.textContent = example.title;
  option.title = example.blurb;
  examplesSelect.appendChild(option);
}

examplesSelect.addEventListener("change", () => {
  const example = EXAMPLES.find((item) => item.id === examplesSelect.value);
  if (!example) return;
  setCode(example.code, { focus: true });
  if (compileAvailable) run();
});

resetButton.addEventListener("click", () => {
  const example =
    EXAMPLES.find((item) => item.id === examplesSelect.value) || DEFAULT_EXAMPLE;
  setCode(example.code, { focus: true });
});

shareButton.addEventListener("click", async () => {
  const url = new URL(window.location.href);
  url.hash = "backend=" + backend + "&code=" + encodeCode(source.value);
  window.history.replaceState(null, "", url.toString());
  try {
    await navigator.clipboard.writeText(url.toString());
    shareButton.textContent = "Copied";
  } catch (error) {
    shareButton.textContent = "Link in URL";
  }
  setTimeout(() => {
    shareButton.textContent = "Share";
  }, 1600);
});

runButton.addEventListener("click", run);
errorClose.addEventListener("click", clearError);
previewTab.addEventListener("click", () => showTab("preview"));
consoleTab.addEventListener("click", () => showTab("console"));

source.addEventListener("input", () => {
  paint();
  save();
});
source.addEventListener("scroll", syncScroll);
source.addEventListener("keydown", onKeyDown);

themeButton.addEventListener("click", () => {
  const next = currentTheme() === "dark" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", next);
  try {
    localStorage.setItem("theme", next);
  } catch (error) {
    /* theme just won't persist */
  }
  themeButton.textContent = next === "dark" ? "☀" : "☾";
  postToFrame({ type: "theme", theme: next });
});

themeButton.textContent = currentTheme() === "dark" ? "☀" : "☾";

// The run shortcut is ⌘⏎ on macOS and Ctrl+⏎ everywhere else.
const isApple = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
document.querySelector(".pg-kbd").textContent = isApple ? "⌘⏎" : "Ctrl+⏎";

backend = initialBackend();
paintBackends();

setCode(initialCode());
showTab("preview");
setStatus("Ready");

probeCompiler().then(() => {
  if (compileAvailable) run();
});

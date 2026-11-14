// Entry point: importing the compiled reativa app mounts the site, routed
// in place by reativa's own Router, so pages come and go without a reload.
import "../../_build/default/website/src/output/website/src/app.js";

// Code panels are static views, colored once when they appear. Pages mount
// as you navigate, so a MutationObserver colors each new block; a block that
// has been colored is marked and skipped. The highlighters themselves live in
// highlight.js, shared with the playground editor.
import {
  highlightOCaml,
  highlightReason,
  highlightDune,
  highlightShell,
} from "./highlight.js";

import { track } from "./analytics.js";

const HIGHLIGHTERS = [
  ["pre.ocaml code", highlightOCaml],
  ["pre.reason code", highlightReason],
  ["pre.dune code", highlightDune],
  ["pre.shell code", highlightShell],
];

const app = document.getElementById("app");

function highlightAll() {
  for (const [selector, highlight] of HIGHLIGHTERS) {
    app.querySelectorAll(selector).forEach((code) => {
      if (code.dataset.highlighted) return;
      code.dataset.highlighted = "1";
      code.replaceChildren(highlight(code.textContent));
    });
  }
}

highlightAll();

// Batched to one pass per frame: a page mounts in one go, and coloring a
// block is itself a mutation the observer sees (and skips).
let queued = false;
new MutationObserver(() => {
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => {
    queued = false;
    highlightAll();
  });
}).observe(app, { childList: true, subtree: true });

// ----- analytics -----
//
// Observed from the outside (a delegated click listener plus a section
// observer) rather than wired into app.mlx, so the OCaml source stays free of
// tracking calls. See website/README.md for what is collected.

const syntaxNow = () =>
  document.querySelector(".syntax-opt.is-active")?.textContent || "";

document.addEventListener("click", (event) => {
  const target = event.target;
  if (!(target instanceof Element)) return;

  const copy = target.closest(".copy-btn");
  if (copy) {
    // The panels carry no id in the DOM; the filename in the bar names the
    // snippet just as well, and follows the syntax toggle.
    track("docs_code_copied", {
      file: copy.closest(".code-panel")?.querySelector(".code-file")?.textContent,
      syntax: syntaxNow(),
    });
    return;
  }

  const syntax = target.closest(".syntax-opt");
  if (syntax) {
    track("docs_syntax_changed", { syntax: syntax.textContent });
    return;
  }

  if (target.closest(".theme-btn")) {
    // The button flips the theme, and the attribute is already updated by the
    // time the event bubbles up here.
    track("docs_theme_changed", {
      theme: document.documentElement.getAttribute("data-theme"),
    });
    return;
  }

  const link = target.closest("a[href]");
  if (!link) return;

  const href = link.getAttribute("href");
  if (href.startsWith("http")) {
    track("docs_outbound_click", { href, text: link.textContent.trim() });
  }
});

// Route changes. The app navigates with history.pushState, which fires no
// event, so it is wrapped; back and forward arrive as popstate. Only a new
// pathname counts: following an #anchor on the same page is not a pageview.
// PostHog records the first pageview itself (capture_pageview in
// analytics.js); these are the in-app ones.
let lastPath = location.pathname;
const onRoute = () => {
  if (location.pathname === lastPath) return;
  lastPath = location.pathname;
  track("$pageview", { $current_url: location.href });
  // Give the new page a tick to mount before looking for its sections.
  setTimeout(observeSections, 0);
};
const pushState = history.pushState.bind(history);
history.pushState = (...args) => {
  pushState(...args);
  onRoute();
};
window.addEventListener("popstate", onRoute);

// How far down a page people actually get. Each section reports once per
// visit to its page, the first time it reaches the middle band of the
// viewport; a threshold in percent would never fire for the sections that are
// taller than the screen.
const sectionObserver =
  typeof IntersectionObserver === "function"
    ? new IntersectionObserver(
        (entries) => {
          for (const entry of entries) {
            if (!entry.isIntersecting) continue;
            sectionObserver.unobserve(entry.target);
            track("docs_section_viewed", {
              section: entry.target.id,
              page: location.pathname,
            });
          }
        },
        { rootMargin: "-25% 0px -25% 0px" },
      )
    : null;

function observeSections() {
  if (!sectionObserver) return;
  sectionObserver.disconnect();
  app.querySelectorAll("section[id], .docs-content h2[id]").forEach((el) => sectionObserver.observe(el));
}

observeSections();

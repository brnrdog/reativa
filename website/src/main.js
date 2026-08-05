// Entry point: importing the compiled reativa app mounts the page
// synchronously, so the highlighter below runs over already-rendered code.
import "../../_build/default/website/src/output/website/src/app.js";

// Code panels are static views (they never re-render), so a single pass after
// mount is enough. The highlighters themselves live in highlight.js, shared
// with the playground editor.
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

for (const [selector, highlight] of HIGHLIGHTERS) {
  document.querySelectorAll(selector).forEach((code) => {
    code.replaceChildren(highlight(code.textContent));
  });
}

// ---------------------------------------------------------------------------
// Analytics
//
// The page is one document, so a pageview on its own says nothing about what
// people came for. The events below are observed from the outside — a
// delegated click listener and an observer over the sections — rather than
// wired into app.mlx, so the OCaml source stays free of tracking calls.
// ---------------------------------------------------------------------------

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
  } else if (href.startsWith("playground")) {
    track("docs_playground_opened");
  }
});

// How far down the page people actually get. Each section reports once, the
// first time it reaches the middle band of the viewport — a threshold in
// percent would never fire for the sections that are taller than the screen.
if (typeof IntersectionObserver === "function") {
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        observer.unobserve(entry.target);
        track("docs_section_viewed", { section: entry.target.id });
      }
    },
    { rootMargin: "-25% 0px -25% 0px" },
  );

  document
    .querySelectorAll("main.page > section[id]")
    .forEach((section) => observer.observe(section));
}

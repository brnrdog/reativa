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

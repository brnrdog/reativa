// Shipped JS helpers for bindings with no global-function equivalent.
//
// The OCaml modules that use these also compile (but never link) under the
// native toolchain, so every external must be bound to a plain identifier:
// melange primitive spellings like "#typeof" or "#undefined" produce symbols
// the native assembler rejects. Binding to this module keeps the FFI names
// ordinary while melange imports the real implementation.

export function classify(x) {
  return typeof x;
}

export function getWindow() {
  return window;
}

export function getUndefined() {
  return undefined;
}

export function getBody() {
  return document.body;
}

// Promise rejections: Melange represents an OCaml exception as an object
// carrying its constructor under MEL_EXN_ID (RE_EXN_ID in older releases).
export function isOcamlExn(reason) {
  return reason != null && typeof reason === "object" && ("MEL_EXN_ID" in reason || "RE_EXN_ID" in reason);
}

export function describeReason(reason) {
  return reason instanceof Error ? reason.message : String(reason);
}

// Parse an HTML string once into a DocumentFragment, through a <template>
// element (whose content is inert: no scripts run, no images load).
export function templateContent(html) {
  const template = document.createElement("template");
  template.innerHTML = html;
  return template.content;
}

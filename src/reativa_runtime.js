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

// Generates the element props of View.Mlx from one table.
//
//   node scripts/generate-mlx-props.mjs          rewrite src/view.ml and src/view.mli
//   node scripts/generate-mlx-props.mjs --check  exit 1 if it is out of date
//
// mlx lowers <input type_="text" onInput=f /> to
// [input ~type_:"text" ~onInput:f ()], so every prop an element accepts is an
// optional argument of View.Mlx.create. Writing ~100 of them by hand, plus the
// code that turns each into an attribute or a listener, invites drift; this
// table is the single place they are declared. The generated block sits
// between the BEGIN/END markers in src/view.ml.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const target = join(root, "src", "view.ml");

// [label, DOM attribute, kind]
//   string  : string value, set with setAttribute ("value" goes to the property)
//   int     : int value, written as a decimal string
//   toggle  : bool value; the attribute is present (empty) or absent
//   prop    : bool value, set as a DOM property (live state, not the default)
export const ATTRIBUTES = [
  // global
  ["id", "id", "string"],
  ["title", "title", "string"],
  ["lang", "lang", "string"],
  ["dir", "dir", "string"],
  ["role", "role", "string"],
  ["style", "style", "string"],
  ["tabIndex", "tabindex", "int"],
  ["hidden", "hidden", "toggle"],
  ["draggable", "draggable", "string"],
  ["contentEditable", "contenteditable", "string"],
  ["spellcheck", "spellcheck", "string"],
  ["translate", "translate", "string"],
  ["slot", "slot", "string"],
  // accessibility
  ["aria_label", "aria-label", "string"],
  ["aria_labelledby", "aria-labelledby", "string"],
  ["aria_describedby", "aria-describedby", "string"],
  ["aria_hidden", "aria-hidden", "string"],
  ["aria_expanded", "aria-expanded", "string"],
  ["aria_controls", "aria-controls", "string"],
  ["aria_current", "aria-current", "string"],
  ["aria_pressed", "aria-pressed", "string"],
  ["aria_selected", "aria-selected", "string"],
  ["aria_checked", "aria-checked", "string"],
  ["aria_disabled", "aria-disabled", "string"],
  ["aria_live", "aria-live", "string"],
  ["aria_haspopup", "aria-haspopup", "string"],
  ["aria_invalid", "aria-invalid", "string"],
  // links and media
  ["href", "href", "string"],
  ["target", "target", "string"],
  ["rel", "rel", "string"],
  ["download", "download", "string"],
  ["hreflang", "hreflang", "string"],
  ["src", "src", "string"],
  ["srcSet", "srcset", "string"],
  ["sizes", "sizes", "string"],
  ["alt", "alt", "string"],
  ["width", "width", "string"],
  ["height", "height", "string"],
  ["loading", "loading", "string"],
  ["decoding", "decoding", "string"],
  ["crossOrigin", "crossorigin", "string"],
  ["poster", "poster", "string"],
  ["preload", "preload", "string"],
  ["controls", "controls", "toggle"],
  ["autoplay", "autoplay", "toggle"],
  ["loop", "loop", "toggle"],
  ["muted", "muted", "toggle"],
  ["playsInline", "playsinline", "toggle"],
  // forms
  ["name", "name", "string"],
  ["type_", "type", "string"],
  ["value", "value", "string"],
  ["placeholder", "placeholder", "string"],
  ["for_", "for", "string"],
  ["htmlFor", "for", "string"],
  ["form", "form", "string"],
  ["action", "action", "string"],
  ["method_", "method", "string"],
  ["enctype", "enctype", "string"],
  ["accept", "accept", "string"],
  ["acceptCharset", "accept-charset", "string"],
  ["autocomplete", "autocomplete", "string"],
  ["pattern", "pattern", "string"],
  ["min", "min", "string"],
  ["max", "max", "string"],
  ["step", "step", "string"],
  ["minLength", "minlength", "int"],
  ["maxLength", "maxlength", "int"],
  ["size", "size", "int"],
  ["rows", "rows", "int"],
  ["cols", "cols", "int"],
  ["wrap", "wrap", "string"],
  ["list", "list", "string"],
  ["inputMode", "inputmode", "string"],
  ["enterKeyHint", "enterkeyhint", "string"],
  ["label_", "label", "string"],
  ["disabled", "disabled", "toggle"],
  ["required", "required", "toggle"],
  ["readOnly", "readonly", "toggle"],
  ["multiple", "multiple", "toggle"],
  ["autofocus", "autofocus", "toggle"],
  ["noValidate", "novalidate", "toggle"],
  ["checked", "checked", "prop"],
  ["selected", "selected", "prop"],
  // tables, lists, details, dialogs
  ["colSpan", "colspan", "int"],
  ["rowSpan", "rowspan", "int"],
  ["headers", "headers", "string"],
  ["scope", "scope", "string"],
  ["start", "start", "int"],
  ["reversed", "reversed", "toggle"],
  ["open_", "open", "toggle"],
  ["dateTime", "datetime", "string"],
  ["cite", "cite", "string"],
  // SVG presentation and geometry
  ["viewBox", "viewBox", "string"],
  ["xmlns", "xmlns", "string"],
  ["d", "d", "string"],
  ["fill", "fill", "string"],
  ["fill_rule", "fill-rule", "string"],
  ["fill_opacity", "fill-opacity", "string"],
  ["stroke", "stroke", "string"],
  ["stroke_width", "stroke-width", "string"],
  ["stroke_linecap", "stroke-linecap", "string"],
  ["stroke_linejoin", "stroke-linejoin", "string"],
  ["stroke_dasharray", "stroke-dasharray", "string"],
  ["stroke_dashoffset", "stroke-dashoffset", "string"],
  ["opacity", "opacity", "string"],
  ["transform", "transform", "string"],
  ["cx", "cx", "string"],
  ["cy", "cy", "string"],
  ["r", "r", "string"],
  ["rx", "rx", "string"],
  ["ry", "ry", "string"],
  ["x", "x", "string"],
  ["y", "y", "string"],
  ["x1", "x1", "string"],
  ["y1", "y1", "string"],
  ["x2", "x2", "string"],
  ["y2", "y2", "string"],
  ["points", "points", "string"],
  ["offset", "offset", "string"],
  ["stop_color", "stop-color", "string"],
  ["preserveAspectRatio", "preserveAspectRatio", "string"],
];

// [label, DOM event]
export const EVENTS = [
  ["onClick", "click"],
  ["onDblClick", "dblclick"],
  ["onContextMenu", "contextmenu"],
  ["onInput", "input"],
  ["onChange", "change"],
  ["onSubmit", "submit"],
  ["onReset", "reset"],
  ["onInvalid", "invalid"],
  ["onKeyDown", "keydown"],
  ["onKeyUp", "keyup"],
  ["onFocus", "focus"],
  ["onBlur", "blur"],
  ["onFocusIn", "focusin"],
  ["onFocusOut", "focusout"],
  ["onMouseDown", "mousedown"],
  ["onMouseUp", "mouseup"],
  ["onMouseEnter", "mouseenter"],
  ["onMouseLeave", "mouseleave"],
  ["onMouseMove", "mousemove"],
  ["onMouseOver", "mouseover"],
  ["onMouseOut", "mouseout"],
  ["onPointerDown", "pointerdown"],
  ["onPointerUp", "pointerup"],
  ["onPointerMove", "pointermove"],
  ["onPointerEnter", "pointerenter"],
  ["onPointerLeave", "pointerleave"],
  ["onPointerOver", "pointerover"],
  ["onPointerOut", "pointerout"],
  ["onPointerCancel", "pointercancel"],
  ["onTouchStart", "touchstart"],
  ["onTouchMove", "touchmove"],
  ["onTouchEnd", "touchend"],
  ["onTouchCancel", "touchcancel"],
  ["onWheel", "wheel"],
  ["onScroll", "scroll"],
  ["onDragStart", "dragstart"],
  ["onDrag", "drag"],
  ["onDragEnd", "dragend"],
  ["onDragEnter", "dragenter"],
  ["onDragOver", "dragover"],
  ["onDragLeave", "dragleave"],
  ["onDrop", "drop"],
  ["onCopy", "copy"],
  ["onCut", "cut"],
  ["onPaste", "paste"],
  ["onLoad", "load"],
  ["onError", "error"],
  ["onToggle", "toggle"],
  ["onClose", "close"],
  ["onAnimationStart", "animationstart"],
  ["onAnimationEnd", "animationend"],
  ["onTransitionEnd", "transitionend"],
  ["onPlay", "play"],
  ["onPause", "pause"],
  ["onEnded", "ended"],
  ["onTimeUpdate", "timeupdate"],
];

// Element helpers. Single-letter tags other than a and p are left out: an
// [open View.Mlx] would otherwise shadow common variable names (i, b, s, q,
// u); write them as [View.element "b" ...]. SVG's <text> and <title> are left
// out for the same reason (they would shadow [text] and the [title] prop's
// variables); use [View.element].
export const ELEMENTS = [
  "a", "abbr", "address", "article", "aside", "audio", "blockquote", "br", "button",
  "canvas", "caption", "code", "col", "colgroup", "dd", "del", "details", "dfn",
  "dialog", "div", "dl", "dt", "em", "fieldset", "figcaption", "figure", "footer",
  "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "iframe", "img",
  "input", "ins", "kbd", "label", "legend", "li", "main", "mark", "menu", "meter",
  "nav", "ol", "optgroup", "option", "output", "p", "picture", "pre", "progress",
  "samp", "section", "select", "small", "source", "span", "strong", "sub",
  "summary", "sup", "table", "tbody", "td", "textarea", "tfoot", "th", "thead",
  "time", "tr", "ul", "video", "wbr",
  // SVG (created in the SVG namespace, see View.insert)
  "svg", "g", "path", "circle", "rect", "line", "polyline", "polygon", "ellipse",
  "defs", "symbol", "use", "stop",
];

function generate() {
  const lines = [];
  const push = (s = "") => lines.push(s);
  const labels = ATTRIBUTES.map(([label]) => label);

  push("  (* Generated by scripts/generate-mlx-props.mjs from its prop table; edit");
  push("     the table, not this block. *)");
  push("");
  push("  let push_string name value attrs =");
  push("    match value with Some value -> Attr.make name value :: attrs | None -> attrs");
  push("");
  push("  let push_int name value attrs =");
  push("    match value with");
  push("    | Some value -> Attr.make name (map_value string_of_int value) :: attrs");
  push("    | None -> attrs");
  push("");
  push("  let push_toggle name value attrs =");
  push("    match value with");
  push('    | Some (Static true) -> Attr_static (name, "") :: attrs');
  push("    | Some (Static false) | None -> attrs");
  push("    | Some (Reactive f) -> Attr.toggle name f :: attrs");
  push("");
  push("  let push_prop name value attrs =");
  push("    match value with Some value -> Attr.bool_property name value :: attrs | None -> attrs");
  push("");
  push("  let push_event name handler events =");
  push("    match handler with Some handler -> (name, handler) :: events | None -> events");
  push("");
  lines.push(...elementType("  "));
  push("");
  push("  (* [className] wins over [class_] when both are given. *)");
  push("  let create tag : element = fun ?class_ ?className");
  push(`      ${labels.map((l) => `?${l}`).join(" ")}`);
  push(`      ${EVENTS.map(([l]) => `?${l}`).join(" ")}`);
  push("      ?ref ?(attrs = []) ?(children = []) () ->");
  push("    let class_ = match className with Some _ -> className | None -> class_ in");
  push("    let acc = push_string \"class\" class_ [] in");
  for (const [label, attr, kind] of ATTRIBUTES) {
    const fn = { string: "push_string", int: "push_int", toggle: "push_toggle", prop: "push_prop" }[kind];
    push(`    let acc = ${fn} ${JSON.stringify(attr)} ${label} acc in`);
  }
  push("    let events = [] in");
  for (const [label, event] of EVENTS) {
    push(`    let events = push_event ${JSON.stringify(event)} ${label} events in`);
  }
  push("    let acc = match ref with Some r -> Attr_ref r :: acc | None -> acc in");
  push("    element ~attrs:(List.rev_append acc attrs) ~events:(List.rev events) tag children");
  push("");
  for (const tag of ELEMENTS) push(`  let ${tag} = create ${JSON.stringify(tag)}`);
  return lines.join("\n") + "\n";
}

// The matching signature in src/view.mli: one [element] type for every
// element helper, since they all take the same props.
function elementType(indent) {
  const type = { string: "string value", int: "int value", toggle: "bool value", prop: "bool value" };
  const lines = [`${indent}type element =`];
  const arg = (s) => lines.push(`${indent}  ${s} ->`);
  arg("?class_:string value");
  arg("?className:string value");
  for (const [label, , kind] of ATTRIBUTES) arg(`?${label}:${type[kind]}`);
  for (const [label] of EVENTS) arg(`?${label}:(Dom.event -> unit)`);
  arg("?ref:Ref.t");
  arg("?attrs:attr list");
  arg("?children:t list");
  arg("unit");
  lines.push(`${indent}  t`);
  return lines;
}

function generateSignature() {
  const lines = [];
  const push = (s = "") => lines.push(s);
  push("  (* Generated by scripts/generate-mlx-props.mjs; edit its table. *)");
  lines.push(...elementType("  "));
  push("");
  push("  val create : string -> element");
  for (const tag of ELEMENTS) push(`  val ${tag} : element`);
  return lines.join("\n") + "\n";
}

// The same table for the ppx, which compiles element trees to templates and
// needs to know, per prop, which attribute it sets and how.
function generatePpxTable() {
  const kind = { string: "String", int: "Int", toggle: "Toggle", prop: "Property" };
  const lines = [
    "(* Generated by scripts/generate-mlx-props.mjs from its prop table; edit the",
    "   table, not this file. *)",
    "",
    "type kind = String | Int | Toggle | Property",
    "",
    "(* label, DOM attribute, kind *)",
    "let attributes =",
    "  [",
    '    ("class_", "class", String);',
    '    ("className", "class", String);',
  ];
  for (const [label, attr, k] of ATTRIBUTES) lines.push(`    (${JSON.stringify(label)}, ${JSON.stringify(attr)}, ${kind[k]});`);
  lines.push("  ]", "", "(* label, DOM event *)", "let events =", "  [");
  for (const [label, event] of EVENTS) lines.push(`    (${JSON.stringify(label)}, ${JSON.stringify(event)});`);
  lines.push("  ]", "", "let elements =", "  [");
  for (const tag of ELEMENTS) lines.push(`    ${JSON.stringify(tag)};`);
  lines.push("  ]", "");
  return lines.join("\n");
}

function splice(file, begin, end, body) {
  const source = readFileSync(file, "utf8");
  const start = source.indexOf(begin);
  const stop = source.indexOf(end);
  if (start === -1 || stop === -1) throw new Error(`markers not found in ${file}`);
  return { source, next: source.slice(0, start + begin.length) + body + source.slice(stop) };
}

const outputs = [
  [target, "  (* BEGIN GENERATED MLX PROPS *)\n", "  (* END GENERATED MLX PROPS *)\n", generate()],
  [
    join(root, "src", "view.mli"),
    "  (* BEGIN GENERATED MLX SIGNATURE *)\n",
    "  (* END GENERATED MLX SIGNATURE *)\n",
    generateSignature(),
  ],
];

{
  const file = join(root, "ppx", "mlx_prop_table.ml");
  const next = generatePpxTable();
  let source = "";
  try {
    source = readFileSync(file, "utf8");
  } catch {}
  if (next !== source) {
    if (process.argv.includes("--check")) {
      console.error(`${file} is out of date: run node scripts/generate-mlx-props.mjs`);
      process.exitCode = 1;
    } else {
      writeFileSync(file, next);
      console.log(`updated ${file}`);
    }
  }
}

let stale = false;
for (const [file, begin, end, body] of outputs) {
  const { source, next } = splice(file, begin, end, body);
  if (next === source) continue;
  if (process.argv.includes("--check")) {
    console.error(`${file} is out of date: run node scripts/generate-mlx-props.mjs`);
    stale = true;
  } else {
    writeFileSync(file, next);
    console.log(`updated ${file}`);
  }
}
if (stale) process.exit(1);

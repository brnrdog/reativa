// Entry point: importing the compiled reativa app mounts the page
// synchronously, so the highlighter below runs over already-rendered code.
import "../../_build/default/website/src/output/website/src/app.js";

// ---------------------------------------------------------------------------
// A tiny, dependency-free syntax highlighter. Code panels are static views
// (they never re-render), so a single pass after mount is enough. Tokens are
// built as DOM nodes — no innerHTML — and unknown text passes through as-is.
// ---------------------------------------------------------------------------

const OCAML_KEYWORDS = new Set([
  "and", "as", "assert", "begin", "do", "done", "downto", "else", "end",
  "exception", "external", "for", "fun", "function", "functor", "if", "in",
  "include", "inherit", "lazy", "let", "match", "method", "module", "mutable",
  "new", "nonrec", "of", "open", "rec", "sig", "struct", "then", "to", "try",
  "type", "val", "virtual", "when", "while", "with",
]);

const OCAML_CONSTANTS = new Set(["true", "false"]);

// ReasonML shares most of OCaml's lexemes but swaps a few keywords (switch for
// match, pub/pri for methods) and uses /* */ comments instead of (* *).
const REASON_KEYWORDS = new Set([
  "and", "as", "downto", "else", "external", "for", "fun", "if", "in",
  "include", "lazy", "let", "module", "mutable", "of", "open", "pri", "pub",
  "rec", "switch", "then", "to", "try", "type", "when", "while",
]);

const isIdentStart = (ch) => /[A-Za-z_]/.test(ch);
const isIdentChar = (ch) => /[A-Za-z0-9_']/.test(ch);

function makeEmitter(fragment) {
  let plain = "";
  const flush = () => {
    if (plain) {
      fragment.appendChild(document.createTextNode(plain));
      plain = "";
    }
  };
  return {
    text(chunk) {
      plain += chunk;
    },
    token(cls, chunk) {
      flush();
      const span = document.createElement("span");
      span.className = cls;
      span.textContent = chunk;
      fragment.appendChild(span);
    },
    done() {
      flush();
      return fragment;
    },
  };
}

function highlightOCaml(source) {
  const out = makeEmitter(document.createDocumentFragment());
  const n = source.length;
  let i = 0;
  let tagContext = false; // the identifier right after "<" or "</" is a tag

  while (i < n) {
    const ch = source[i];

    // (* comments *), nested
    if (ch === "(" && source[i + 1] === "*") {
      let depth = 0;
      let j = i;
      while (j < n) {
        if (source[j] === "(" && source[j + 1] === "*") {
          depth += 1;
          j += 2;
        } else if (source[j] === "*" && source[j + 1] === ")") {
          depth -= 1;
          j += 2;
          if (depth === 0) break;
        } else {
          j += 1;
        }
      }
      out.token("tok-com", source.slice(i, j));
      i = j;
      continue;
    }

    // "strings" with escapes
    if (ch === '"') {
      let j = i + 1;
      while (j < n && source[j] !== '"') {
        if (source[j] === "\\") j += 1;
        j += 1;
      }
      j = Math.min(j + 1, n);
      out.token("tok-str", source.slice(i, j));
      i = j;
      continue;
    }

    // {|quoted strings|} and {js|unicode strings|js}
    if (ch === "{") {
      const open = source.slice(i).match(/^\{([a-z]*)\|/);
      if (open) {
        const closer = "|" + open[1] + "}";
        const end = source.indexOf(closer, i + open[0].length);
        const j = end === -1 ? n : end + closer.length;
        out.token("tok-str", source.slice(i, j));
        i = j;
        continue;
      }
    }

    // numbers
    if (/[0-9]/.test(ch)) {
      let j = i;
      while (j < n && /[0-9._xXa-fA-F]/.test(source[j])) j += 1;
      out.token("tok-num", source.slice(i, j));
      i = j;
      continue;
    }

    // JSX-ish tag brackets: "<div", "</div", "/>"
    if (ch === "<" && (source[i + 1] === "/" || isIdentStart(source[i + 1] || ""))) {
      const close = source[i + 1] === "/";
      out.token("tok-punct", close ? "</" : "<");
      i += close ? 2 : 1;
      tagContext = true;
      continue;
    }
    if (ch === "/" && source[i + 1] === ">") {
      out.token("tok-punct", "/>");
      i += 2;
      continue;
    }

    // identifiers, keywords, modules, tags
    if (isIdentStart(ch)) {
      let j = i;
      while (j < n && isIdentChar(source[j])) j += 1;
      const word = source.slice(i, j);
      const capitalized = /[A-Z]/.test(word[0]);
      if (tagContext && !capitalized) {
        out.token("tok-tag", word);
      } else if (OCAML_KEYWORDS.has(word)) {
        out.token("tok-kw", word);
      } else if (OCAML_CONSTANTS.has(word)) {
        out.token("tok-num", word);
      } else if (capitalized) {
        out.token("tok-mod", word);
      } else {
        out.text(word);
      }
      tagContext = false;
      i = j;
      continue;
    }

    if (ch !== "." ) tagContext = tagContext && /\s/.test(ch);
    out.text(ch);
    i += 1;
  }

  return out.done();
}

function highlightReason(source) {
  const out = makeEmitter(document.createDocumentFragment());
  const n = source.length;
  let i = 0;
  let tagContext = false; // the identifier right after "<" or "</" is a tag

  while (i < n) {
    const ch = source[i];

    // /* comments */, nested
    if (ch === "/" && source[i + 1] === "*") {
      let depth = 0;
      let j = i;
      while (j < n) {
        if (source[j] === "/" && source[j + 1] === "*") {
          depth += 1;
          j += 2;
        } else if (source[j] === "*" && source[j + 1] === "/") {
          depth -= 1;
          j += 2;
          if (depth === 0) break;
        } else {
          j += 1;
        }
      }
      out.token("tok-com", source.slice(i, j));
      i = j;
      continue;
    }

    // "strings" with escapes
    if (ch === '"') {
      let j = i + 1;
      while (j < n && source[j] !== '"') {
        if (source[j] === "\\") j += 1;
        j += 1;
      }
      j = Math.min(j + 1, n);
      out.token("tok-str", source.slice(i, j));
      i = j;
      continue;
    }

    // {|quoted strings|} and {js|unicode strings|js}
    if (ch === "{") {
      const open = source.slice(i).match(/^\{([a-z]*)\|/);
      if (open) {
        const closer = "|" + open[1] + "}";
        const end = source.indexOf(closer, i + open[0].length);
        const j = end === -1 ? n : end + closer.length;
        out.token("tok-str", source.slice(i, j));
        i = j;
        continue;
      }
    }

    // numbers
    if (/[0-9]/.test(ch)) {
      let j = i;
      while (j < n && /[0-9._xXa-fA-F]/.test(source[j])) j += 1;
      out.token("tok-num", source.slice(i, j));
      i = j;
      continue;
    }

    // JSX-ish tag brackets: "<div", "</div", "/>"
    if (ch === "<" && (source[i + 1] === "/" || isIdentStart(source[i + 1] || ""))) {
      const close = source[i + 1] === "/";
      out.token("tok-punct", close ? "</" : "<");
      i += close ? 2 : 1;
      tagContext = true;
      continue;
    }
    if (ch === "/" && source[i + 1] === ">") {
      out.token("tok-punct", "/>");
      i += 2;
      continue;
    }

    // identifiers, keywords, modules, tags
    if (isIdentStart(ch)) {
      let j = i;
      while (j < n && isIdentChar(source[j])) j += 1;
      const word = source.slice(i, j);
      const capitalized = /[A-Z]/.test(word[0]);
      if (tagContext && !capitalized) {
        out.token("tok-tag", word);
      } else if (REASON_KEYWORDS.has(word)) {
        out.token("tok-kw", word);
      } else if (OCAML_CONSTANTS.has(word)) {
        out.token("tok-num", word);
      } else if (capitalized) {
        out.token("tok-mod", word);
      } else {
        out.text(word);
      }
      tagContext = false;
      i = j;
      continue;
    }

    if (ch !== ".") tagContext = tagContext && /\s/.test(ch);
    out.text(ch);
    i += 1;
  }

  return out.done();
}

function highlightDune(source) {
  const out = makeEmitter(document.createDocumentFragment());
  const n = source.length;
  let i = 0;

  while (i < n) {
    const ch = source[i];

    if (ch === ";") {
      let j = source.indexOf("\n", i);
      if (j === -1) j = n;
      out.token("tok-com", source.slice(i, j));
      i = j;
      continue;
    }
    if (ch === "%" && source[i + 1] === "{") {
      let j = source.indexOf("}", i);
      j = j === -1 ? n : j + 1;
      out.token("tok-num", source.slice(i, j));
      i = j;
      continue;
    }
    if (ch === "(") {
      out.token("tok-punct", "(");
      i += 1;
      let j = i;
      while (j < n && /[A-Za-z0-9_.]/.test(source[j])) j += 1;
      if (j > i) {
        out.token("tok-kw", source.slice(i, j));
        i = j;
      }
      continue;
    }
    if (ch === ")") {
      out.token("tok-punct", ")");
      i += 1;
      continue;
    }
    out.text(ch);
    i += 1;
  }

  return out.done();
}

function highlightShell(source) {
  const out = makeEmitter(document.createDocumentFragment());
  for (const [index, line] of source.split("\n").entries()) {
    if (index > 0) out.text("\n");
    if (line.trimStart().startsWith("#")) {
      out.token("tok-com", line);
      continue;
    }
    const match = line.match(/^(\s*)(\S+)([\s\S]*)$/);
    if (match) {
      if (match[1]) out.text(match[1]);
      out.token("tok-kw", match[2]);
      out.text(match[3]);
    } else {
      out.text(line);
    }
  }
  return out.done();
}

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

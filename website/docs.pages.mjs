// The documentation pages, registered once. scripts/build-agent-docs.mjs reads
// this to publish each page's agent layer as /docs/<slug>.md and to write
// /llms.txt; the site's "New in 2.0" section lists the pages marked isNew.
//
// Each entry: slug, title, section, summary (one sentence, also the llms.txt
// description), isNew (new in the upcoming major release), and file (the
// agent layer, under website/docs/agent/).

export const VERSION = "2.0";

export const pages = [
  { slug: "glossary", title: "Glossary", section: "Start", summary: "The terms the other pages use: signal, computed, effect, owner, region, leaf, template, hole.", file: "glossary.md" },
  { slug: "signals", title: "Signals, computeds and effects", section: "Reactivity", summary: "Reactive state, derived values and side effects; batching, untracked reads, equality and disposal.", file: "signals.md" },
  { slug: "ownership", title: "Ownership and lifecycle", section: "Reactivity", summary: "Who disposes what: owners, lazy components, on_mount, on_cleanup, refs and mount_disposable.", isNew: true, file: "ownership.md" },
  { slug: "views", title: "Views", section: "Rendering", summary: "Building views: leaves, elements, regions, control flow and the static/dynamic value wrappers.", file: "views.md" },
  { slug: "mlx", title: "mlx markup and the ppx", section: "Rendering", summary: "JSX-like markup in .mlx files: value inference, components, templates and the escape hatches.", isNew: true, file: "mlx.md" },
  { slug: "lists", title: "Lists", section: "Rendering", summary: "for_ and keyed lists: what survives an update, what moves, and how to key.", file: "lists.md" },
  { slug: "context", title: "Context", section: "Composition", summary: "Values scoped to a subtree, carried by the owner tree.", isNew: true, file: "context.md" },
  { slug: "error-boundaries", title: "Error boundaries", section: "Composition", summary: "Catch render and effect errors below a point, show a fallback, reset.", isNew: true, file: "error-boundaries.md" },
  { slug: "portals", title: "Portals", section: "Composition", summary: "Render into another container while staying owned by this point of the tree.", isNew: true, file: "portals.md" },
  { slug: "resources", title: "Resources and suspense", section: "Async", summary: "Promise-backed data as a signal, refetching on dependency changes, and Suspense fallbacks.", isNew: true, file: "resources.md" },
  { slug: "routing", title: "Routing", section: "Composition", summary: "The location signal, navigation, links, routes and redirects.", file: "routing.md" },
  { slug: "backends", title: "Backends", section: "Platform", summary: "Melange or js_of_ocaml: selecting one, what differs, and the Dom/History/Promise contract.", file: "backends.md" },
  { slug: "devtools", title: "Devtools and reativa-lens", section: "Tooling", summary: "Inspect what the reactive graph does and why; drive an app headlessly from a CLI or an agent.", isNew: true, file: "devtools.md" },
  { slug: "migrating-to-2", title: "Migrating to 2.0", section: "Start", summary: "What changed in 2.0 and how to update: lazy components, interface files, Mlx opens.", isNew: true, file: "migrating-to-2.md" },
];

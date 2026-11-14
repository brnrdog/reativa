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
  { slug: "devtools", title: "Devtools and reativa-inspect", section: "Tooling", summary: "Inspect what the reactive graph does and why; drive an app headlessly from a CLI or an agent.", isNew: true, file: "devtools.md" },
  { slug: "migrating-to-2", title: "Migrating to 2.0", section: "Start", summary: "What changed in 2.0 and how to update: lazy components, interface files, Mlx opens.", isNew: true, file: "migrating-to-2.md" },
];

// The human docs: the sidebar, routes, previous/next links and the static
// copies of index.html that let every route load directly on GitHub Pages.
//
// scripts/generate-docs-index.mjs turns this into website/src/docs_index.ml
// (run it after editing; CI checks it is up to date), and
// scripts/build-site-routes.mjs reads it after `vite build`.
//
// Page fields: title (sidebar label), heading (page title, when it differs),
// path (URL under the site base), body (the OCaml function rendering the
// page, Module.name), lead (one sentence under the title), agent (the slug of
// the matching agent page above, linked as Markdown for coding agents), isNew
// (badged as new in VERSION). Text must be plain ASCII.

export const docs = [
  {
    label: "Get started",
    pages: [
      { title: "Introduction", path: "/docs", body: "Docs_start.intro", lead: "What reativa is, what writing it feels like, and whether it fits your project." },
      { title: "Quick start", path: "/docs/quick-start", body: "Docs_start.quick_start", lead: "Install reativa, set up dune, pick a backend and mount your first view." },
      { title: "Thinking in signals", path: "/docs/thinking-in-signals", body: "Docs_start.thinking", lead: "Components run once; only the parts that read a signal update. Everything else follows from that.", agent: "glossary" },
    ],
  },
  {
    label: "Learn",
    pages: [
      { title: "Signals", path: "/docs/learn/signals", body: "Docs_learn.signals", lead: "Hold a value, read it, change it, and let everything that depends on it follow.", agent: "signals" },
      { title: "Computeds", path: "/docs/learn/computeds", body: "Docs_learn.computeds", lead: "Derive values from signals and keep them in sync without writing the syncing yourself.", agent: "signals" },
      { title: "Effects", path: "/docs/learn/effects", body: "Docs_learn.effects", lead: "Run code outside the signal graph, like timers, storage or logging, whenever its inputs change.", agent: "signals" },
      { title: "Markup and components", path: "/docs/learn/markup", body: "Docs_learn.markup", lead: "Write views as JSX-like markup in .mlx or .re files, and split them into components.", agent: "mlx" },
      { title: "Rendering", path: "/docs/learn/rendering", body: "Docs_learn.rendering", lead: "Show changing text and attributes, handle events, and render one thing or another.", agent: "views" },
      { title: "Lists", path: "/docs/learn/lists", body: "Docs_learn.lists", lead: "Render a list from a signal, and keep each row's DOM when items move.", agent: "lists" },
      { title: "Lifecycle and refs", path: "/docs/learn/lifecycle", body: "Docs_learn.lifecycle", lead: "When a component runs, what gets cleaned up with it, and how to reach its DOM nodes.", agent: "ownership", isNew: true },
      { title: "Context", path: "/docs/learn/context", body: "Docs_learn.context", lead: "Hand a value to everything a component renders, without passing it through every prop.", agent: "context", isNew: true },
      { title: "Error boundaries and portals", path: "/docs/learn/boundaries-and-portals", body: "Docs_learn.boundaries", lead: "Contain failures with a fallback, and render into another part of the page.", agent: "error-boundaries", isNew: true },
      { title: "Async data", path: "/docs/learn/async-data", body: "Docs_learn.async_data", lead: "Turn a promise into a signal that tracks loading, success and failure, and show a fallback meanwhile.", agent: "resources", isNew: true },
      { title: "Routing", path: "/docs/learn/routing", body: "Docs_learn.routing", lead: "Map URLs to views, read route params and navigate without reloading the page.", agent: "routing" },
    ],
  },
  {
    label: "Platform and tools",
    pages: [
      { title: "Backends", path: "/docs/backends", body: "Docs_platform.backends", lead: "Compile with Melange or with js_of_ocaml: what you choose, and what changes.", agent: "backends" },
      { title: "Testing", path: "/docs/testing", body: "Docs_platform.testing", lead: "Test state natively with dune, and measure what an interaction does to the DOM.", agent: "devtools" },
      { title: "Devtools and reativa-inspect", path: "/docs/devtools", body: "Docs_platform.devtools", lead: "See every write, recompute and effect run, and ask why a node shows what it shows.", agent: "devtools", isNew: true },
    ],
  },
  {
    label: "Reference",
    pages: [
      { title: "API reference", path: "/docs/api", body: "Docs_reference.api", lead: "Every module under the Reativa namespace, at a glance." },
      { title: "Glossary", path: "/docs/glossary", body: "Docs_reference.glossary", lead: "The terms the rest of the docs use, and what each one means in reativa.", agent: "glossary" },
    ],
  },
  {
    label: "Project",
    pages: [
      { title: "What's new in 2.0", path: "/docs/whats-new", body: "Docs_reference.whats_new", lead: "What 2.0 adds, the three changes that can break your code, and how to upgrade.", agent: "migrating-to-2" },
    ],
  },
];

// Routes that are not docs pages; the app renders them by hand (app.mlx).
export const otherRoutes = ["/", "/examples"];

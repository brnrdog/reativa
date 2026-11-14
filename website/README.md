# Documentation site

The site published at <https://brnrdog.github.io/reativa/> is itself a reativa
app: `src/app.mlx` is compiled with Melange, and every live demo on the page is
the library running for real.

```sh
opam install . --deps-only --with-test
npm install

npm run docs:dev       # local dev server
npm run docs:build     # static build into _site/
npm run docs:preview   # serve the static build
```

`.github/workflows/pages.yml` builds and deploys the site on every push to
`main`.

## Pages and routes

The site is a single reativa app routed by `Reativa.Router`: a home page,
`/examples`, and the docs under `/docs`. The base path (`/reativa`) lives in
`src/site.ml`; routes in the code are written without it.

| File | Holds |
| --- | --- |
| `docs.pages.mjs` | the registry: every docs page's section, title, path, lead, body function and agent page |
| `src/docs_index.ml` | generated from the registry by `scripts/generate-docs-index.mjs`; do not edit |
| `src/docs_start.mlx`, `docs_learn.mlx`, `docs_platform.mlx`, `docs_reference.mlx` | the docs pages, written as `Doc.block` lists |
| `src/doc.mlx`, `src/ui.mlx` | blocks, code panels and the inline markup of page text (`` `code` ``, `**bold**`, `[label](/route)`) |
| `src/docs_layout.mlx` | sidebar, previous/next, "On this page" |
| `src/home.mlx`, `src/examples_page.mlx`, `src/examples.mlx` | the home page, `/examples`, and the example programs and demos |
| `src/app.mlx` | header, footer and the route outlet |

To add a docs page: write a function returning `Doc.block list` in one of
the docs modules, add an entry to `docs` in `docs.pages.mjs`, and run
`node scripts/generate-docs-index.mjs`. Text in OCaml string literals must be
plain ASCII (Melange reads plain literals byte by byte); use `{js|...|js}` for
anything else.

GitHub Pages serves files, not routes, so `scripts/build-site-routes.mjs`
(part of `docs:build`) copies `index.html` to every route and to `404.html`.
`scripts/smoke-site.mjs` renders every route under jsdom in CI.

## Playground (local only)

The playground is **not part of the published site**: compiling needs the OCaml
toolchain, and there is nowhere online to run it. It still runs against the dev
server, and shipping it again is a matter of adding its two pages back to
`input` in `vite.config.mjs`.

```sh
npm run playground
```

Opens the editor at `/reativa/playground/`. Each run writes the buffer to a
scratch dune project and builds it with the backend picked in the toolbar —
Melange emits ES modules that are bundled and imported by the preview frame,
js_of_ocaml links one self-contained script the frame runs as a plain
`<script>`. Compile errors come back in place of the preview.

Programs are complete `.mlx` modules ending in `View.mount_by_id "app"`. The
preview frame ships a small stylesheet (`.card`, `.row`, `.list`, `.value`,
`.muted`) so short examples look finished. Press <kbd>⌘</kbd>/<kbd>Ctrl</kbd> +
<kbd>Enter</kbd> to run; *Share* copies a link with the program and backend in
the URL fragment.

The js_of_ocaml option needs its own packages:

```sh
opam install reativa-jsoo js_of_ocaml
```

Served without a compile endpoint — a static build, for instance — the editor
falls back to read-only: it shows the examples but cannot run edits.

## Analytics

The published site reports usage to [PostHog], and only when the build is given
a project key — clones, forks and `npm run docs:dev` are silent by default,
because without `VITE_POSTHOG_KEY` the PostHog chunk is not emitted at all.

The Pages workflow reads two values as either repository secrets or repository
variables (Settings → Secrets and variables → Actions):

| Name | Value |
| --- | --- |
| `POSTHOG_KEY` | Project API key, from PostHog → Settings → Project |
| `POSTHOG_HOST` | `https://us.i.posthog.com` or `https://eu.i.posthog.com` |

A missing key never fails the build; the workflow writes a warning to the run
summary instead. For a local build, copy `.env.example` to `.env.local`.

Collected: one pageview per document load plus named events such as
`docs_code_copied`, `docs_syntax_changed` and `docs_section_viewed`, defined at
their call sites in `src/main.js`. Autocapture, session recording and person
profiles are off, and Do Not Track is honoured. The playground has its own
events in `playground/playground.js`, which report only which backend ran, how
big its output was and whether it built — never the program in the editor —
and are dormant while it stays off the published site.

[PostHog]: https://posthog.com

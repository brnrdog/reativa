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

## Playground

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

Compiling requires the OCaml toolchain, so the playground published with the
site is read-only: it shows the examples but cannot run edits.

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
`docs_code_copied`, `docs_syntax_changed`, `playground_compiled` and
`playground_run_failed`, defined at their call sites in `src/main.js` and
`playground/playground.js`. Autocapture, session recording and person profiles
are off, Do Not Track is honoured, and the playground never reports the program
in the editor — only which backend ran, how big its output was and whether it
built.

[PostHog]: https://posthog.com

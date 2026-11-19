## [2.0.1](https://github.com/brnrdog/reativa/compare/v2.0.0...v2.0.1) (2026-11-19)


### Bug Fixes

* **ppx:** keep non-ASCII text in compiled templates intact under Melange ([102dceb](https://github.com/brnrdog/reativa/commit/102dceb938c93f31b95ab4127b60481f29459edc))
* **ppx:** name hoisted templates after their module ([f540e47](https://github.com/brnrdog/reativa/commit/f540e471a4e0fd097e84a856d946e5a47ab1c3e1))
* **ppx:** no module prefix for code parsed without a file name ([4cbd312](https://github.com/brnrdog/reativa/commit/4cbd312a0d15334108916baf70e561cc12d37f98))
* **ppx:** write non-ASCII template text as character references ([eb9f1c9](https://github.com/brnrdog/reativa/commit/eb9f1c9d6f2223dbe1956f53835c09819cf5b71e)), closes [#xE9](https://github.com/brnrdog/reativa/issues/xE9)

# [2.0.0](https://github.com/brnrdog/reativa/compare/v1.2.0...v2.0.0) (2026-11-19)


* feat!: declare the public API in interface files ([f2b1cf3](https://github.com/brnrdog/reativa/commit/f2b1cf3d872c41b1554ee4908382e6f8fb3d74f3))
* feat!: own effects per scope and make every component lazy ([17b1063](https://github.com/brnrdog/reativa/commit/17b10639a28f874a6b97f3ed2c4abfc87f536de1))


### Bug Fixes

* keep the tracking context when a node is created during a first run ([dc4dd17](https://github.com/brnrdog/reativa/commit/dc4dd1754bdcca2b9c077664b49db4b7072adc27))
* **ppx:** compile tags without a View.Mlx helper to templates ([0a3bd1e](https://github.com/brnrdog/reativa/commit/0a3bd1e59ea78c417e3307e672c29214513ef9cd))
* **ppx:** keep opens of View.Mlx from warning once templates stop using them ([d17e9bb](https://github.com/brnrdog/reativa/commit/d17e9bb38e17a3141b87316dbeb7905b92c7de75))
* **ppx:** match Pfunction_cases with its location and attributes ([61bd4b3](https://github.com/brnrdog/reativa/commit/61bd4b3d8e40706018da1df690458fe87f7641df))
* **ppx:** treat calls to local reactive helpers and Signal.get aliases as reads ([d0be171](https://github.com/brnrdog/reativa/commit/d0be171b097b18c02b99321468b46303b6767ed2))
* **signals:** defer a first-run re-run that arrives through an ~equals computed ([fe9e511](https://github.com/brnrdog/reativa/commit/fe9e5111a862c7eb9b6ba4b36107a88bf1756421))
* **signals:** defer an effect's re-run until its first run returns ([1a47de3](https://github.com/brnrdog/reativa/commit/1a47de3e99d771ca1e46cfbe73435800aab278b1))
* **signals:** finalize disposal and release unobserved computeds ([04556dd](https://github.com/brnrdog/reativa/commit/04556ddb4f214f64e703e0dd1a1711ce40f0a3aa))
* **signals:** keep an effect's dependency on a signal it writes in its first run ([6475b01](https://github.com/brnrdog/reativa/commit/6475b0101c82ca55694fc9e26539d37211f0aa82)), closes [#23](https://github.com/brnrdog/reativa/issues/23)
* **view:** a top-level child hole reports what its view reports ([ccb2965](https://github.com/brnrdog/reativa/commit/ccb296509a76bb3125c7d49953d55db566c256bf))
* **view:** keep keyed and for_ lists stack-safe at 10,000 items ([b47f982](https://github.com/brnrdog/reativa/commit/b47f982a5e4c5845ae9a32b6dbf053467951b349))
* **view:** move a keyed row with the content of a region it starts with ([2602be8](https://github.com/brnrdog/reativa/commit/2602be8c4cd967c8ae7c0d3011f80c536f9ae94f))


### Features

* add Devtools, a view of what the reactive graph does ([7f63c71](https://github.com/brnrdog/reativa/commit/7f63c7165e9775660e755b9f1e97aca02b2ae7bf))
* add Resource, over each backend's own promises ([ebf30a2](https://github.com/brnrdog/reativa/commit/ebf30a25acb514d78075b5a2a81d30b036b2ffad))
* **context:** add Context for values scoped to a subtree ([1bf6f90](https://github.com/brnrdog/reativa/commit/1bf6f909c7aab3a232a68e6bf4ee71b2fb815f66))
* **devtools:** add an in-page devtools panel (reativa.devtools) ([4d78556](https://github.com/brnrdog/reativa/commit/4d78556fd8969948f134da41afbee9676a67128f))
* **lens:** add reativa-lens, a CLI and MCP server over Devtools ([30727fe](https://github.com/brnrdog/reativa/commit/30727feb13859e00611f1821897f000e14d7230f))
* **view:** add on_mount, on_cleanup, element refs, error boundaries, portals and suspense ([1a3eb27](https://github.com/brnrdog/reativa/commit/1a3eb27f99da50b369d09bdd297dea2d65fd33a4))
* **view:** typed props for every common element, attrs, optional attributes and SVG ([966762a](https://github.com/brnrdog/reativa/commit/966762a150529234d32882b857cc38424d6aeae7))


### Performance Improvements

* **ppx:** compile mlx element trees to templates ([15f4524](https://github.com/brnrdog/reativa/commit/15f4524501051acd8e5c7ab4da88954ddd4cfcdc))
* **view:** add templates, and clear or append long lists cheaply ([f2c0ccc](https://github.com/brnrdog/reativa/commit/f2c0ccc5fb582b463ab8b4ba27ec11c193224d13))
* **view:** move only displaced rows, skip equal writes, update text in place ([f50988c](https://github.com/brnrdog/reativa/commit/f50988c6f887f7c7090f2b39d15c62ea9ced9e4e))


### BREAKING CHANGES

* code that pattern-matched on View.t or View.attr
constructors, read or wrote a signal's record fields, or used Router or
View internals no longer compiles. Use the documented functions instead:
Signal.peek/Signal.set for a signal's value, View.Attr.* to build
attributes.
* a component used as a JSX tag no longer runs when the
view value is built: its body runs when the view is mounted, untracked,
and everything it creates (effects, computeds, cleanups) is disposed
when the region holding it re-renders or is removed. Code that relied on
a component body running eagerly, or on a signal read in a component
body subscribing the surrounding region, must move that work into the
view (an inline read, View.tracked) or out of the component. Calling
Module.component directly is unchanged.

# [1.2.0](https://github.com/brnrdog/reativa/compare/v1.1.0...v1.2.0) (2026-08-05)


### Bug Fixes

* **ci:** read the PostHog key from secrets as well as variables ([f73aa17](https://github.com/brnrdog/reativa/commit/f73aa17c1b446889a2b4dea241abd70ac22af69b))
* decode route params with the backend's decodeURIComponent ([97d07a0](https://github.com/brnrdog/reativa/commit/97d07a0b10f740c7f085951c94fe7d30615a554d))
* **mlx:** limit runtime child coercion to HTML element tags ([d01c158](https://github.com/brnrdog/reativa/commit/d01c158fb164627451b37a7dd6b20029a16d15d1))
* **router:** bind browser globals through a shipped runtime helper ([70f3c85](https://github.com/brnrdog/reativa/commit/70f3c85c645467a2da1f8daf0681f8165326a835))


### Features

* add a js_of_ocaml backend ([6d9695f](https://github.com/brnrdog/reativa/commit/6d9695f2eb614da1e5cccd95e16dbdecd88843ba))
* add SPA router primitives ([9036fca](https://github.com/brnrdog/reativa/commit/9036fca92c61bb19480cde5ba1d21cfa6c016938))
* build the demos and the router example on js_of_ocaml ([c9f11c3](https://github.com/brnrdog/reativa/commit/c9f11c3f211a21d77deebc0a2c8ba049c933726f))
* **dom:** expose console log ([c80a3ad](https://github.com/brnrdog/reativa/commit/c80a3ad0b5f5f85e4278be0edb5fdea775d89f59))
* **dom:** expose keyboard event key ([8680fe4](https://github.com/brnrdog/reativa/commit/8680fe4daab193f4b2239169036c3b0508074a30))
* **mlx:** auto-track inline signal reads and bare literal children ([c4c6752](https://github.com/brnrdog/reativa/commit/c4c675272b5e5c12be1bdf4e6d82070d185ceb7a)), closes [xote#138](https://github.com/xote/issues/138)
* **mlx:** render bare children without View.text/int/float ([6edfb17](https://github.com/brnrdog/reativa/commit/6edfb179f14cc8c454a95bad8f09ec5e382dd52f)), closes [xote#138](https://github.com/xote/issues/138)
* **mlx:** support component modules and value inference ([0ac6d5b](https://github.com/brnrdog/reativa/commit/0ac6d5be9313e50cacd0fbff4ed489e901a5df90))
* replace custom jsx ppx with mlx ([ce32781](https://github.com/brnrdog/reativa/commit/ce327818b2c97713b6d224c4d921c0590e2b392f))
* unify static and dynamic view values ([e04351c](https://github.com/brnrdog/reativa/commit/e04351c4be61af274486bd6f687400fdc0c66452))
* **view:** add ForEach JSX primitive ([68c3340](https://github.com/brnrdog/reativa/commit/68c3340e880555bd46938478a9a4c54254808148))
* **view:** add keyed list reconciliation ([73fdf5a](https://github.com/brnrdog/reativa/commit/73fdf5a95fb58be8cc919bb31194ee974c760d25))
* **view:** add Show and Maybe JSX primitives ([b3fd4c9](https://github.com/brnrdog/reativa/commit/b3fd4c9fb8111a29d871a22d219629132412ba60))
* **view:** support checked property ([66db898](https://github.com/brnrdog/reativa/commit/66db8981d754801061ea39e60f37666a88c9ac8e))
* **view:** support className attribute ([e4b13c2](https://github.com/brnrdog/reativa/commit/e4b13c270477b966bf599a76e916ea4549f1ba28))
* **website:** redesign docs site with live, copy-pastable examples ([5c643b2](https://github.com/brnrdog/reativa/commit/5c643b2a678710c1db80ffd74deaeacd38ad9ff8))

# [1.1.0](https://github.com/brnrdog/reativa/compare/v1.0.0...v1.1.0) (2026-06-27)


### Features

* **view:** add view layer with JSX support ([1290338](https://github.com/brnrdog/reativa/commit/129033800c003662f95a9ed3b88d7ba8f3ddfdd3))

# 1.0.0 (2026-06-27)


### Bug Fixes

* avoid linting semantic-release commit body ([ea33f95](https://github.com/brnrdog/reativa/commit/ea33f95eb40a631b1f198586aa5b3fdd82ec37b2))


### Features

* signals implementation based on rescript-signals ([53f60d6](https://github.com/brnrdog/reativa/commit/53f60d6edcb16a3267c37f3479fa5073bac71287))

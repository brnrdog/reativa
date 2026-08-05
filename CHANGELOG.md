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

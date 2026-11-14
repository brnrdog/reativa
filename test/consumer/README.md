# Consumer test

A small application built against the **installed** `reativa` and
`reativa-jsoo` opam packages, never against the source tree. CI's packaging job
runs `opam install .` and then:

```sh
cp -r test/consumer /tmp/consumer && cd /tmp/consumer && opam exec -- dune build
```

`melange/` compiles it with the default Melange backend and `jsoo/` links it
with js_of_ocaml. It catches what an in-tree build cannot: a module or value
the interface files hide by mistake, a missing installed file, or a package
that only builds as part of this workspace. The main workspace skips this
directory (see `test/dune`).

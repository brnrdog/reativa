# Releasing

Releases are cut by [semantic-release](https://semantic-release.gitbook.io/)
from the **Release** workflow (**Actions → Release → Run workflow**). The
version comes from the [Conventional Commit](https://www.conventionalcommits.org/)
messages since the last release, and semantic-release acts on whichever branch
the workflow runs from. It tags the release, updates `CHANGELOG.md` and the
`version` in `package.json`, and creates the GitHub release. Users install
reativa with `opam pin` from the tag.

| Channel | Branch | Version shape | Install |
| --- | --- | --- | --- |
| Stable | `main` | `2.1.0` | `opam pin add reativa https://github.com/brnrdog/reativa.git#v2.1.0` |
| Release candidate | `rc` | `2.1.0-rc.1` | `opam pin add reativa https://github.com/brnrdog/reativa.git#v2.1.0-rc.1` |

- **Stable:** run the workflow on `main`.
- **Release candidate:** branch `rc` from `main`, land the work there, and run
  the workflow on `rc`. Each run publishes the next `-rc.N` pre-release
  without touching the stable line. When it is ready, merge `rc` into `main`
  and run the workflow on `main`.

`reativa-jsoo` pins `reativa` to the exact same version, so both packages are
always released together from the same tag.

A breaking change needs a `feat!:`/`fix!:` subject or a `BREAKING CHANGE:`
footer, and a migration note in the commit body: the release notes are built
from it.

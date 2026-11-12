#!/usr/bin/env bash
# Print the public signature of Reativa and compare it with test/api/reativa.api.
#
#   scripts/check-api.sh           fail with a diff if the API changed
#   scripts/check-api.sh --update  rewrite test/api/reativa.api
#
# Needs a byte build of the library first (`dune build`). The print comes from
# the compiler, so it is exactly what a consumer can see.
set -euo pipefail
cd "$(dirname "$0")/.."

objs=_build/default/src/.reativa.objs/byte
if [ ! -f "$objs/reativa.cmi" ]; then
  echo "no build found in $objs: run \`dune build\` first" >&2
  exit 2
fi

ocamlc=${OCAMLC:-ocamlfind ocamlc}
actual=$(mktemp)
trap 'rm -f "$actual"' EXIT
# Collapse runs of whitespace: line breaking differs between compiler versions.
$ocamlc -I "$objs" -i test/api/api.ml | tr -s ' \n' ' ' | sed -e 's/ \(module\|val\|type\|end\) /\n\1 /g' -e 's/ \(module\|val\|type\|end\) /\n\1 /g' >"$actual"

if [ "${1:-}" = "--update" ]; then
  cp "$actual" test/api/reativa.api
  echo "updated test/api/reativa.api"
elif ! diff -u test/api/reativa.api "$actual"; then
  echo >&2
  echo "The public API changed. If that is intended, run scripts/check-api.sh --update and commit test/api/reativa.api." >&2
  exit 1
else
  echo "public API unchanged"
fi

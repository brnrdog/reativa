#!/usr/bin/env bash
# Report a built bundle's size and fail if it exceeds a ceiling.
#
# The size delta between backends is the main reason Melange stays Reativa's
# default, so it should be visible on every run rather than discovered later.
# The measured size always goes to the job summary; the ceiling is only a
# backstop against a runaway regression.
#
# Usage: check-bundle-size.sh <file> <label> <limit-kb>
set -euo pipefail

file=$1
label=$2
limit_kb=$3

if [ ! -f "$file" ]; then
  echo "error: $label bundle not found at $file" >&2
  exit 1
fi

# Both sizes round up, so the two numbers are directly comparable.
round_up_kb() { echo $((($1 + 1023) / 1024)); }

bytes=$(wc -c <"$file" | tr -d ' ')
kb=$(round_up_kb "$bytes")

# gzip is what actually crosses the wire, so report it alongside the raw size.
gz_bytes=$(gzip -9 -c "$file" | wc -c | tr -d ' ')
gz_kb=$(round_up_kb "$gz_bytes")

printf '%s: %s KB (%s KB gzipped), ceiling %s KB\n' \
  "$label" "$kb" "$gz_kb" "$limit_kb"

# A markdown table needs its header emitted before the first row, and each job
# gets its own summary file — so write the header the first time this script
# appends to a given summary, tracked by a marker file beside it.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  header_marker="${GITHUB_STEP_SUMMARY}.reativa-bundle-header"
  if [ ! -f "$header_marker" ]; then
    {
      printf '### Bundle sizes\n\n'
      printf '| Bundle | Raw | Gzipped | Ceiling |\n'
      printf '|---|---|---|---|\n'
    } >>"$GITHUB_STEP_SUMMARY"
    : >"$header_marker"
  fi

  printf '| %s | %s KB | %s KB | %s KB |\n' \
    "$label" "$kb" "$gz_kb" "$limit_kb" >>"$GITHUB_STEP_SUMMARY"
fi

if [ "$kb" -gt "$limit_kb" ]; then
  echo "error: $label bundle is ${kb} KB, over the ${limit_kb} KB ceiling" >&2
  echo "If this growth is intended, raise the limit in .github/workflows/ci.yml" >&2
  exit 1
fi

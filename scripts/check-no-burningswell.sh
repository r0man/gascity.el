#!/bin/sh
# scripts/check-no-burningswell.sh --- the offline leak gate for the manual.
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# REQ-009 / plan W7 (decisions D4, D5) of plans/manual-standard.  The
# private `burningswell' host and city name must never appear in the
# manual sources, the tracked build inputs or the published HTML.  This
# gate greps an explicit tracked-source set with plain POSIX `sh' and
# `grep' (no new runtime dependency); with `--html' it also greps every
# page of the generated split HTML tree.  It prints the offending
# `file:line' and exits non-zero on a leak.
#
# Usage:
#   scripts/check-no-burningswell.sh          # tracked sources only
#   scripts/check-no-burningswell.sh --html   # also doc/gascity.html/**/*.html

set -u

# Resolve the repository root from this script's location so the gate runs
# the same way from a checkout, `make check' and CI.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
cd "$root" || exit 2

html=0
for arg in "$@"; do
  case "$arg" in
    --html) html=1 ;;
    -h|--help)
      printf 'usage: %s [--html]\n' "$0"
      exit 0 ;;
    *)
      printf '%s: unknown argument: %s\n' "$0" "$arg" >&2
      exit 2 ;;
  esac
done

# The explicit tracked-source set (REQ-008, REQ-009, D4).  Only paths that
# exist are checked: a clean checkout has no generated HTML, and a missing
# optional input must not read as a leak.  `doc/screenshots/**' is the
# whole tree, `--html' adds the generated pages.
files() {
  find doc -maxdepth 1 -name '*.texi' -type f 2>/dev/null
  find doc/generated -maxdepth 1 -name '*.texi' -type f 2>/dev/null
  [ -f doc/manual.css ] && printf '%s\n' doc/manual.css
  [ -f doc/lightbox.js ] && printf '%s\n' doc/lightbox.js
  find doc/screenshots -type f 2>/dev/null
  [ -f lisp/gascity-bookmark.el ] && printf '%s\n' lisp/gascity-bookmark.el
  if [ "$html" -eq 1 ]; then
    find doc/gascity.html -type f -name '*.html' 2>/dev/null
  fi
  return 0
}

list=$(mktemp) || exit 2
trap 'rm -f "$list"' EXIT HUP INT TERM
files > "$list"

leaked=0
while IFS= read -r file; do
  [ -n "$file" ] || continue
  # `-I' skips the PNG images under doc/screenshots/; `-i' catches a
  # capitalized reintroduction too.  `grep' is called per file (so a
  # missing optional input is a no-op), which is why the file name is
  # prefixed by hand: the gate must print `file:line'.
  if hits=$(grep -n -I -i 'burningswell' "$file"); then
    printf '%s\n' "$hits" | while IFS= read -r line; do
      printf '%s:%s\n' "$file" "$line"
    done
    leaked=1
  fi
done < "$list"

if [ "$leaked" -ne 0 ]; then
  printf '%s: leaked private host/city name in the manual sources\n' "$0" >&2
  exit 1
fi

printf '%s: OK\n' "$0"
exit 0

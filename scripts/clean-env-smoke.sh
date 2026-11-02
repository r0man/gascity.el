#!/bin/sh
# scripts/clean-env-smoke.sh - repeatable clean-environment smoke test.
#
# ga-x40e made locally spawned gc children default XDG_RUNTIME_DIR to
# /run/user/<uid>.  Half of that fix is only observable against a live
# city, so CI cannot cover it: this script runs the check locally, under
# a clean environment, and is deliberately NOT wired into CI.
#
# Usage:
#
#     scripts/clean-env-smoke.sh [CITY_ROOT]
#
# CITY_ROOT defaults to $GC_CITY, then to the first city.toml found by
# walking up from the repository root.  The script skips cleanly (exit 0
# with a SKIP line) when it cannot find a city or when
# /run/user/$(id -u) does not exist; otherwise it starts Emacs under
# `env -i HOME=... PATH=... TERM=...' (no XDG_RUNTIME_DIR) and:
#
#   1. asserts `(gascity-reader--default-runtime-dir)' is
#      /run/user/$(id -u);
#   2. runs a real `gc status --json' through `gascity-reader-run' from
#      the city root;
#   3. requires exit 0 and a non-empty agents list.
#
# The Emacs half is scripts/clean-env-smoke.el.  It loads gascity from
# this checkout (lisp/ first on EMACSLOADPATH) and needs the same sibling
# beads.el + vui the autotools build uses; the beads_dir and vui_dir
# values are read from a configured Makefile, with BEADS_DIR / VUI_DIR
# and the sibling-checkout default as fallbacks.
#
# See docs/qa/2026-11-02-clean-env-cockpit.md for the interactive pass
# and the manual's "Clean-environment smoke test" section.

set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Resolve the city: explicit argument, then GC_CITY, then walk up.
city=${1:-${GC_CITY:-}}
if [ -z "$city" ]; then
  dir=$repo
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/city.toml" ]; then
      city=$dir
      break
    fi
    dir=$(dirname -- "$dir")
  done
fi

if [ -z "$city" ] || [ ! -f "$city/city.toml" ]; then
  echo "SKIP: no city.toml at or above $repo; pass a city root as the first argument"
  exit 0
fi

uid=$(id -u)
if [ ! -d "/run/user/$uid" ]; then
  echo "SKIP: /run/user/$uid does not exist; cannot exercise the XDG_RUNTIME_DIR fallback"
  exit 0
fi

# The autotools build already resolved the sibling checkouts; prefer its
# answer, then the documented overrides, then the sibling default.
beads_dir=
vui_dir=
if [ -f "$repo/Makefile" ]; then
  beads_dir=$(sed -n 's/^beads_dir = //p' "$repo/Makefile" | head -n 1)
  vui_dir=$(sed -n 's/^vui_dir = //p' "$repo/Makefile" | head -n 1)
fi
: "${beads_dir:=${BEADS_DIR:-$HOME/workspace/beads.el}}"
: "${vui_dir:=${VUI_DIR:-}}"

if [ ! -d "$beads_dir/lisp" ]; then
  echo "FAIL: beads.el not found at $beads_dir/lisp; configure the checkout or set BEADS_DIR" >&2
  exit 1
fi

if [ -z "$vui_dir" ]; then
  vui_dir=$(find "$beads_dir/.eldev" -maxdepth 4 -type d -name 'vui-*' 2>/dev/null \
            | sort | tail -n 1)
fi

if [ -z "$vui_dir" ] || [ ! -d "$vui_dir" ]; then
  echo "FAIL: vui not found; configure the checkout (--with-vui-dir) or set VUI_DIR" >&2
  exit 1
fi

load_path="$repo/lisp:$beads_dir/lisp:$vui_dir"

echo ">>> clean-env smoke: city=$city (env -i, XDG_RUNTIME_DIR unset)"

cd "$city"
exec env -i \
  HOME="${HOME:?HOME must be set}" \
  PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}" \
  TERM="${TERM:-dumb}" \
  EMACSLOADPATH="$load_path" \
  emacs --batch \
  -l "$repo/scripts/clean-env-smoke.el" \
  -f clean-env-smoke-main

#!/bin/sh
# scripts/lint.sh - the CI lint job's exact command, runnable locally.
#
# The CI `lint' workflow runs, on Emacs 31.1:
#
#     make lint
#
# and fails on ANY warning from the doc/re/package linters.  scripts/
# gate.sh deliberately does NOT include lint: the doc linter's checkdoc
# rules are version-dependent (Emacs 29.4/30.2 flag docstring verbs that
# 31.1 accepts), so lint in the shared gate would fail the four-version
# test matrix.  Run THIS before pushing instead - it matches the one
# environment CI's lint job uses, so green here means green there.
#
# `make lint' checkdocs every lisp/*.el (via scripts/lint.el) and, when
# package-lint is installed, runs it too.  Install package-lint for the full
# CI bar; CI does so before running this.  Three pushes went lint-red in two
# days (ga-2rf1r, ga-4hvvi.2, ga-94fvy.1) because only the gate was run.
#
# Usage:  scripts/lint.sh          # from anywhere; cd's to repo root
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ ! -f Makefile ]; then
  echo ">>> lint: bootstrapping autotools (./autogen.sh && ./configure)"
  ./autogen.sh
  ./configure --with-beads-dir="${BEADS_DIR:-$HOME/workspace/beads.el}"
fi

echo ">>> lint: make lint"
make lint

echo ">>> lint: PASS (no warnings)"

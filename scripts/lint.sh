#!/bin/sh
# scripts/lint.sh - the CI lint job's exact command, runnable locally.
#
# The CI `lint' workflow runs, on Emacs 31.1:
#
#     eldev -p -dtT lint
#
# and fails on ANY warning from the doc/re/package linters.  scripts/
# gate.sh deliberately does NOT include lint: the doc linter's checkdoc
# rules are version-dependent (Emacs 29.4/30.2 flag docstring verbs that
# 31.1 accepts), so lint in the shared gate would fail the four-version
# test matrix.  Run THIS before pushing instead - it matches the one
# environment CI's lint job uses, so green here means green there.
#
# Three pushes went lint-red in two days (ga-2rf1r, ga-4hvvi.2,
# ga-94fvy.1) because only the gate was run.  The usual defects: a
# docstring line opening with '(' in column 0, a first line that is not
# a complete sentence, an argument not named in the docstring, a raw
# C-x keycode, an unquoted Lisp symbol, a line over 80 columns.
#
# Usage:  scripts/lint.sh          # from anywhere; cd's to repo root
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo ">>> lint: eldev -p -dtT lint"
eldev -p -dtT lint

echo ">>> lint: PASS (no warnings)"

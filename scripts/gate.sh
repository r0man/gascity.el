#!/bin/sh
# scripts/gate.sh - the standard quality gate for gascity.el.
#
# Runs the two halves of the offline gate that, together, catch the
# regression classes the test suite alone cannot:
#
#   1. make
#        Byte-compiles every lisp/*.el with warnings promoted to errors
#        (byte-compile-error-on-warn t).  This is the ONLY half that catches
#        undefined-function references - a keymap or menu that names an
#        action verb whose forward `declare-function' is missing (see
#        gce-ege, gce-9f6).  A plain byte-compile reports these merely as
#        warnings, and `make check' never sees them at all.
#   2. make check
#        Runs the ERT suite.
#
# Lint is NOT part of this gate: the doc linter's checkdoc rules differ
# between supported Emacs versions (29.4/30.2 flag verbs 31.1 accepts),
# so a lint step here would fail CI on four Emacs versions.  Run the CI
# lint job's exact command before pushing instead: scripts/lint.sh.
#
# Either half failing exits non-zero, so a diff that reintroduces such a
# reference fails the gate before it can reach the refinery.
#
# The whole package is compiled, never an "affected" subset: an undefined
# reference only surfaces when the referencing file is byte-compiled, and
# the action verbs are wired across files, so a partial compile would be
# unsound.  The suite is small enough that the full gate stays fast.
#
# Usage:  scripts/gate.sh          # run from anywhere; cd's to repo root
#
# Wire it into the rig's CI / merge gate via the polecat-work formula var:
#   formula_vars.test_command = "scripts/gate.sh"
set -eu

# Run from the repository root regardless of the caller's cwd.
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# Bootstrap the autotools build on a fresh checkout (the generated files are
# never committed).  BEADS_DIR overrides the default sibling checkout.
if [ ! -f Makefile ]; then
  echo ">>> gate: bootstrapping autotools (./autogen.sh && ./configure)"
  ./autogen.sh
  ./configure --with-beads-dir="${BEADS_DIR:-$HOME/workspace/beads.el}"
fi

echo ">>> gate: make (byte-compile, warnings as errors)"
make

echo ">>> gate: make check (ERT)"
make check

echo ">>> gate: PASS (compile clean + tests green)"

#!/bin/sh
# scripts/gate.sh - the standard quality gate for gascity.el.
#
# Runs the two halves of the offline gate that, together, catch the
# regression classes the test suite alone cannot:
#
#   1. eldev compile --warnings-as-errors
#        Byte-compiles every file with warnings promoted to errors.  This
#        is the ONLY half that catches undefined-function references - a
#        keymap or menu that names an action verb whose forward
#        `declare-function' is missing (see gce-ege, gce-9f6).  Plain
#        `eldev compile' reports these merely as warnings (exit 0), and
#        `eldev test' never sees them at all.
#   2. eldev test
#        Runs the ERT suite.
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

# Run from the repository root regardless of the caller's cwd, so Eldev
# discovers the project correctly.
cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

echo ">>> gate: eldev compile --warnings-as-errors"
eldev compile --warnings-as-errors

echo ">>> gate: eldev test"
eldev test

echo ">>> gate: PASS (compile clean + tests green)"

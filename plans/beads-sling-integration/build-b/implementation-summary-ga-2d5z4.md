---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-x6yz3
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-2d5z4
      hash: bead:ga-2d5z4
      title: "B8 source anchor: gates, tmux/TRAMP e2e, QA report, PR"
      ids:
        - REQ-003
        - REQ-004
        - REQ-008
        - REQ-009
    - path: plans/beads-sling-integration/build-b/implementation-plan.md
      hash: sha256:7bf8cb5ea946b88159f3a058ec16064109240a7e7197909b3d5ca6bdb6fe3cc0
      title: "Approved workstream-B plan; section B8"
      ids:
        - REQ-009
    - path: plans/beads-sling-integration/requirements.md
      hash: sha256:2046b64245d0f4a45b7252f5ca4ff46086e0ee4fa2cef53c4482d6906c12d09f
      title: "AC-B13/AC-B14/AC-B16 verification requirements"
    - path: docs/qa/2026-10-27-beads-sling-e2e.md
      hash: sha256:9078a9715345245b722723f32ace07a3fca4c9aec9f04ba2f64c4d094a7712fa
      title: "Changed: adds the third pass (plain shape over TRAMP, control-target caveat)"
    - path: lisp/gascity-beads-sling.el
      hash: sha256:80c3c6a0621bf03cc1be83942817730d59ae71a6064de32651808e1b016b0152
      title: "Under test (unchanged by B8): the downstream registration module"
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-008
      status: blocked
      rationale: >-
        gascity's provider, additive action entry and after-action refresh are
        implemented and unit-tested, but beads.el's menu provider splicing
        (be-cnn7f) and the unbound V entry (ga-3rrs6) keep the two live clauses
        from being demonstrable. Neither is a sling-path defect.
    - id: REQ-009
      status: covered
---

# Implementation Summary — B8: gates, tmux/TRAMP e2e, QA report, PR (ga-2d5z4)

## Summary

B8 is the verification and landing item for the gascity.el half of the
beads-sling integration. No production code changed: the item ran the
repository gates over the integrated workstream-B tree, drove the real `S`
flow in non-graphical tmux Emacsen against two live cities, recorded the
passes under `docs/qa/`, and opened the pull request.

The B8 stack was already pushed as PR #29
(https://github.com/r0man/gascity.el/pull/29, `beads-sling-b8` → `main`)
by the B8 implementation item `ga-lii6c`; it contains B1–B7 plus B6's ERT
suite and its own two-pass QA report. This item (`ga-2d5z4`) re-ran the
gates on the same tree and added a third independent pass that closes the
one shape gap those passes left: a **plain** (`gc sling TARGET BEAD`) sling
over `/ssh:localhost:/home/roman/bright-lights`, captured with its echo,
runner argv and store route.

## Intended Behavior

- `S` in a `beads-show-mode` buffer opens beads.el's adaptive sling
  transient seeded with the bead; `T` offers the cached `gc` roster as
  qualified `:backend "gc"` targets; `s` dispatches through the registered
  `gc` backend.
- Plain, `--on` and formula-only dispatches build the exact argv shapes
  documented in B3a; a plain dispatch echoes `Slung BEAD to TARGET` and
  leaves `gc.routed_to` on the bead.
- The launch is asynchronous: the echo appears at once, the city cockpit
  repaints with the new session, and no city log is written on success.
- Registration stays cache-only and idempotent; a cold session with no
  city/rig view offers only beads.el's local targets (F4).

## Verification

Gates, from `worktrees/ga-lii6c` with
`BEADS_DIR=/home/roman/workspace/beads.el`:

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 843 tests, 843 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)

$ scripts/lint.sh
lint: package-lint is not installed; skipping package metadata checks (CI installs it)
$ echo $?
0

$ touch doc/gascity.texi && make -C doc
$ echo $?
0
```

The first `gate.sh` run hit the known async-reader flake
(`gascity-test-local-reader-read-async-generic-envelope-stderr-wins`,
beads `ga-r8vmg`/`ga-vfz1j`/`ga-o6ofn`); three following full runs were
843/843. The branch touches neither the reader nor that test.

Interactive e2e (AC-B13/AC-B14, `scripts/e2e-harness.sh` bounds), appended
to `docs/qa/2026-10-27-beads-sling-e2e.md` as the third pass:

| City | Bead → target | Evidence |
| --- | --- | --- |
| `emacs-city` | `ga-spcd7` → `gascity.el/gc.implementation-worker` | `Slung ga-spcd7 to …`; cockpit shows `gc.run-operator-1` active |
| `emacs-city` (instrumented) | `ga-llczk` → same | runner argv `("gc" "sling" "gascity.el/gc.implementation-worker" "ga-llczk" "--json")` |
| `bright-lights` over `/ssh:localhost:` | `bl-85id` → `mayor` | `Slung bl-85id to mayor`; argv `("gc" "sling" "mayor" "bl-85id" "--json")`; store `gc.routed_to=mayor`; `mayor` active |
| `bright-lights` (caveat) | `bl-3xi5` → `core.control-dispatcher` | dispatch landed, but the control dispatcher quarantined the ordinary task bead (`unsupported control bead kind ""`), so the pass repeated with `mayor` |

Cold start: 61 targets/0 gc from the city root, 97/36 from a rig-pinned
bead show buffer — the documented F4 behavior.

## Changed Files

| File | Change |
| --- | --- |
| `docs/qa/2026-10-27-beads-sling-e2e.md` | Third pass: plain shape locally and over TRAMP, runner argv, cockpit evidence, cold-start counts, control-target caveat, cleanup. |
| `plans/beads-sling-integration/build-b/implementation-summary-ga-2d5z4.md` | This summary. |

No beads.el file is changed (AC-B16); the branch diff touches only
gascity.el paths.

## Findings / follow-ups

Already filed by the earlier B8 pass and unchanged here: `be-cnn7f`
(beads.el provider groups unparsed), `ga-6lo2o` (city-scoped cross-store
route not warned), `ga-3rrs6` (contributed `V` action unbound), `be-qrgv8`
(extended formulas offer no vars), `ga-99g35` (workflow latch indexed as
its own run root). The third pass adds no new code finding; the
`core.control-dispatcher` quarantine is a target-selection caveat, not a
sling defect, and is recorded in the QA report.

## PR

- https://github.com/r0man/gascity.el/pull/29 (`beads-sling-b8` → `main`)

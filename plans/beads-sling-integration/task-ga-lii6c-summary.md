---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-h9v28
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
    - path: beads/ga-lii6c
      hash: bead:ga-lii6c
      title: "B8 source anchor: gates, tmux/Emacs e2e pass, QA report, PR"
      ids:
        - REQ-003
        - REQ-004
        - REQ-008
        - REQ-009
    - path: plans/beads-sling-integration/implementation-plan.md
      hash: sha256:9172aff2d78b0a6522bbeb911fc1edd6a4442ba72ad17b67399387dd3253d313
      title: "Approved plan §Workstream B, B8 and the verification table"
    - path: plans/beads-sling-integration/requirements.md
      hash: sha256:2046b64245d0f4a45b7252f5ca4ff46086e0ee4fa2cef53c4482d6906c12d09f
      title: "AC-14 (per-repo gates) and AC-15 (interactive tmux/Emacs pass)"
    - path: plans/beads-sling-integration/context.md
      hash: sha256:c7f5758722b3f9535bd2584f743767e9b014808951d3c3c563f06c0a3e2e8c72
      title: "Grounded input context and operator constraint (forge-over-magit)"
    - path: docs/qa/2026-10-27-beads-sling-e2e.md
      hash: sha256:e272d1389265c0152aff8374b0a9d6b4a1621138e1c16ec62250cedf415d53ac
      title: "Changed: the AC-15 e2e report (both cities, evidence, findings)"
    - path: lisp/gascity-beads-sling.el
      hash: sha256:80c3c6a0621bf03cc1be83942817730d59ae71a6064de32651808e1b016b0152
      title: "Under test (unchanged by B8): the downstream registration module"
  coverage:
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-009
      status: covered
---

# Implementation Summary — B8: gates, tmux/Emacs e2e pass, QA report, PR (ga-lii6c)

## Summary

B8 is the verification and landing item for the gascity.el side of the
beads-sling integration (plan §Workstream B, B8). Nothing in the shipped
module changed: the item ran the repository gates over the integrated branch,
drove the real `S` flow in a non-graphical tmux Emacs against two live cities,
recorded the pass under `docs/qa/`, and opened the gascity.el pull request.

The branch is the full stack, not a fresh B8 base: `beads-sling-b8` starts at
`beads-sling-b7` (B1–B5b + B7 docs) and cherry-picks B6's ERT suite
(`5ca664f`) and its summary (`6670dad`). B7 branched from the shared B1–B5b
base and never contained B6's tests, so the integration commit is what makes
the branch match the plan's "all of Workstream B in one tree" expectation.
The resulting tree is green: compile (warnings as errors), 843/843 ERT, lint.

## Intended Behavior

- `S` in a `beads-show-mode` buffer opens beads.el's adaptive sling transient
  seeded with the bead; the Who picker offers the cached `gc` roster as
  qualified targets, and `s` dispatches through the registered `gc` backend.
- The targeted formula (`--on`) shape creates a workflow root; gascity's run
  view and status dashboard show that root live (`● live`, Moving section).
- A gc refusal (cross-store route) keeps the backend's documented failure
  echo: the first stderr line in the echo area, the full text in
  `*gascity-log: CITY*`, and no store invalidation.
- Registration stays idempotent and cache-only; a cold session offers only
  beads.el's local targets (the documented F4 limitation).

## Coverage

| ID | Status |
| --- | --- |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-008 | covered |
| REQ-009 | covered |

## Changed Files

| File | Change |
| --- | --- |
| `docs/qa/2026-10-27-beads-sling-e2e.md` | New: the AC-15 pass — setup, gates, cold-start observation, remote and local transcripts, findings, cleanup, limitations. |
| `plans/beads-sling-integration/task-ga-lii6c-summary.md` | New: this summary. |

No production code changed by B8. The PR carries the whole Workstream B
stack (B1–B7 commits) plus B6's tests, which is the deliverable the plan
describes for this branch.

## Verification

Per-repo gates, from the item's worktree
(`BEADS_DIR=~/workspace/beads.el`, because the sandbox environment sets
`BEADS_DIR` to the bead store):

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

$ make -C doc
$ echo $?
0
```

One known, pre-existing flake fired during a repeat gate run
(`gascity-test-local-reader-read-async-generic-envelope-stderr-wins`, beads
ga-r8vmg / ga-vfz1j / ga-o6ofn). It reproduces on `main` at the same rate
(2/10 vs 3/10 isolated runs) and the branch touches neither the reader nor
that test. The recorded gate result is a green full run; the flake is noted in
the QA report.

Interactive E2E (AC-15, `scripts/e2e-harness.sh` bounds), recorded in
`docs/qa/2026-10-27-beads-sling-e2e.md`:

| City | Bead → target → formula | Result |
| --- | --- | --- |
| `bright-lights` over `/ssh:localhost:` | `bl-fgg6` → `mayor` → `e2e-demo` | `Launched workflow bl-sx9x`; run view and Moving show it |
| `emacs-city` (local) | `ga-a9i6z` → `gascity.el/gc.run-operator` → `e2e-demo` | `Launched workflow ga-gsqi3`; run view and Moving show it |

The local pass first tried the city-scoped `mayor` target and gc refused the
cross-store route; the refusal surfaced exactly as designed and no root was
created (finding `ga-6lo2o`: the advisory validator does not warn for that
route). Both cities' throwaway beads, workflow roots, convoys and steps were
closed afterwards; the temporary local formula copy was removed.

## Findings / follow-ups

| Finding | Location | Bead |
| --- | --- | --- |
| Downstream provider groups break `beads-dispatch` (`Invalid function: "City"`): providers are appended to `:setup-children` unparsed | beads.el (`beads-menu--provider-children`) | `be-cnn7f` |
| A city-scoped cross-store route gc refuses is not warned by the sling validators | gascity.el (`gascity-sling--cross-store-p`) | `ga-6lo2o` |

Neither blocks the sling path; both are filed with repros and fix directions.
The `[City]` group is beads.el's rendering defect; gascity's provider returns
the documented contract.

## Remaining Risks

- The `e2e-demo` latch workflow does not advance its "Finalize workflow" step
  on its own in either city (0/0 steps); the pass closed the roots and steps
  by hand after collecting evidence, as earlier formula-sling passes did.
- The interactive pass exercised the `--on` (bead + formula) shape. The
  `plain` and targetless `--formula` argv shapes remain covered by ERT only.
- The branch stacks eleven commits over `main`; the Refinery must merge it as
  one PR (beads.el's consuming seam landed separately as
  r0man/beads.el#84).
- The gate's known async-reader flake (above) can make a CI run red for
  reasons unrelated to this branch.

## PR

- gascity.el: https://github.com/r0man/gascity.el/pull/29 (`beads-sling-b8`
  → `main`).

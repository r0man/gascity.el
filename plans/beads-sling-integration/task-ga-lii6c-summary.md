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
      hash: sha256:2e7e6df389ce2bf5cb86af596a38b7459c84b684ec2f1ce59076a73bf6ecdd76
      title: "Changed: the AC-15 e2e report (both cities, evidence, findings, independent re-run)"
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
        gascity's half is implemented and unit-tested, but neither live clause
        is demonstrable: beads.el's beads-menu--provider-children splices the
        provider groups unparsed, so the beads dispatch menu fails with
        `Invalid function: "City"` (be-cnn7f), and the contributed V action is
        advertised in the bead action bar but unbound (ga-3rrs6).
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
A second worker re-ran both gates on the same tree and repeated the
interactive flow independently (scrubbed environment, own tmux Emacs, both
cities), adding the plain-shape dispatch from a city-store bead, the
cross-store advisory evidence and three findings; that pass is the
"Independent re-run" section of the QA report.

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
| REQ-008 | blocked |
| REQ-009 | covered |

REQ-008 is `blocked` rather than `covered`: gascity's half is implemented and
unit-tested (the provider contribution, the additive action entry, the
post-mutation invalidation), but neither live clause is demonstrable end to
end. The `[City]` group cannot render (`?` raises `Invalid function:
"City"`, beads.el `be-cnn7f`), and the contributed `V` action is advertised
in the bead action bar but unbound (`V is undefined`, finding G1). Both are
filed; neither is a defect in the sling path.

## Changed Files

| File | Change |
| --- | --- |
| `docs/qa/2026-10-27-beads-sling-e2e.md` | New: the AC-15 pass — setup, gates, cold-start observation, remote and local transcripts, findings, cleanup, limitations — plus the independent re-run section: the plain shape from a city-store bead, the cross-store advisory, and findings G1–G3. |
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
| `bright-lights`, independent re-run | `bl-dbib` → `mayor` → `e2e-demo-on` | `Launched workflow bl-eh4k`; run view Active row; `gc.var.note` in the store |
| `emacs-city` (local) | `ga-a9i6z` → `gascity.el/gc.run-operator` → `e2e-demo` | `Launched workflow ga-gsqi3`; run view and Moving show it |
| `emacs-city`, independent re-run, plain shape | `ec-rqj9v` → `mayor` (no formula) | `Slung ec-rqj9v to mayor`; `gc.routed_to=mayor`; auto-convoy `ec-ojdg0` |

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
| G1: the contributed `V` cockpit action is advertised in the bead action bar but unbound (`V is undefined`) | gascity.el (`gascity-beads-sling--actions`) | `ga-3rrs6` |
| G2: `bd formula show` drops vars inherited through `extends`, so `build-basic` shows no vars or missing-var warning in the beads transient | beads.el (`beads-sling--fetch-formula` / formula-show) | `be-qrgv8` |
| G3: a workflow-latch step is indexed as its own run root, so the real root renders `Steps 0/0` (the `e2e-demo` limitation above) | gascity.el (`gascity-runs-index`) | `ga-99g35` |

None blocks the sling path (F1/G1 are message/menu surface, G2 affects which
formulas can fill vars from the beads UI, G3 is a pre-existing run-view
classification); all are filed with repros and fix directions. The `[City]`
group is beads.el's rendering defect; gascity's provider returns the documented
contract.

## Remaining Risks

- The `e2e-demo` latch workflow does not advance its "Finalize workflow" step
  on its own in either city (0/0 steps, and the latch row surfaces as its own
  waiting run); the pass closed the roots and steps by hand after collecting
  evidence. G3 (`ga-99g35`) records the run-view classification behind the
  `0/0` reading.
- A formula that inherits its vars through `extends` (`build-basic` →
  `build-base`) offers no vars in the beads transient (G2, `be-qrgv8`), so
  REQ-004's var entry and REQ-005's missing-var warning are demonstrated live
  only for formulas that declare their own vars (`e2e-demo`, `e2e-demo-on`);
  the `--var` passthrough itself is confirmed (store `gc.var.note`) and by the
  B6 ERT argv tests.
- REQ-008 is reported `blocked` (F1 + G1) instead of `covered`.
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

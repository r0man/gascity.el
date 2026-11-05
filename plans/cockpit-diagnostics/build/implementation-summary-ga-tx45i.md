---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-4hdav
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: blocked
trace:
  upstream:
    - path: beads/ga-tx45i
      hash: "bead:ga-tx45i"
      title: "Acceptance pass, QA report and final gates for the diagnostics batch"
    - path: plans/cockpit-diagnostics/build/requirements.md
      hash: "sha256:f1264856fbd255221baec68edccf8d18a4da7c29c09ea2067277d83f15a5451c"
      title: "Batch requirements (REQ-001..REQ-007, AC-1..AC-7)"
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
    - path: plans/cockpit-diagnostics/build/implementation-plan.md
      hash: "sha256:f7772bfc777b26b0a7c8f7a6630c78ebc8df37fef522eda1cfb377d483dd28f8"
      title: "Batch implementation plan (Verification, Decisions 1-5)"
    - path: lisp/gascity-dashboard.el
      hash: "git:b3733a9"
      title: "Trial-integration revision of the cockpit changes (W1+W3+W5)"
    - path: lisp/gascity-runs.el
      hash: "git:b3733a9"
      title: "Trial-integration revision of the Runs card and facts line (W1+W2)"
    - path: lisp/gascity-run.el
      hash: "git:b3733a9"
      title: "Trial-integration revision of the run-detail failure line (W1)"
    - path: lisp/gascity-event.el
      hash: "git:b3733a9"
      title: "Trial-integration revision of the event drawer fields (W4)"
    - path: docs/qa/2026-11-05-cockpit-diagnostics.md
      hash: "sha256:54d65fb2a143d443917d30b9dbefbb9a686f961271b57a05d0eed15242136d71"
      title: "Acceptance pass report (this pass)"
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: blocked
      rationale: "gc.failure_class renders, but close_reason never does: gc delivers it as payload.bead.metadata.close_reason and gascity-event--bead-why-fields reads only a top-level bead.close_reason. Over 24h of emacs-city events, 0 of 1124 bead.closed payload beads (0 of any event type) carry the top-level key while 917 carry metadata.close_reason (1301 across all event types). Fix belongs to W5 ga-4odv8."
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: blocked
      rationale: "W6 ga-bc5tg is open with an empty worktree at 4ed9d40: doc/gascity.texi:1909 still has the stale 'stage Rev… · step build-basic.re… · failure control_dispatc… · worker contr…' example, NEWS.md has no entry, and doc/images/ are the pre-batch renders. make -C doc passes only because the source is unchanged."
    - id: REQ-007
      status: blocked
      rationale: "scripts/gate.sh (978 tests, 0 unexpected) and scripts/lint.sh are clean on the trial integration, but the batch has no integrated branch (none of the five item commits is reachable from origin/main) and the live acceptance pass fails REQ-004/REQ-006, so the acceptance criterion is not met. Screenshot verify passed for cockpit,runs,run-detail (4 images byte-identical)."
---

# Implementation Summary — Cockpit and run/event diagnostics acceptance (W7)

## Summary

This step executed W7, the acceptance pass for the cockpit/run-diagnostics
batch, on a **trial integration** of the five implementation items, because no
integration exists yet: `origin/main` (`4ed9d40`) contains none of the five
fixes and none of their commits is pushed. The five item commits
(`af17537`, `c569d86`, `7f35b9d`, `bf470e9`, `feaaf0b`) were cherry-picked in
order into the throwaway worktree `worktrees/ga-tx45i-integration`; all
applied with auto-merges only (no conflicts).

The batch's five behaviours were exercised in tmux `emacs -Q` sessions
against the deterministic fixture city, live `emacs-city` (read-only) and
`bright-lights` over TRAMP. Four of the five behave as specified on real
data; the fifth (REQ-004) is half-broken, and the docs/NEWS/screenshots item
(W6) has not started. The pass therefore **fails**: see "Verification" and
`docs/qa/2026-11-05-cockpit-diagnostics.md`.

## Intended Behavior

The batch was to deliver five operator-facing diagnostics behaviours:

- a failed-run cockpit Needs-you item with a real drawer (run, class, failed
  step, first reason line with full text in `help-echo`, `RET`/`b` hints) and
  the failure class in the row, class-first then rig then city (REQ-001);
- Runs history facts lines whose four values (`stage`, `step`, `fail`, `work`)
  are budgeted separately from their labels at a fixed 78 columns (REQ-002);
- every failure/close-reason render fitted with `gascity-ui-truncate` /
  `gascity-ui-fit`, cut with `…` and the full text in `help-echo` (REQ-003);
- Events detail showing `close_reason` and `gc.failure_class` for
  `bead.closed`/`bead.updated` payloads (REQ-004);
- stalled agents whose reason survives a long qualified name and whose row and
  drawer show the stall age, lease and heartbeat when present, `unknown` when
  not (REQ-005);
- with docs/NEWS/screenshots updated (REQ-006) and all gates clean (REQ-007).

## Changed Files

This implementation step (W7) produces evidence, not source changes. The
deliverable worktree `worktrees/ga-tx45i` (detached at `4ed9d40`) adds only:

- `docs/qa/2026-11-05-cockpit-diagnostics.md` — the acceptance report:
  verdict, integration recipe, gate results, captured rows/drawers, the
  `close_reason` payload survey, deviations and reproduction commands.
- `plans/cockpit-diagnostics/build/implementation-summary-ga-tx45i.md` —
  this summary.

The trial integration worktree (throwaway, not a deliverable branch) contains
the five item commits on top of `4ed9d40`:

- `a2c2e0d` W1 failure-line fitting (ga-f7nvv): `lisp/gascity-dashboard.el`,
  `lisp/gascity-run.el`, `lisp/gascity-runs.el`, `lisp/test/gascity-runs-test.el`
- `594f38e` W2 facts-line budgeting (ga-40i2t): `lisp/gascity-runs.el`,
  `lisp/test/gascity-runs-test.el`
- `32975f9` W3 failed-run item and drawer (ga-lya6t): `lisp/gascity-dashboard.el`,
  `lisp/test/gascity-cockpit-test.el`
- `223db30` W4 event drawer fields (ga-4odv8): `lisp/gascity-event.el`,
  `lisp/test/gascity-comms-test.el`
- `b3733a9` W5 stalled-agent visibility (ga-i83g4): `lisp/gascity-dashboard.el`,
  `lisp/test/gascity-cockpit-test.el`

No file was edited in the launcher checkout.

## Verification

First verification command (whole-package gate on the trial integration):

```sh
cd worktrees/ga-tx45i-integration && ./configure --with-beads-dir="$HOME/workspace/beads.el"
scripts/gate.sh
```

Observed: **PASS** — byte-compile with warnings-as-errors clean; `make check`
"Ran 978 tests, 978 results as expected, 0 unexpected" (41.5 s).
`scripts/lint.sh` also passed (exit 0, no warnings; `package-lint` not
installed locally, so its metadata checks were skipped).
`make -C doc` passed (nothing to rebuild — the Texinfo source is unchanged,
which is part of the W6 finding).
`TMPDIR=/tmp/ga-tx45i GASCITY_SHOT_STAGING=/tmp/ga-tx45i/staging
doc/screenshots/capture.sh --verify cockpit,runs,run-detail` **passed**
(4 images byte-identical over two runs, coverage ok, 44 non-selected images
untouched).

Interactive acceptance (see the QA report for the captured panes):

- cockpit, fixture city: failed-step row carries `code_review` in its right
  column and its drawer shows run/step/class/reason;
- cockpit, `bright-lights` over TRAMP with a 24 h window: failed-run row
  `■ run hw-cz23 build-basic failed 22h hard` and drawer
  `run / class hard / step build-basic.review / reason control_dispatch_error /
  RET run detail b root bead`;
- Runs history: line width **78**, `help-echo` holds the full
  `integration_conflict: …` value; Failed card second line width **78** and
  ends in `…` with the full close reason in `help-echo`;
- run detail `implement` step drawer: `failure` line width **78**, full reason
  in `help-echo`;
- Events, `bead.closed` ga-j8cnx: `gc.failure_class integration_conflict`
  renders, **no `close_reason` line** (the payload has no top-level value).

Coverage (matches `trace.coverage`):

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | blocked |
| REQ-005 | covered |
| REQ-006 | blocked |
| REQ-007 | blocked |

Final proof command (artifact validation, after recording the summary path on
the workflow root):

```sh
cd /home/roman/workspace/gascity.el
GC_BEAD_ID=ga-u565r .gc/scripts/checks/build-artifact-valid.sh
```

Observed: see the close reason; the summary was validated locally with the
same command before `gc.outcome` was set.

## Remaining Risks

- **Blocking:** the batch is unintegrated. Publish/finalize must merge (or the
  items must be pushed and landed) before any consumer sees the fixes; a
  retry of this item should first confirm `origin/main` (or the batch's
  integration branch) contains all five commits.
- **Blocking:** REQ-004's `close_reason` needs W5 to read
  `metadata.close_reason` (preferring a top-level value when one exists).
  Without it the Events view can never explain a closed bead's reason on real
  gc data.
- **Blocking:** W6 (ga-bc5tg) must write the manual/NEWS and regenerate
  `cockpit-dark`, `cockpit-light`, `runs-dark`, `run-detail-dark` plus thumbs;
  the capture pipeline is deterministic on the new code, so the regeneration
  itself is low-risk, but the manual example must be diffed against the tested
  facts line.
- **Low:** no city had a stalled agent during the pass (fixture agents
  `stopped`; bright-lights 3 idle/2 stopped; emacs-city 4 running/1 idle/4
  stopped), so REQ-005's live render was not observed; it rests on the ERT
  coverage (join, 45+ character name, `unknown`, lease/heartbeat).
- **Low:** the fixture city has no supervisor, so `gc events --since` fails
  there and the fixture's Activity/Events sections are empty; the Events
  acceptance therefore ran on `emacs-city`. This is a pre-existing fixture
  limitation, not a batch regression.
- **Low:** `package-lint` is not installed in this environment, so the local
  lint run did not include the package-metadata half of the CI bar.

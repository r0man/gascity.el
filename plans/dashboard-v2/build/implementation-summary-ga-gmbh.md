---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-sd7e
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
    - path: beads/ga-gmbh
      hash: bead:ga-gmbh
      ids:
        - ga-7pq7
    - path: plans/dashboard-v2/implementation-plan.md
      hash: sha256:1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f
    - path: plans/dashboard-v2/requirements.md
      hash: sha256:912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07
    - path: lisp/gascity-dashboard.el
      hash: sha256:699cd6bc1b3dc2089c352a6c660dc236b5bb89f6aa228b991fbf9552742495f8
    - path: lisp/gascity-run.el
      hash: sha256:0b3b64d0507151e74ae26630eb769af0fd59c177ddceedc59963953552dec5ce
    - path: lisp/gascity-reader.el
      hash: sha256:43127076ff509a5258738e1972b16cc841b790070e502e3e27e83442dfda4860
    - path: lisp/test/gascity-test.el
      hash: sha256:5813325fdbfd2dd49fd8f9ff83ac141df04b644ea8d3305b078ad22e61e8003e
    - path: plans/dashboard-v2/delivery-report.md
      hash: sha256:0e73a9672c62f1761c79c225f7ce07df3266fa0db29d172798598d67c03600fd
    - path: docs/qa/2026-09-24-ga-gmbh-dashboard-v2-s5-e2e.md
      hash: sha256:4bc90f0eb2531b65bbfcb2585b59f8462a00f30f16ee545f1d8dddd57608ce0d
  coverage:
    - id: ga-7pq7
      status: covered
      rationale: >-
        S5 verified every acceptance criterion of requirements.md once
        against the live cities; the live checks found three real
        defects (runs invisible from a real city, wrong progress
        fractions, step grouping missing the live step shape) plus an
        unwired RET drill-in and a phantom footer key, all fixed in
        this pass and covered by six new ERT tests; capability beads
        ga-ik26 (costs JSON) and ga-jcv1 (pending interactions) are
        filed; the delivery report and the TRAMP e2e report are
        recorded at the artifact root / docs/qa.
---

# Implementation Summary: S5 — Verification, e2e, capability beads, delivery report (source anchor ga-gmbh)

## Summary

Completed S5 of the approved Dashboard v2 plan
(plans/dashboard-v2/implementation-plan.md §S5) for source anchor bead
ga-gmbh, in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-gmbh`. S1–S4 were already
merged in this worktree; S5 ran the acceptance pass against the live
cities, found and fixed three live-data defects plus two wiring bugs in
the earlier stages' code, and produced the delivery report and the TRAMP
e2e record. Gate: `scripts/gate.sh` PASS (byte-compile with
`--warnings-as-errors` clean + 413/413 ERT tests, 6 of them new).

## Intended Behavior

- The city dashboard's **Runs** section lists open workflow runs from the
  LIVE city with run id, formula, phase, a correct progress fraction
  (closed/total, counting closed steps), current step and updated time;
  closed runs render as a dim count line.
- `RET` on a run row opens the **run detail** (full step graph with
  id/title/kind/status/assignee, progress header, joined input convoy),
  scoped to the run's owning rig store.
- The **Activity** feed renders `gc events` JSONL with a user-filterable
  type exclusion; the **mail** header shows the unread count with `m`
  into the city-scoped inbox; needs-you is honest (no `awaiting-input`
  path); costs render as a dim pointer with a filed capability bead.
- Everything works identically over TRAMP
  (`/ssh:localhost:/home/roman/bright-lights`), with zero HTTP and no
  synchronous `gc` in render/eldoc/prefix paths.

## Changed Files

- `lisp/gascity-dashboard.el` — rig fan-out for the in-progress/blocked
  censuses (`gascity-dashboard--bd-list-rigs-async`, rows stamped
  `(gascity-rig . NAME)`); a dedicated full-status fan-out for the Runs
  census (closed steps must count toward progress); `--workflow-runs`
  buckets steps by `gc.root_bead_id` (the live shape — the root key
  never reaches the steps); run rows stamp `gascity-run-rig`;
  `gascity-dashboard-activate` dispatches a run row to `gascity-run-show`
  with the owning rig; `e` bound to the events filter (footer legend).
- `lisp/gascity-run.el` — `gascity-run-show`/`gascity-run-app` take an
  owning rig; the run view's `bd list` read scopes `--rig` to it; the
  not-found fallback renders the city's affected-list rows (each row
  re-drills with its own rig stamp); `gascity-run-activate` re-drills
  affected rows instead of opening beads.el.
- `lisp/test/gascity-test.el` — stub keys updated for the per-rig argv;
  six new tests (fan-out union/stamp/order, partial-failure degradation,
  no-rigs empty resolve, full-status runs read, live step shape, RET
  dispatch, run-show rig scoping).
- `plans/dashboard-v2/delivery-report.md` — sections added, exact CLI
  recipes, the two documented CLI gaps with their dim-pointer treatment.
- `docs/qa/2026-09-24-ga-gmbh-dashboard-v2-s5-e2e.md` — the live e2e
  acceptance record (local + TRAMP, keystroke flow, harness bounds).

Capability beads filed in this workflow (still open, by design):
`ga-ik26` (costs JSON surface), `ga-jcv1` (pending-interactions surface).

## Verification

- **First verification command**: `scripts/gate.sh` (from the worktree) —
  byte-compile with `--warnings-as-errors` + full ERT suite.
  Result after the fixes: PASS, 413/413 tests (first S5 run: 406/406 but
  with three live-data defects unfixed; the fixes added 6 tests and kept
  the gate green).
- **Final proof command** (acceptance, live cities through
  `scripts/e2e-harness.sh` bounds): fresh `emacs -nw -Q` in tmux
  (`gce-e2e-s5`) with the worktree `lisp/` on `EMACSLOADPATH` —
  emacsclient evals + keystroke flow over `/home/roman/emacs-city`
  (Runs: `ga-sd7e do-work 1/6 · ga-lbl7`, `ga-uxhh build-basic 12/42`,
  44 closed runs hidden; `RET` drill-in renders the 42-step graph of the
  live build-basic run at 12/42 with the joined input convoy) and
  `/ssh:localhost:/home/roman/bright-lights` (TRAMP: byte-identical
  rendering in both access modes, live Activity, `m` opens the
  city-scoped mail inbox, no sync stalls). Result: PASS — full record in
  `docs/qa/2026-09-24-ga-gmbh-dashboard-v2-s5-e2e.md`.
- Honesty greps: `rg -in "url|http" lisp/gascity-dashboard.el
  lisp/gascity-reader.el` → doc comments only; no supervisor API usage;
  no synchronous `gc` added in render/eldoc/prefix paths.

## Remaining Risks

- The Beads → **Ready** census still reads the city HQ store (`bd ready`
  is city-store-scoped, capped at 100 rows by gc); the in-progress,
  blocked and Runs censuses now fan out over rig stores. A ready-census
  fan-out is a follow-up candidate (noted in the delivery report).
- The rig fan-out issues one async read per rig per census (rig list +
  N per-rig reads, twice per refresh); fine for the 2–4 rigs these cities
  carry, but an aggregate `gc bd list --rig all` (gc CLI gap, same family
  as the filed capability beads) would remove the extra reads.
- The default `gce-e2e` tmux session is contended by bright-lights' demo
  automation (bd.dog restarted it mid-pass); the acceptance ran under a
  dedicated session. Worth a gc-side look if e2e passes keep colliding.

| ID | Status |
| --- | --- |
| ga-7pq7 | covered |

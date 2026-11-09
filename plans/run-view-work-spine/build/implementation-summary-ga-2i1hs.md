---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-nvipz
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
    - path: beads/ga-2i1hs
      hash: bead:ga-2i1hs
    - path: plans/run-view-work-spine/implementation-plan.md
      hash: sha256:54eea7c01c944a3dcbab1dcf941deda57bc3e2a18331b999d3fdac64340b5527
      ids:
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-010
    - path: plans/run-rendering-alternatives/design.md
      hash: sha256:823b7c92df7d88a5562176d0b29be42c527eee117b52f5ace83c78b7d255ed50
    - path: lisp/gascity-runs.el
      hash: sha256:d29e7a3b4cfefc9d8a353ccf0f82517905e9d1e11bd7627a25bc1613e483f308
    - path: lisp/gascity-dashboard.el
      hash: sha256:2ba85608a5d383cb81f7ce60d6cd8ef39d00238bcf88b6e5c256cb7b5b89c58c
    - path: lisp/test/gascity-runs-test.el
      hash: sha256:4dbd7544218cf3b4c14de3fc16e445a065f3c90b4d891ab8cbcc9714e644a6ef
  coverage:
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-010
      status: covered
---

# WP-0 — Model: ordered deliverable map, bead lookup, labeled counters

## Summary

Implemented plan WP-0 (`plans/run-view-work-spine/implementation-plan.md`
§WP-0, design §4.3 phase 0) in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-2i1hs`, on top of
`origin/main` 5c63beb, as one commit:

`feat(run-view): join drain members to their business beads (ga-036m5)`.

The Runs model is now deliverable-first without any new `gc` call and
without a store-key change: `gascity-runs-index` joins every drain
member root to its business bead in one pass over the payload it
already has, exposes a bead-by-id map, and the shared ladder has one
total order helper used by both its sort and its `:name`.  Pure
accessors (`gascity-runs-bead`, `-deliverables`, `-work-units`,
`-unit-counts`) are the surface the detail (WP-1) and card (WP-2)
items consume.

The five plan-mandated ERT cases were written first and observed red
(`void-function gascity-runs-bead`), then green.

## Intended Behavior

- **One shared order (0.1).** `gascity-dashboard--step-ref (bead
  formula)` is the single total helper: `gc.step_ref` with the formula
  prefix stripped when it carries it, else the raw non-empty
  `gc.step_ref`, else `gc.step_id`, else the bead id.  It can never
  signal, so a foreign or unknown-kind step no longer breaks the
  ladder (the old `:name` was a bare `substring`, which errored on a
  bead without a prefixed ref).  `gascity-dashboard--ladder` sorts by
  `(depth, step-ref, bead-id)` and computes its `:name` through the
  helper.  `gascity-run-tree`'s child sort is untouched
  (`depth, attempt, id`), so iteration order never moves.
  `gascity-runs--step-ref` is the runs-facing name of the same
  function (`defalias`); the implementation lives beside the ladder it
  orders because `gascity-runs.el` loads `gascity-dashboard.el`, not
  the reverse.
- **Index additions (0.2).** In the same single pass that populates
  `:drains`, `gascity-runs-index` now also records each member root's
  `gc.drain_member_id`, `gc.drain_index`, `gc.drain_count` and the
  member bead.  It returns:
  - `:beads` — id → bead, first write wins, over every bead in the
    read;
  - `:deliverables` — drain step id → ordered list of
    `(:business-id ID :member-id ID :member ROOT :index N :count N)`.

  The wire values are strings (`"0"`, `"8"`); they are parsed with a
  tested numeric check rather than a bare `string-to-number` (which
  returns 0 for `"abc"`), and an absent or non-numeric value is nil,
  which sorts last.  The list is sorted by index, then business id,
  then member id, so a shuffled read always yields the same order.
  `:drains` is unchanged (the ladder, `gascity-runs-member-roots` and
  the drawers keep reading it).  `:beads` and the ordering rule are
  documented in the `gascity-runs-index` docstring (REQ-003).
- **Pure accessors (0.3).**
  - `gascity-runs-bead (index id)` — hash lookup; nil is legal.
  - `gascity-runs-deliverables (index root)` — one
    `(:step STEP :members MEMBERS)` per ladder step with members, in
    ladder order; nil for a formula with no drain and for an inline
    drain.
  - `gascity-runs-work-units (index root)` — the ordered spine: a
    `:drain` row per step with member roots, one `:deliverable` row per
    member (`:business` is the joined bead, nil when the payload has
    none while `:business-id` is kept), and a `:work` row for an inline
    drain and every other top-level step.  Each row carries
    `:unit-kind :step :node :business :business-id :member
    :member-id :index :count :order`.  `:node` is the step's annotated
    tree node (`gascity-run-tree` + `gascity-run-annotate`, memoized in
    the index), so a WP-1 `:work` row can render today's
    `gascity-run--step-lines` unchanged.
  - `gascity-runs-unit-counts (index root)` — `(:steps (DONE . TOTAL)
    :deliverables (DONE . TOTAL) :beads N :in-flight N :failed N)`.
    Totals are never mixed: steps come from the ladder, deliverables
    from the member rows (done = the member run is done), beads from
    the run's graph, and `:in-flight`/`:failed` count work units whose
    state is active/failed — drain header rows are never counted, so a
    member is not counted twice (REQ-010).
- No new `gc` call, no store key, no timer, no render-path I/O: the
  index remains a pure function of the payload the Runs view and the
  run detail already load.

## Changed Files

- `lisp/gascity-runs.el` — `gascity-runs--step-ref` (alias),
  `gascity-runs--wire-number`, `gascity-runs--deliverable-less-p`, the
  extended `gascity-runs-index` (with its `:beads`/`:deliverables`
  docstring), and the new accessors `gascity-runs-bead`,
  `gascity-runs-deliverables`, `gascity-runs--tree`,
  `gascity-runs--unit-state`, `gascity-runs-work-units`,
  `gascity-runs-unit-counts`; forward `declare-function`s for
  `gascity-run-tree`/`gascity-run-annotate`.
- `lisp/gascity-dashboard.el` — `gascity-dashboard--step-ref`, the
  ladder's `:name` routed through it, and the ladder sort extended to
  `(depth, step-ref, bead-id)`; docstring states the total order.
- `lisp/test/gascity-runs-test.el` — the `gascity-runs-test--workflow-step`
  and `gascity-runs-test--deliverable-beads` fixtures plus the five new
  ERT cases: `gascity-test-runs-index-deliverables-ordered` (eight
  members, out-of-order string indexes `"0"`…`"7"`, first seven `done`,
  last `:index 7 :count 8` and active, no invented id, plus the
  separate counts), `...-index-deliverables-missing-business` (id kept,
  nil business, one row), `...-inline-drain-one-unit`,
  `...-no-drain-no-deliverables` (flat `do-work` and standalone
  `review`), and `...-order-step-ref-tiebreak` (step ref beats bead id
  at equal depth, dependency cycle neither loops nor drops a node).
- `plans/run-view-work-spine/build/implementation-summary-ga-2i1hs.md`
  — this artifact.

## Verification

First verification command (from the item worktree root
`/home/roman/workspace/gascity.el/worktrees/ga-2i1hs`):

```sh
find lisp -name '*.elc' -delete && scripts/gate.sh
```

Observed: **PASS** — `>>> gate: make (byte-compile, warnings as errors)`
clean (no warnings), and `>>> gate: check (ERT)` — `Ran 1062 tests,
1062 results as expected, 0 unexpected`, then `>>> gate: PASS`.

Targeted suite before the implementation (red), same command after
(green):

```sh
EMACSLOADPATH="$HOME/workspace/beads.el/lisp:$HOME/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0:$EMACSLOADPATH:" \
  emacs --batch -Q -L lisp -L lisp/test -l ert \
    --eval '(progn (require (quote gascity-test-helpers)) (load "lisp/test/gascity-runs-test.el" nil t) (ert-run-tests-batch-and-exit "\\`gascity-test-runs-\\(index-deliverables\\|inline-drain-one-unit\\|no-drain-no-deliverables\\|order-step-ref-tiebreak\\)"))'
```

Observed red before the implementation: `Ran 5 tests ... 5 unexpected`
(each `void-function gascity-runs-bead`/`gascity-runs-work-units`).
Observed green after: `Ran 5 tests, 5 results as expected, 0
unexpected`.  The pre-existing cockpit/runs ladder goldens were not
updated: all 1062 tests pass unchanged, so no intentional golden moved.

Final proof command:

```sh
scripts/lint.sh
```

Observed: **PASS** — checkdoc clean on every source file;
`lint: package-lint is not installed; skipping package metadata checks
(CI installs it)`.

Pure-payload proof (no new read):

```sh
git diff | grep -n 'gascity-reader-\|gascity-store-\(use\|fetch\|subscribe\)'
```

Observed: no output — this change adds no `gascity-reader-*` call and
no store read; the index is a pure function of the payload already in
hand.

Artifact validation (from the launcher rig root, the rig-relative
artifact resolved against the worktree):

```sh
cd /home/roman/workspace/gascity.el && \
  GC_RIG_ROOT=/home/roman/workspace/gascity.el/worktrees/ga-2i1hs \
  GC_BEAD_ID=ga-zummf .gc/scripts/checks/build-artifact-valid.sh
```

Observed: `build artifact valid: schema=gc.build.implementation-summary.v1`.

## Remaining Risks

- `:node` reaches `gascity-run-tree`/`gascity-run-annotate` through
  forward declarations (the tree builder lives in `gascity-run.el`,
  which loads after `gascity-runs.el`).  That is the established
  load-order direction for this package (`gascity.el` loads
  `gascity-runs` then `gascity-run`), and both functions are only
  called at render time, but a consumer that loads `gascity-runs.el`
  *without* `gascity-run.el` and calls `gascity-runs-work-units` would
  fail; the tests load the whole package, as the view does.
- `gascity-runs-unit-counts` defines deliverable "done" by the member
  run's state, not by the business bead's status.  Drift (business
  closed while the member failed, or the reverse) is the plan's later
  verdict and is deliberately not folded into these counters.
- `:in-flight`/`:failed` count work units (work and deliverable rows),
  never drain headers.  That matches the design's
  `5/10 steps · 7/8 deliverables · 1 in flight · 0 failed` line, but
  WP-1 must render the words and must not re-add drain rows to the
  totals.
- The rest of the plan is untouched: no run-detail or card rendering,
  no keymap, no manual/NEWS, no screenshot or tmux/TRAMP acceptance
  pass here.  WP-1/WP-2/WP-3 and the end-to-end pass are the following
  work items, so this change is model-only and invisible in the UI
  until they land.
- `plans/run-view-work-spine/implementation-plan.md` (the plan this
  item follows) is drafted but still untracked in the launcher
  checkout, so it is cited by absolute upstream hash only; it is not
  part of this commit.

| ID | Status |
| --- | --- |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-010 | covered |

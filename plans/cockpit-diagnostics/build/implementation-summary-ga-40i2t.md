---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-lblkt
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
    - path: beads/ga-40i2t
      hash: bead:ga-40i2t
    - path: plans/cockpit-diagnostics/build/requirements.md
      hash: sha256:f1264856fbd255221baec68edccf8d18a4da7c29c09ea2067277d83f15a5451c
    - path: plans/cockpit-diagnostics/build/implementation-plan.md
      hash: sha256:f7772bfc777b26b0a7c8f7a6630c78ebc8df37fef522eda1cfb377d483dd28f8
      ids:
        - REQ-002
    - path: lisp/gascity-runs.el
      hash: sha256:7169dcdf2cf7fb99496b3f8b40fc0b380fbc9e563517156da03a8280ce985f52
    - path: lisp/test/gascity-runs-test.el
      hash: sha256:3d3ee934a4c2a83f8a453f54fe6017a88741ca0d2bcfbb69a41f6283206c3f6c
  coverage:
    - id: REQ-002
      status: covered
---

# W2 — Facts-line value budgeting in the Runs history rows

## Summary

Rewrote `gascity-runs--facts-line` (`lisp/gascity-runs.el`) so each of
the four facts columns budgets its value separately from its dim label,
per plan §2 and Decisions 2 (REQ-002, AC-2).  The columns are now data
in `gascity-runs--facts-columns` — `(KEY LABEL WIDTH)` with `stage 12`,
`step 21`, `fail 22`, `work 12` (widths include the label and its one
trailing space) — so the value budgets are `6/16/17/7` instead of the
old `4/15/16/6`, while the line stays exactly
`2 + 12 + 3 + 21 + 3 + 22 + 3 + 12 = 78` columns.  A cut value keeps
its full text in `help-echo`; the worker delta face is unchanged.

Commit `c569d86` on branch `ga-40i2t`
(`/home/roman/workspace/gascity.el/worktrees/ga-40i2t`, based on
`origin/main` 4ed9d40).

## Intended Behavior

- `gascity-runs--facts-columns` is a `defconst` of four
  `(KEY LABEL WIDTH)` rows: `(stage "stage" 12)`, `(step "step" 21)`,
  `(failure "fail" 22)`, `(worker "work" 12)`.  WIDTH includes the dim
  label plus its one space, so the per-value budgets are 6/16/17/7.
  The docstring states the label set, the budgets and the 78-column
  total, so the manual example and the test cannot drift.
- For each column the cell is
  `(dim (concat label " ")) + (gascity-ui-fit (dim value) (- width (1+ (length label))))`,
  then the whole cell is `gascity-ui-fit`-ed to WIDTH as a guard; the
  line is `"  " + cell(stage) + " · " + cell(step) + " · " +
  cell(failure) + " · " + cell(worker)` via `mapconcat`.
- Visible result: `Review` (6 columns) now fits whole instead of the
  old `Rev…` (4 columns); `build-basic.review` cuts one column later
  (`build-basic.rev…` instead of `build-basic.re…`); a failure reason
  gets 17 columns instead of 16.  `Finalization` still cuts (6-column
  budget), by design.
- A value that must be cut carries its full text in `help-echo`
  (from `gascity-ui-fit`); the label and padding stay dim.
- With `changed` (a live-run delta), the worker value still gets the
  `gascity-changed` face, plus the full text's `help-echo` when cut.
- Nothing else changes: four fixed columns, three ` · ` separators,
  no header line, no dynamic per-row layout, no gc call on render
  (dashboard-v3 D9).  Values are read through the table keys
  (`stage` → `:stage`), so the existing `gascity-runs--row-facts`
  plist contract is untouched.

The rendered line (78 columns including trailing padding), captured
from the fixture's failed run `be-bn2` and recorded verbatim for the
docs work item W6:

```
  stage Review · step build-basic.rev… · fail hard: control_di… · work -      
```

The AC-2 test values (`Review`, `build-basic.review`,
`control_dispatch_error: final attempt 3: …`, `control`) render the
manual's example shape:

```
  stage Review · step build-basic.rev… · fail control_dispatch… · work control
```

## Changed Files

- `lisp/gascity-runs.el` — new `gascity-runs--facts-columns` defconst;
  `gascity-runs--facts-line` rewritten over the column table (per-value
  budget, whole-cell guard, same separators and delta face).
- `lisp/test/gascity-runs-test.el` — new
  `gascity-test-runs-facts-line-budgets` (column table, 6/16/17/7
  budgets each larger than 4/15/16/6, 78-column total, `Review` whole,
  step/failure cut text, full text in `help-echo`, worker delta face);
  the existing `gascity-test-runs-history-columns` budget comment
  updated to `2+12+3+21+3+22+3+12`.
- `plans/cockpit-diagnostics/build/implementation-summary-ga-40i2t.md`
  — this artifact.

No public interface, persisted state, JSON shape, gc CLI, store,
scheduler or live-stream change.

## Verification

TDD: the new ERT test was written first and observed red (the old
line rendered `"  stage -      · ..."` / no `gascity-runs--facts-columns`,
then the first draft failed on the table-key lookup), then green.

First verification command (targeted, from the worktree root):

```sh
EMACSLOADPATH=/home/roman/workspace/beads.el/lisp:/home/roman/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0:$EMACSLOADPATH: \
  emacs --batch -Q -L lisp -L lisp/test -l lisp/test/gascity-runs-test.el \
  --eval '(ert-run-tests-batch-and-exit "gascity-test-runs-facts-line-budgets")'
```

Observed: red before the change (`void-variable
gascity-runs--facts-columns`), green after: 1/1 pass.

Final proof commands (from the worktree root):

```sh
./autogen.sh && ./configure --with-beads-dir="$HOME/workspace/beads.el"
scripts/gate.sh
```

Observed: PASS — whole-package byte-compile with warnings as errors
clean, `make check` ran 962 tests with 962 results as expected, 0
unexpected.

```sh
scripts/lint.sh
```

Observed: PASS — checkdoc clean; `package-lint is not installed;
skipping package metadata checks` (CI installs it).

Interactive acceptance (tmux, non-graphical `emacs -nw -Q`, `lisp/` on
`load-path`, against the throwaway deterministic fixture city
`doc/screenshots/fixture.sh --create` + `--seed`): `M-x gascity`, `j r`
opened Runs, `H` showed the history of the seeded run; the rendered
facts line was

```
  stage Final… · step build-basic.pub… · fail -                 · work -
```

measured at 78 columns in the live buffer, and
`(get-text-property POS 'help-echo)` on the cut step value returned
`"build-basic.publish"`.  The fixture city was torn down afterwards.

## Remaining Risks

- The stage value keeps a 6-column budget, so a long stage label
  (`Finalization`) still cuts (`Final…`).  This is the plan's chosen
  budget (Decisions 2), not a defect; the test pins the budgets.
- The manual example in `doc/gascity.texi` and the `cockpit`/`runs`
  screenshots are the docs work item's scope (W6), which consumes the
  verbatim line recorded above; this item does not touch `doc/` or
  `doc/images/`.
- Truncation happens in two steps (value, then whole cell).  Because
  the value budget makes the cell exactly WIDTH, the outer fit is a
  no-op guard today; if a future column table sets a width smaller
  than the label plus budget, the outer fit protects the line but
  would replace the inner cut text's `help-echo` with the already-cut
  string.
- The facts line is asserted in three places (constant docstring, ERT,
  manual); the ERT pins the table, the budgets and the 78-column total,
  which is what protects the manual from drift once W6 copies it.

| ID | Status |
| --- | --- |
| REQ-002 | covered |

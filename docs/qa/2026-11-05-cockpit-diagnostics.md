# Cockpit and run/event diagnostics batch — acceptance pass

- Date: 2026-11-05
- Item: W7 "Acceptance pass, QA report and final gates for the diagnostics
  batch" (ga-tx45i, workflow root ga-4hdav, do-work implement step ga-u565r)
- Deliverable worktree: `worktrees/ga-tx45i` (detached at `4ed9d40`, this
  report is the only file it adds)
- Trial integration worktree: `worktrees/ga-tx45i-integration` (throwaway,
  detached at `4ed9d40`, created for this pass only — see "How the batch was
  assembled")
- Environment: GNU Emacs 31.1, `gc` from the Guix profile, beads.el from
  `~/workspace/beads.el` (vui 1.4.0 from its eldev package dir), headless
  tmux sessions with `emacs -nw -Q` and the integration worktree's `lisp/` on
  `load-path`
- Cities: throwaway fixture city `/tmp/ga-tx45i/gascity-fixture`
  (`doc/screenshots/fixture.sh --create` then `--seed`, `TMPDIR` isolated so
  the shared `/tmp/gascity-fixture` of the screenshot pipeline is untouched);
  live `emacs-city` (`/home/roman/emacs-city`) read-only; remote acceptance
  city `bright-lights` over TRAMP (`/ssh:localhost:~/bright-lights`)

## Verdict (review iteration 2 — PASS)

**Acceptance PASSED on the integrated tree after the review-fix pass.** The
three iteration-1 blockers are resolved and re-verified:

1. **The batch is integrated.** The review-fix integration tree merges W1 →
   W2 → W3 → W4 → W5 → W6 → W7 on top of `4ed9d40` (W1's fixes in `0d4064c`
   and `3d0734b`, W3's in `4b65597`, W5's in `e73fabb`). The whole-package
   gate is green: `Ran 981 tests, 981 results as expected, 0 unexpected`,
   byte-compile clean with warnings as errors.
2. **W6 is delivered and verified.** `doc/gascity.texi` carries the new
   facts-line example (`stage Review · step build-basic.rev… · fail
   control_dispatch… · work control`), `NEWS.md` has the batch entry, and
   `make -C doc` builds. The committed cockpit/runs/run-detail images were
   regenerated from this merge set and
   `doc/screenshots/capture.sh --verify cockpit,runs,run-detail` reports
   **byte-identical** (isolation OK, 44 non-selected images untouched).
3. **REQ-004's `close_reason` half now works on real payloads.**
   `gascity-event--bead-why-fields` reads `metadata.close_reason` first with
   the top-level value as the fallback. Live Events drawer on `emacs-city`
   (`type=bead.closed`, `SPC` on `ec-wisp-5vl90a`):

   ```
   16:54       bead.closed                      ec-wisp-5vl90a   │ type       bead.closed
                                                                  │ ts         2026-11-05T16:54:34…
                                                                  │ bead       ec-wisp-5vl90a order:order-tracki…
                                                                  │ close_reason  order dispatch completed: trackin…
   ```

The five REQ-001..REQ-005 behaviours were re-exercised through a live
non-graphical Emacs in tmux on the integrated tree (fixture city,
`emacs-city`, and `bright-lights` over TRAMP); see "Review-fix re-run"
below. The iteration-1 FAILED verdict is retained as the historical record
of what was wrong.

## Verdict (iteration 1 — superseded, FAILED)

**Acceptance FAILED — the finished batch cannot be accepted yet.** Three
blocking facts, in order of severity:

1. **The batch is not integrated.** `origin/main` (`4ed9d40`) contains none
   of the five implementation items. Their commits exist only as local
   detached-HEAD commits in their item worktrees (`ga-f7nvv` `af17537`,
   `ga-40i2t` `c569d86`, `ga-lya6t` `7f35b9d`, `ga-4odv8` `bf470e9`,
   `ga-i83g4` `feaaf0b`); `git branch -r --contains af17537` is empty. No
   publish/finalize step has run, so there is no branch a consumer can pull.
2. **W6 (docs, NEWS, screenshots) is not started.** ga-bc5tg is still open;
   its worktree `worktrees/ga-bc5tg` is clean at `4ed9d40` with no commits.
   `doc/gascity.texi:1909` still carries the stale example
   `stage Rev… · step build-basic.re… · failure control_dispatc… · worker contr…`,
   `NEWS.md` has no entry, and `doc/images/` are the pre-batch renders.
   REQ-006/AC-6 therefore fails.
3. **REQ-004's `close_reason` half does not work on real gc payloads.**
   The event drawer renders `gc.failure_class` but never `close_reason`,
   because `gascity-event--bead-why-fields` reads only a top-level
   `bead.close_reason` and gc delivers the reason in
   `bead.metadata.close_reason`: over 24 h of `emacs-city` events,
   **0 of 1124 `bead.closed` payload beads** (and 0 of any event type)
   carry a top-level `close_reason`, while **917** carry
   `metadata.close_reason` (1301 across all event types). The fix belongs to
   W5 (ga-4odv8). The manual acceptance step "verify `close_reason` and
   `gc.failure_class` lines" therefore cannot pass.

Everything else in the batch behaves as specified — see the evidence below.
The trial integration (five commits cherry-picked cleanly onto `4ed9d40`,
whole-package gate green) shows the items compose with no conflicts, so the
remaining work is integration + W6 + the one W5 fix.

## How the batch was assembled

Because nothing is merged, the pass ran on a **trial integration** built in a
throwaway worktree. It is not a deliverable branch and must not be merged.

```sh
git worktree add worktrees/ga-tx45i-integration --detach origin/main
cd worktrees/ga-tx45i-integration
for c in af17537 c569d86 7f35b9d bf470e9 feaaf0b; do git cherry-pick -x "$c"; done
```

All five cherry-picks applied with auto-merges only (W5's dashboard/test
hunks on top of W1+W3), no conflict:

```
b3733a9 fix(cockpit): stalled agents show stall age, lease and heartbeat (ga-i83g4)
223db30 fix(events): bead close reason and failure class in the event drawer (ga-4odv8)
32975f9 fix(cockpit): give failed runs a real drawer and a budgeted class row (ga-lya6t)
594f38e fix(runs): budget each facts column's value separately (ga-40i2t)
a2c2e0d fix(runs): fit long failure lines in cards and drawers (ga-f7nvv)
4ed9d40 feat(run-view): run view v3 — attempt history, artifacts, live deltas (ga-hsbfs) (#43)
```

Configure had to be pointed at the sibling beads checkout:
`./configure --with-beads-dir="$HOME/workspace/beads.el"`.

## Automated gates

| Command | Result |
| --- | --- |
| `scripts/gate.sh` | **PASS** — `make` (byte-compile, warnings as errors) clean; `make check` "Ran 978 tests, 978 results as expected, 0 unexpected" (41.5 s) |
| `scripts/lint.sh` (`make lint`) | **PASS** — exit 0, no checkdoc/re warnings. Deviation: `package-lint is not installed; skipping package metadata checks` (CI installs it); not a failure but not the full CI bar |
| `make -C doc` | **PASS** — exit 0, "Nothing to be done" (the Texinfo source is unchanged, which is itself part of the W6 finding: the manual is stale) |
| `doc/screenshots/capture.sh --verify cockpit,runs,run-detail` | **PASS** — "verify: byte-identical for 4 image(s) (scope cockpit,runs,run-detail)"; coverage ok; isolation ok (44 non-selected `doc/images` files byte-identical) |

No new `gc` call was introduced on the render path: the five commits touch
only `lisp/gascity-dashboard.el`, `lisp/gascity-runs.el`, `lisp/gascity-run.el`,
`lisp/gascity-event.el` and their tests, and
`git diff 4ed9d40..HEAD -- lisp/test/gascity-store-test.el` is empty (the
non-blocking guard is unchanged).

## Interactive acceptance

Two tmux sessions were used: `gce-w7` on the fixture city (80-column-ish
cockpit at 120x40) and `gce-w7-live` on `emacs-city`, plus `gce-w7-tramp` on
`/ssh:localhost:~/bright-lights`.

### Cockpit Needs you — active run with a failed step (fixture)

`M-x gascity-dashboard`, then `SPC` on the failed-step row
(`gascity-thing-toggle` on the row's text properties):

```
Needs you  5
  ■ work     demo-task-fixture  demo gone  age 673d                    demo-rig
  ■ work     demo-run  demo-rig/gc.run-operator gone  age 673d         demo-rig
  ■ work     demo-task-manual  demo gone  age 673d                     demo-rig
  ■ run      demo-run build-basic  idle 673d                          demo-rig
  ■ run      demo-run ✕ build-basic.review                         code_review
  │ run      demo-run  build-basic
  │ step     review  build-basic.review
  │ class    code_review
  │ reason   two blocking findings: the render path stats a file and the header is not frozen
```

The row's right column carries the failure class (`code_review`), not the bare
`failed`, and the drawer names run, step ref, class and reason (REQ-001's
renderer family; this is the active-run/`failed-step` item, not the closed-run
item).

### Cockpit Needs you — closed failed run over TRAMP (bright-lights)

The cockpit's failed-run list is bounded by its Activity window (2 h by
default) and bright-lights' only failed workflow root (`hw-cz23`, closed
2026-11-04 17:40) was 22 h old, so the filter window was widened through the
real UI: `/` then `-W`, value `24h`, `C-g`, then `SPC` on the row:

```
Needs you  3
  ■ run      hw-cz23 build-basic  failed                            22h   hard
  │ run      hw-cz23  build-basic
  │ class    hard
  │ step     build-basic.review
  │ reason   control_dispatch_error
  │ RET run detail  b root bead
  ▲ mail     7 unread                                                j m inbox
  ▲ store    health: counting retained bead rows: hydrating …       j h health
```

This is REQ-001 on real remote data: run id + formula, class, failed step ref,
reason and both key hints; the row's right column is the class (`hard`), and
the remote cockpit renders identically to the local one (header
`bright-lights @localhost`, buffer pinned to
`/ssh:localhost:/home/roman/bright-lights/`).

### Runs — history facts line (`emacs-city`, `j r`, `H`)

```
  ✕ ga-oequ0  do-work       ◆✕✕          1/3    fail      gascity.el        2h
  stage imple… · step do-work.impleme… · fail integration_conf… · work -
```

Measured at point: **line width 78**, `help-echo` on the cut value =
`"integration_conflict: run-view-v3 feature branches are independent and
conflict; worktree base 61effa2 has none of the v3 features, so the nine
REQ-010 acceptance sections are blocked"`. Value budgets are the new
6/16/17/7 (`stage` keeps 6, `fail` shows 16 of `integration_conflict`), so the
old starved `Rev…`/`control_dispatc…` shape is gone (REQ-002/AC-2).

### Runs — Failed card truncation (`emacs-city`)

```
Failed  1 · last 24h
  ✕ ga-oequ0  do-work                                     gascity.el        2h
     ◆✕✕  implement      1/3    close-source-anchor FAIL (not pass): resolved…
```

Measured: **line width 78**, ends in `…`, and the text's `help-echo` is the
full close reason (the whole `close-source-anchor FAIL (not pass): resolved
the source anchor as ga-eg5ij …` paragraph). No line overflows at 78
columns (REQ-003).

### Run detail — step drawer failure line (`gascity-run-show "ga-oequ0"`, `SPC` on `implement`)

```
  │ step     do-work.implement  ga-917kw  closed  outcome skipped
  │ attempt  1 · iteration 1 · iteration bead ga-j8cnx
  │ attempts
  │   1   fail      ○ ec                      2h integration_conflic…
  │ worker   ec-wisp-sf4smu  ○ ec  assignee/session gone
  │ artifacts run   implementation-summary-ga-eg5ij.md (4 KB, 2h)
  │ events   (no recent events)
  │ failure  integration_conflict: run-view-v3 feature branches are independe…
```

Measured on the `failure` line: **width 78**, full text in `help-echo`
(`"integration_conflict: run-view-v3 feature branches are independent and
conflict; …"`). The attempt row keeps its 20-column cut
(`integration_conflic…`) with its own `help-echo` (asserted by the ERT suite;
not re-measured here).

### Events — `bead.closed` detail (`emacs-city`, `j e`, filter `search=ga-j8cnx`, `SPC`)

```
 14:23     bead.closed                        ga-j8cnx                   Implement owned work
  │ type       bead.closed
  │ ts         2026-11-05T14:23:19.534571626+01:00
  │ seq        390213
  │ actor                cache-reconcile
  │ bead                 ga-j8cnx Implement owned work (closed)
  │ gc.failure_class     integration_conflict
  │ run_id               ga-oequ0
  │ session_id           ec-wisp-sf4smu
  │ step_id              implement
  │ depends_on_step_ids  do-work.prepare-worktree
  │ subject              ga-j8cnx
```

`gc.failure_class` is present (REQ-004 half). **No `close_reason` line**, and
none can appear: the real payload bead has no top-level `close_reason`. The
programmatic pass over the same read (exit 0, 7879 events, 0 bad lines)
confirms it for the whole feed:

| 24 h `emacs-city` events | count |
| --- | --- |
| `bead.closed` events | 1124 |
| …with top-level `payload.bead.close_reason` | **0** |
| …with `payload.bead.metadata.close_reason` | 917 |
| any event type with top-level `payload.bead.close_reason` | **0** |
| any event type with `payload.bead.metadata.close_reason` | 1301 |

### Stalled agent — not exercised live

No stalled agent existed in any city at pass time: the fixture's agents are
`stopped` (`gc status`: "0/4 agents running"), `bright-lights` had 3 idle + 2
stopped, `emacs-city` had 4 running + 1 idle + 4 stopped. The fixture is a
no-controller city, so a "gc says running, no live session" agent cannot be
manufactured there without fabricating status data. REQ-005 therefore rests
on its ERT coverage (`gascity-cockpit-test`, including the `--agents` join,
the 45+ character qualified name, `unknown` age, and lease/heartbeat cases)
for this pass; there is no live render to record.

## Screenshots

`TMPDIR=/tmp/ga-tx45i GASCITY_SHOT_STAGING=/tmp/ga-tx45i/staging
doc/screenshots/capture.sh --verify cockpit,runs,run-detail` ran against the
trial integration (raw view tokens `cockpit,runs,run-detail`, as the plan
requires) and **passed**: two captures of `cockpit-dark`, `cockpit-light`,
`runs-dark` and `run-detail-dark` were byte-identical, every selected view
produced an image, and the 44 non-selected `doc/images` files were untouched
(isolation OK). The new renders are therefore deterministic.

The committed `doc/images/` are nevertheless **not** regenerated — the verify
writes to the throwaway staging dir by design, and updating the committed
images is W6's deliverable (ga-bc5tg). The committed cockpit/runs/run-detail
images and their thumbs still show the pre-batch renders and must be
regenerated (and `--check-isolation`'d) before the batch can be accepted.

## Deviations

| Deviation | Severity | Note |
| --- | --- | --- |
| Batch assembled by cherry-pick in a throwaway worktree | blocking | No publish/finalize has run; the five item commits are local and unmerged |
| W6 docs/NEWS/screenshots absent | blocking | ga-bc5tg open, empty worktree; stale manual example, no NEWS entry, pre-batch images |
| Events `close_reason` absent on real payloads | blocking | gc delivers it as `metadata.close_reason`; W5 reads only the top-level key |
| `package-lint` unavailable locally | low | `make lint` checkdoc/re half clean; CI installs package-lint |
| Fixture city has no supervisor, so `gc events --since` fails there | low | Fixture Activity/Events empty; Events acceptance ran on `emacs-city` instead (the plan names the fixture for the local pass; the fixture's `gc events` error is a pre-existing fixture limitation) |
| Stalled-agent path had no live data | low | ERT-covered; no city had a stalled agent during the pass |
| bright-lights store health `agent_state_unknown` | low | Pre-existing remote city state, unrelated to the batch |

## Reproduce

```sh
# gates on the trial integration
cd worktrees/ga-tx45i-integration
./configure --with-beads-dir="$HOME/workspace/beads.el"
scripts/gate.sh && scripts/lint.sh && make -C doc

# fixture city (isolated)
TMPDIR=/tmp/ga-tx45i doc/screenshots/fixture.sh --create
TMPDIR=/tmp/ga-tx45i doc/screenshots/fixture.sh --seed

# interactive; w7-init.el:
#   ;;; -*- lexical-binding: t; -*-
#   (add-to-list 'load-path ".../worktrees/ga-tx45i-integration/lisp")
#   (add-to-list 'load-path ".../beads.el/lisp")
#   (add-to-list 'load-path ".../beads.el/.eldev/31.1/packages/vui-1.4.0")
#   (setq default-directory "/tmp/ga-tx45i/gascity-fixture/")
#   (require 'gascity)
tmux new-session -d -s gce-w7 -x 120 -y 40 \
  'cd /tmp/ga-tx45i/gascity-fixture && emacs -nw -Q -l /tmp/ga-tx45i/w7-init.el'
# then M-x gascity-dashboard, j r, H (history), SPC/RET on rows
```

```sh
# the negative finding, independent of the UI
GC_HOME=$HOME/.gc gc events --city /home/roman/emacs-city --since 24h \
  | python3 -c 'import json,sys; ...count payload.bead.close_reason vs metadata.close_reason...'
```

## Review-fix re-run (review iteration 2)

Re-run on 2026-11-05 after the review-fix pass (bead `ga-ivpx9`). The tree is
`worktrees/ga-tx45i-integration`, rebuilt from `4ed9d40` by merging, in the
documented order, the fixed item tips: W1 `3d0734b` (whose `0d4064c` adds the
metadata `close_reason` fallback), W2 `e06de5a`, W3 `4b65597` (rebased on W1,
drawer routed through `gascity-dashboard--drawer-value`), W4 `feaaf0b`,
W5 `e73fabb`, W6 `56909e9`, W7 (this report). Every merge was an auto-merge;
no conflict.

### Automated gates (integrated tree)

| Command | Result |
| --- | --- |
| `scripts/gate.sh` | **PASS** — `make` clean (warnings as errors); `make check` "Ran 981 tests, 981 results as expected, 0 unexpected" (42 s) |
| `scripts/lint.sh` | **PASS** — checkdoc/re clean; `package-lint is not installed; skipping package metadata checks` (CI installs it; M5) |
| `make -C doc` | **PASS** — the W6 manual/NEWS changes build (`doc/gascity.info`) |
| `doc/screenshots/capture.sh --verify cockpit,runs,run-detail` | **PASS** — "verify: byte-identical for 4 image(s)", coverage ok, isolation ok (44 non-selected images byte-identical) |

New coverage in this pass: `gascity-test-runs-failed-card-metadata-close-reason`
(metadata-only and top-level-only close reason for the Failed card and its
`help-echo`, plus `gascity-runs--failure`/`--failure-info`),
`gascity-test-comms-event-drawer-close-reason-top-level-fallback` (metadata
precedence and the bd-list fallback), and
`gascity-test-cockpit-needs-you-failed-run-close-reason-metadata` (drawer
reason from the event shape). The AC-1 rendered-row test now asserts the
class on the rendered row, not only on the item plist.

### Interactive acceptance (fresh tmux + `emacs -nw -Q`)

Fixture city `/tmp/ga-fix-accept/gascity-fixture` (isolated `TMPDIR`), the
integrated `lisp/` on `load-path`:

```
Needs you  5
  ■ run      demo-run build-basic  idle 673d                          demo-rig
  ■ run      demo-run ✕ build-basic.review                         code_review
  │ run      demo-run  build-basic
  │ step     review  build-basic.review
  │ class    code_review
  │ reason   two blocking findings: the render path stats a file and the header is not frozen
```

The failed-step drawer renders run, step, class and the first reason line on
the fixed tree (REQ-001's active-run render site).

`bright-lights` over TRAMP (`/ssh:localhost:~/bright-lights`), Activity
window widened to 24h through `/` → `-W` → `24h`, then `SPC` on `hw-cz23`:

```
Needs you  3
  ■ run      hw-cz23 build-basic  failed                            23h   hard
  │ run      hw-cz23  build-basic
  │ class    hard
  │ step     build-basic.review
  │ reason   control_dispatch_error
  │ RET run detail  b root bead
```

All five REQ-001 drawer elements render after the R3 collapse onto
`gascity-dashboard--drawer-value`, and the remote cockpit still renders
identically to the local one.

`emacs-city`, Runs view (`j r`, then `H`):

```
Closed  316 · all time
  ✕ ga-4hdav  do-work       ◆✕✕          1/3    fail      gascity.el       38m
  stage imple… · step do-work.impleme… · fail acceptance_failu… · work -
```

The facts line is exactly 78 columns with the new per-column budgets
(REQ-002/AC-2), and the Failed card above it keeps its cut reason plus the
full text in `help-echo` (REQ-003; asserted by
`gascity-test-runs-failed-card-fits-failure-reason`).

`emacs-city`, Events view (`j e`, `/` → `-t` → `bead.closed`, `SPC`):

```
16:54       bead.closed                      ec-wisp-5vl90a  │ bead          ec-wisp-5vl90a order:order-tracki…
                                                                │ close_reason  order dispatch completed: trackin…
```

`close_reason` now renders from the real payload's
`bead.metadata.close_reason` — the iteration-1 blocker (REQ-004/AC-4).

Stalled agents (REQ-005/AC-5) still have no live instance in any city at pass
time; the behaviour rests on the five `gascity-test-cockpit-stalled-agent-*`
ERT tests, as in iteration 1. `help-echo` is still asserted as a text property
(ERT) rather than observed as a rendered tooltip; the live pass shows the cut
text and the drawer contents.

### Evidence hygiene recorded by the review

- W1/W3 first-verification commands re-run with the explicit
  `EMACSLOADPATH=beads.el/lisp:…/vui-1.4.0` + `-L lisp -L lisp/test` form
  (M1).
- W4's reconstructed red run was recorded by the test-evidence review (5/5
  fail on base `af17537`); no code change (M2).
- `package-lint` remains unavailable locally (CI installs it) (M5).
- `runs-dark` still cannot show the facts line because the fixture has no
  history row; the manual example is the evidence (M6).
- The committed images were captured from this merge set and `--verify`
  reproduces them byte-for-byte (M7).

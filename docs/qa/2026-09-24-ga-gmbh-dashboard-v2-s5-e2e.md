# Dashboard v2 S5 — live e2e acceptance report (ga-gmbh)

Date: 2026-09-24 · Implementer: gascity.el/gc.implementation-worker-8 (session
ec-oyq3) · Harness: `scripts/e2e-harness.sh` (every emacs/emacsclient/tmux
call bounded). Requirement: S5 of `plans/dashboard-v2/implementation-plan.md`
— the interactive acceptance gate for AC 6–12 of `requirements.md`, against
the live `emacs-city` (runs) and `bright-lights` (TRAMP parity).

## S5 findings that changed the code (live-data checks)

Verification against the live cities surfaced three real defects in the
S1–S4 code, all fixed in this pass before the acceptance run:

1. **Runs were invisible from a real city (AC 1).** The Runs section read
   one city-scoped `gc bd list --status in_progress`, but workflow runs live
   in the **dispatching rig's** bead store — `gc bd list --city ROOT` reads
   only the city HQ store, so the live emacs-city dashboard showed
   `Runs (0)` while two formula-v2 runs were in flight. Fix: the
   in-progress/blocked census now **fans out over the city's rig stores**
   (`gascity-dashboard--bd-list-rigs-async`: one `rig list` read, one
   `bd list … --rig NAME` read per rig, rows in rig order, each stamped with
   `(gascity-rig . NAME)`).
2. **Progress fractions were wrong (AC 1).** A run's closed steps are
   invisible to an in-progress read — the real build-basic run rendered
   `0/0`. Fix: the Runs census got its own full-status fan-out
   (`open,in_progress,blocked,deferred,closed`); Work in flight keeps the
   in-progress read.
3. **Step grouping missed every step (live shape).** Live steps carry only
   `gc.root_bead_id` — `gc.graphv2_root_key` never reaches the steps — so
   the selector that bucketed steps by the root key counted `0/0` even with
   the full read. Fix: `--workflow-runs` now buckets steps by
   `gc.root_bead_id` (the same verified shape `gascity-run--steps` climbs),
   and pins the run-row's owning store on the row.

Also fixed in this pass:

- **RET on a Runs row never reached the run detail (AC 2).** The drill-in
  hook existed but `gascity-dashboard-activate` fell through to the generic
  bead visit (beads.el). Now the run row (stamped `gascity-run-rig` by the
  fan-out) opens `gascity-run-show` with the owning rig, and the run view
  scopes its own `bd list` read with `--rig`. A run opened without a rig
  (bare `M-x gascity-run-show`) renders the city's affected-list rows with
  their own rig stamps instead of a bare "not found".
- **Footer legend promised an `e` key that did not exist (AC 11).** Bound
  `e` directly to `gascity-dashboard-events-filter-dispatch` (still
  reachable under `/` as "Events…").

## Verification results (all through harness bounds)

1. **Static gates**: `scripts/gate.sh` PASS — whole-package
   `eldev compile --warnings-as-errors` + 413 ERT tests, 0 unexpected
   (6 new tests: rig fan-out union/stamping, partial-failure degradation,
   no-rigs empty resolve, full-status runs read, live step shape, RET
   dispatch, run-show rig scoping). Honesty greps: `rg -in "url|http"` over
   `lisp/gascity-dashboard.el lisp/gascity-reader.el` → doc comments only,
   no supervisor API contact; no synchronous `gc` in render/eldoc/prefix
   paths (all new reads are `gascity-reader-read-async`).
2. **Local live city (`/home/roman/emacs-city`)**: dashboard renders the
   real runs with correct fractions — `ga-sd7e do-work 1/6 (ga-lbl7)`,
   `ga-uxhh build-basic 12/42`, `be-j2b build-basic 13/45` — plus
   `44 closed runs hidden`; Work in flight joins 9 rows; Activity feed
   live from `gc events`; mail header 3 unread; costs dim pointer present.
3. **Run drill-in (AC 2)**: programmatic activate on the `ga-sd7e` row and a
   keystroke isearch+RET flow both open `*gascity-run@/home/roman/emacs-city/*`
   — header `Run ga-sd7e — do-work · phase in_progress · progress 1/6`, all
   6 steps with kind/status/assignee, input convoy `ga-e4xa open 0/1` joined.
   Drill into `ga-uxhh` renders the full 42-step graph at 12/42. The run
   view's read is scoped `--rig gascity.el` (the fan-out's stamp); the
   keystroke fallback on a Work-in-flight row opens `beads-show[gascity.el]`
   — §4.3 store scoping intact.
4. **TRAMP parity (AC 9)**: `/ssh:localhost:/home/roman/bright-lights` —
   identical rendering in both local and TRAMP access (same section counts,
   byte-identical 2840-byte buffers), Activity feed live, footer/header
   legends with `m`/`e`, no TRAMP sync stalls (every probe returned inside
   the harness bounds; the fan-out adds per-rig async reads that ride the
   same TRAMP-safe reader path).
5. **Mail (`m`, AC 4)**: keystroke `m` from the TRAMP dashboard opens
   `*gascity-mail@/ssh:localhost:/home/roman/bright-lights/*` — the inbox
   scopes to the city the dashboard reads.
6. **Capability beads (AC 6)**: filed earlier in this workflow and still
   open — `ga-ik26` (costs JSON surface, referencing the live
   `json_unsupported` error) and `ga-jcv1` (pending-interactions surface).
7. **E2e session note**: the default `gce-e2e` tmux session is contended by
   bright-lights' demo automation (bead `bl-70ac`, `bd.dog` agents restarted
   it mid-pass); this pass ran under a dedicated `gce-e2e-s5` session. Pane
   capture archived at `/tmp/ga-gmbh-e2e/run-drillin-pane.txt`.

## Gate

`scripts/gate.sh` PASS at close: compile `--warnings-as-errors` clean +
413 tests green.

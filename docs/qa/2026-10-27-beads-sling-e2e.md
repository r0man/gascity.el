# Slinging a beads.el issue to Gas City — tmux/Emacs e2e pass (2026-10-27)

Work bead `ga-lii6c` (B8 of
`plans/beads-sling-integration/implementation-plan.md`), workflow root
`ga-h9v28`, convoy `ga-3us7o`. This is the interactive acceptance gate for
AC-15 / REQ-003, REQ-004, REQ-008: the real `S` flow in a
`beads-show-mode` buffer, through beads.el's adaptive sling transient, the
registered `gc` backend, `gc sling`, and back into gascity.el's run/status
views — locally and over TRAMP.

## Setup

| | |
|---|---|
| Checkout | worktree `worktrees/ga-lii6c`, branch `beads-sling-b8`, based on the full `beads-sling-b7` stack plus a cherry-pick of B6's ERT suite (`5ca664f`) and its summary (`6670dad`) |
| beads.el | sibling checkout `~/workspace/beads.el` at `a744ac25` (Workstream A merged) |
| Emacs | GNU Emacs 31.1, `emacs -nw -Q` in tmux session `gce-lii6c` (server `gce-lii6c`), non-graphical |
| transient | 0.13.8 (bundled) |
| Load path | worktree `lisp/` + `~/workspace/beads.el/lisp` + the `vui-1.4.0` bundled under `~/workspace/beads.el/.eldev/31.1/packages/` |
| gc | 1.5.1 in both cities |
| Cities | local `emacs-city` (`~/emacs-city`) and `bright-lights` (`/ssh:localhost:/home/roman/bright-lights`) |
| Bounds | `. scripts/e2e-harness.sh`; every emacs/emacsclient/tmux call under `timeout(1)`; pane 120x50 |

Method: drive the real keys through tmux (`S`, `T`, `f`, `s`, `F`, `?`), read
the pane as a user would, and confirm every dispatch in the store and in
gascity.el's views. The throwaway `e2e-demo` formula (a v2 workflow with a
single workflow-latch step) is the dispatch payload — it creates a workflow
root but spawns no agent session, so the pass never mutates real work.
`bright-lights` already ships it; for the local city a temporary copy was
placed in `~/emacs-city/formulas/` and removed after the pass.

## Gates

| Command | Result |
|---|---|
| `BEADS_DIR=~/workspace/beads.el scripts/gate.sh` | **PASS** — byte-compile clean (warnings-as-errors), `Ran 843 tests, 843 results as expected, 0 unexpected` |
| `BEADS_DIR=~/workspace/beads.el scripts/lint.sh` | **PASS** — `make lint` exit 0 (package-lint is not installed locally; CI installs it) |
| `make -C doc` | **PASS** — `doc/gascity.info` rebuilt from `doc/gascity.texi` |

One known flake fired during a repeat run
(`gascity-test-local-reader-read-async-generic-envelope-stderr-wins`, a
stderr/stdout race in the async reader; beads ga-r8vmg, ga-vfz1j, ga-o6ofn).
It reproduces on `main` at the same rate as on this branch (2/10 vs 3/10
isolated runs), and the branch touches neither the reader nor that test; the
recorded gate result is a green full run. Not attributable to the beads-sling
stack.

## Cold start (F4, observed, expected)

In a fresh Emacs with no gascity view open, the target provider cannot name a
city and contributes nothing:

```
(:count 58 :gc-count 0
 :local ("ga-lii6c/plan" "ga-lii6c/review" "ga-lii6c/task"))
```

Opening the city's dashboard and its agents view warms the memo and the
`("agent" "list")` store entry; the same call then answers with the roster:

```
bright-lights: (:count 30 :gc-count 20)
emacs-city:    (:count 95 :gc-count 36)
```

This is the documented limitation (manual: targets appear once a city is
known), not a defect.

## Remote pass — `bright-lights` over `/ssh:localhost:`

1. Visit `/ssh:localhost:/home/roman/bright-lights/city.toml`, `M-x
   gascity-dashboard` → header `bright-lights @localhost ● live`, all
   sections render; `M-x gascity-agents` warms the roster.
2. Disposable bead `bl-fgg6` in `beads-show-mode`
   (`*beads-show[/ssh:localhost:|bright-lights]/bl-fgg6*`).
3. `S` → the bead-seeded transient. The derived local target is shown but not
   preselected; the Who picker's completion list holds 30 targets, 20 of them
   the gc roster (`bd.dog`, `hello-world/…`, `mayor`, …).
4. `T` → `mayor`; `f` → `e2e-demo`; the transient re-renders with the formula
   recipe and its one defaulted var:

   ```
   Sling — bright-lights
      Run e2e-demo against bead bl-fgg6, drained by mayor
      ✓ Ready — on run · target mayor · 0 of 1 vars set

   What
    A Work: bl-fgg6 — e2e beads-sling: S from a beads show buffer
    f Formula: e2e-demo — Disposable end-to-end demo formula for the gascity.el …
   How — e2e-demo vars
    ot note — Disposable demo note carried into the step title. [default: gce-e2e demo] (--var note=gce-e2e demo)

   Who
    T Target: mayor · local · available

   Actions
    s Launch
    P Full preview
    r Recipe preview
    x Reset
    q Quit
   ```

5. `s` → echo `Launched workflow bl-sx9x (e2e-demo on bl-sx9x) — F: run view`.
6. `F` opens the run view, live:

   ```
    bright-lights @localhost  Run bl-sx9x  ● live
   ⬣ bl-sx9x  e2e-demo                                         city · started 11s
     formula  e2e-demo (graph.v2)   source ~/bright-lights/formulas/e2e-demo.formula.toml
     convoy   bl-wbnd  open 0/1  input convoy for bl-fgg6
   Steps  0/0
   ```

7. The status dashboard (`M-x gascity-dashboard`, `g`) shows the same root:

   ```
    bright-lights @localhost  ● live  ↻ 0s ago
   agents 0/5 ▲   sessions 3   runs 1 ⬣   ready 12   mail ▲7

   Moving  1 run · 0 workers
     ⬣ bl-sx9x   e2e-demo                      0/0    48s                    city
   ```

Store confirmation: `bl-sx9x` is `in_progress`, `gc.kind=workflow`,
`gc.formula_name=e2e-demo`, `gc.routed_to=mayor`,
`gc.input_convoy_id=bl-wbnd`, `gc.var.note=gce-e2e demo`; the input bead
`bl-fgg6` carries `gc.execution_routed_to=mayor`.

## Local pass — `emacs-city`

1. Visit `/home/roman/emacs-city/city.toml`, open the dashboard and agents
   view (roster warm: 36 gc targets).
2. Disposable bead `ga-a9i6z` in `beads-show-mode`
   (`*beads-show[gascity.el]/ga-a9i6z*`).
3. `S` → seeded transient, derived local target `gascity.el/task` (not a gc
   target — the user must pick one, by design).
4. First attempt: `T` → city-scoped `mayor`, `f` → `e2e-demo`, `s`. gc 1.5.1
   refuses a cross-store route (the bead lives in `rig:gascity.el`, the
   target reads `city:emacs-city`). The backend surfaces the first stderr line
   exactly as designed:

   ```
   gc sling mayor ga-a9i6z --json --on e2e-demo --var note=gce-e2e demo failed:
   gc sling: refusing cross-store route: bead ga-a9i6z lives in rig:gascity.el
   but target "mayor" reads city:emacs-city; re-file the bead in city:emacs-city
   (or pick a target reachable from rig:gascity.el). Cross-store routes silently
   wedge pools — see tr-6s7yx
   ```

   No workflow root was created; see finding F3 for the missing advisory.
5. Second attempt with a rig-reachable target: `T` →
   `gascity.el/gc.run-operator`, `f` → `e2e-demo`:

   ```
   Sling — gascity.el
      Run e2e-demo against bead ga-a9i6z, drained by gascity.el/gc.run-operator
      ✓ Ready — on run · target gascity.el/gc.run-operator · 0 of 1 vars set
   …
   How — e2e-demo vars
    ot note — Disposable demo note carried into the step title. [default: gce-e2e demo] (--var note=gce-e2e demo)
   Who
    T Target: gascity.el/gc.run-operator · local · available
   ```

6. `s` → echo `Launched workflow ga-gsqi3 (e2e-demo on ga-gsqi3) — F: run view`.
   The run view (opened via `M-x gascity-run-show ga-gsqi3`):

   ```
    emacs-city  Run ga-gsqi3  ● live
   ⬣ ga-gsqi3  e2e-demo                                  gascity.el · started 55s
     formula  e2e-demo (graph.v2)   source ~/emacs-city/formulas/e2e-demo.formula.toml
     convoy   ga-ouzrs  open 0/1  input convoy for ga-a9i6z
   Steps  0/0
   ```

   and the status dashboard's Moving section:

   ```
   Moving  3 runs · 1 sub-run · 2 workers
     …
     ⬣ ga-gsqi3  e2e-demo                      0/0    1m               gascity.el
   ```

   Store confirmation: `ga-gsqi3` is `in_progress`, `gc.kind=workflow`,
   `gc.formula_name=e2e-demo`, `gc.routed_to=gascity.el/gc.run-operator`,
   `gc.input_convoy_id=ga-ouzrs`, `gc.var.note=gce-e2e demo`.

The local dispatch caused gc to start one `gascity.el/gc.run-operator-1`
session while it resolved the routed root; it found no agent work (the formula
is a latch) and exited on its own (`ec-wisp-y044w` no longer listed). No
stalled session remained.

## Findings

- **F1 — `[City]` dispatch group cannot render (beads.el; filed `be-cnn7f`).**
  From the show buffer, `?` raises `Invalid function: "City"`
  (`transient-setup: Invalid function: "City"` in `*Messages*`) and the whole
  `beads-dispatch` menu fails to open. `beads-menu--provider-children` appends
  the provider's raw group vectors to a group's `:setup-children`, but
  transient 0.13.8 feeds that return value straight to
  `transient--init-child`, which expects already-parsed specs — so `"City"`
  is read as a class name. Not a gascity.el defect (the provider returns
  exactly the documented contract) and not on the `S` path; filed in the
  beads.el rig with the repro and the fix direction.
- **F2 — cold-start target absence (documented, F4).** With no gascity view
  open the Who picker offers only beads.el's local targets; the gc roster
  appears once a city is known (see "Cold start"). The manual documents this.
- **F3 — city-scoped cross-store route is not warned (gascity.el; filed
  `ga-6lo2o`).** `gascity-sling--cross-store-p` deliberately exempts a
  `city` scope ("the mayor routes beads of every store", mockup §5b), but gc
  1.5.1 refuses that route for a rig-store bead. The footer said
  `✓ Ready — … target mayor`, and only the gc failure surfaced the problem.
  Advisory gap, not a refusal bug: gc's error is clear and the backend echoes
  it correctly. Filed as follow-up rather than grown into B8.

## Cleanup

The pass left no live artifacts:

- `bright-lights`: `bl-fgg6` (input bead), `bl-sx9x` (root), `bl-wbnd`
  (convoy), `bl-xatz` (latch), `bl-hnqf` (finalize) all closed.
- `emacs-city`: `ga-a9i6z` (input bead), `ga-gsqi3` (root), `ga-ouzrs`
  (convoy), `ga-i2gaa` (latch), `ga-19rpk` (finalize) all closed; the
  temporary `formulas/e2e-demo.formula.toml` copy removed.

## Limitations

- The `e2e-demo` latch workflow never advances its "Finalize workflow" step
  on its own in either city (0/0 steps, no agent work); the pass closed the
  roots and their steps by hand after collecting evidence, as on the earlier
  formula-sling passes.
- The dispatch was exercised through the `--on` (bead + formula) shape, which
  is the shape that creates a workflow root. The plain (`gc sling TARGET
  BEAD`) and targetless (`--formula`) argv shapes are covered by the B6 ERT
  suite and were not repeated here.
- `P` (full preview) and the failure echo were observed; the recipe preview
  (`r`) was not exercised in this pass — B6/B7 cover it via the gascity
  transient tests and the earlier formula-sling e2e.

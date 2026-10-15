# Dogfood run report — 2026-10-15 — /home/roman/bright-lights (rw)

- **Workflow:** `gascity-dogfood` root `ga-9jqvo`, dogfood step `ga-c8p5a`.
- **Run epic:** `ga-jqt9q` (adopted by the setup step, not recreated).
- **Session:** `gascity.el/gc.implementation-worker-3` (`ec-wisp-djw0yu`).
- **Window:** ~13:04–13:35 CEST, 2026-10-15.
- **gascity.el:** `origin/main` @ `2b2e19e`, worktree
  `worktrees/gc-dogfood-20261015-rw`.
- **City:** local `/home/roman/bright-lights` (HQ `bright-lights` + `hello-world`).
- **Mode:** rw (full-user operations). Issue cap: 8 (4 filed).

## Setup

A non-graphical Emacs (`emacs -nw -Q`) in tmux server `gc-dogfood-20261015`,
loading gascity.el from the run worktree plus `~/workspace/beads.el/lisp` and
its bundled vui. City env anchors (`GC_CITY`, `GC_CITY_PATH`, `GC_RIG*`,
`BEADS_DIR`, …) were unset so the UI resolved the city from each buffer's
`default-directory`; every emacs/tmux call was wrapped in `timeout`, and all
writes went to the run worktree. The session inherited some worker env
(`GC_DISABLE_USAGE_METRICS=1`, `GC_PROVIDER`, `GC_SESSION_*`) — a harness
artifact, noted below.

## What was exercised

Checklist from the raw log (`SESSION-LOG.org`), read + full-user (`rw`)
navigation:

| View / action | Key | Result |
| --- | --- | --- |
| Cockpit (status) | `j` | PASS — header `▲ degraded (agent_state_unknown)`, agents 2/5, sessions 2, runs 0, ready 12 |
| Needs-you store row | — | **FAIL** — doubled `store health: store health:` label + truncated timeout (→ `.1`) |
| Agents list + tree | `j a` | PASS — 2 rows; tree `City → bd.dog scaled 0–2 → bd.dog-1/2 stopped, control-dispatcher active` |
| Runs + live detail | `j r`, `F` | **FAIL** — `1 active · 7 waiting · 29 done · 3 failed` but section header `Active 8` (→ `.2`) |
| Events | `j e` | PASS — churn folded (`order.fired/completed ×149`); `session.stopped bd.dog` |
| Mail | `j m` | PASS — inbox empty |
| Health | `j h` | **FAIL** — same store-health doubled prefix + `list timed out` (→ `.1`) |
| Cities | `j c` | PASS — `bright-lights 2/5`, `emacs-city 6/9`, both `▲` |
| Rig list | — | PASS — bright-lights (bl, running) + hello-world (hw, stopped) |
| Rig dashboard hello-world | `j g` | PASS — 1 stopped agent, Ready 2, 5 convoys |
| Session list | — | PASS — control-dispatcher + mayor, both active |
| Orders | `j o` | PASS — beads-health, cascade-nudge-on-blocker, cross-rig-deps, dolt-health, dolt-remotes-patrol |
| Convoys | `j v` | PASS — bl-106, bl-3bhn, bl-5x3, bl-b9u, bl-ej6a |
| Dolt | `j D` | PASS — empty (no dolt dbs on bright-lights) |
| Costs | `j $` | **FAIL** — `INVOCATIONS 0`, `EST_USD 0.0000` beside `WALL_S` up to 46490 (→ `.3`) |
| Cockpit Rigs footer | — | **FAIL** — `Rigs 1` vs 2 in rig list (→ `.4`) |
| Beads delegation | `j b` | PASS — `gascity-rig-beads "hello-world"` opened `*beads-dashboard<hello-world>*` correctly scoped |
| Sling via `S` transient | `S` | PASS — `A` freeform → `f` formula `e2e-demo` → `s` Sling; echo `Launched workflow hw-kid5 (e2e-demo on hw-yz8c) — F: run view` |
| Follow offer | `F` | PASS — opened live run detail for `hw-kid5` (`Steps 0/0`, no live worker) |
| Refresh | `g` | PASS |

All views rendered against bright-lights; store/SWR behaviour held (live stream
showed `● live` and repainted on the 2.5 s batch).

## What was done (rw)

- Slung `e2e-demo` via the `S` transient with freeform work text; `F` opened the
  live run detail. The new run and the created bead `hw-yz8c` both appeared in
  the Runs view and the beads.el dashboard.
- Opened the beads.el dashboard for `hello-world`, confirming the delegation
  contract (DESIGN.md §4.3).
- No destructive operations; no other agents' work touched.

## Findings filed (4 of 8 cap), under epic `ga-jqt9q`

| id | pri | type | title |
|---|---|---|---|
| `ga-jqt9q.1` | P2 | bug | Dashboard/Health store-health doubled prefix + persistent timeout |
| `ga-jqt9q.2` | P3 | feature | Runs view lumps `waiting` runs under "Active" |
| `ga-jqt9q.3` | P3 | feature | Costs view unexplained `EST_USD 0.0000` |
| `ga-jqt9q.4` | P4 | feature | Cockpit "Rigs" section omits HQ rig |

### Triage verification

- **Real** — each finding is reproduced by a pane capture in `SESSION-LOG.org`
  and, for `.1`, corroborated by `gc status`/`gc doctor` on bright-lights while
  the UI still warned.
- **Deduped** — searched open beads in the gascity.el rig (prefix `ga`) and the
  beads.el rig (store `be`, routes `~/workspace/beads.el/.beads/routes.jsonl`);
  no existing open bead covered these defects. No `be-` open bead matched the
  findings.
- **Routed** — all four are gascity.el UI/gc-CLI defects → gascity.el rig;
  `.1` carries the `gc-bug` label (the other three are feature/improvement
  requests, correctly unlabeled `gc-bug`). All four are labeled `dogfood` and
  linked to `ga-jqt9q` (parent-child).
- **Severity honest** — `.1` P2 (persistent user-visible warning state), `.2`
  and `.3` P3 (misleading/stale presentation), `.4` P4 (cosmetic count mismatch).

## Findings NOT filed

- **View-open city resolution silence** — invoking a view from a non-city
  `default-directory` silently showed *emacs-city* data; triggered here by
  non-interactive invocation, needs a real-buffer repro.
- **Non-interactive prompt blocking** — `emacsclient -e` on a prompting verb
  wedged at the minibuffer; harness guidance, not a product defect.
- **beads.el dashboard breadcrumb** — `Beads-Dashboard — hello-world` does not
  name the owning city; single low-confidence observation.
- **Harness artifact** — the dogfood Emacs inherited `GC_DISABLE_USAGE_METRICS=1`
  etc., which may have zeroed the Costs view; future runs should launch with a
  clean environment.
- **Bright-lights data state** (not product) — six `waiting` runs since
  Sep 23–27, `order-tracking-sweep` failure at 12:45, heavy order churn.
- Remaining observations documented in `improvement-plan.md`.

## Improvement suggestions

See the operator-requested consolidated plan:
`plans/dogfood/runs/2026-10-15-bright-lights-rw/improvement-plan.md`.

Highlights: fix the store-health doubled prefix and investigate the retained-row
count timeout; split the Runs "Active" section by state; annotate zero-cost rows;
include or explicitly exclude the HQ rig in the cockpit. beads.el's contribution
is deliberately small (dashboard breadcrumb) because no beads.el defect was
reproduced and the gascity→beads scoping contract held.

## Capability gaps

None blocking. The only gap is that a view opened from a non-city buffer gives
no indication of which city it resolved — noted as a non-filed follow-up.

## Deliverables

- `plans/dogfood/runs/2026-10-15-bright-lights-rw/improvement-plan.md`
  (consolidated gascity.el + beads.el plan).
- `plans/dogfood/runs/2026-10-15-bright-lights-rw/report.md` (this file).
- `SESSION-LOG.org` (raw run log, in the run worktree).

## Limitations

- Only ~30 min wall clock, so some views (convoy/order/dolt details, beads.el
  list/show/detail) were opened but not deeply exercised.
- The inherited worker env is not a user environment (see above).

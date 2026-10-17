# Dogfood run report — 2026-10-17 (run 2) — /home/roman/bright-lights (rw)

- **Workflow:** `gascity-dogfood` root `ga-b4ms6`, setup step `ga-a6joz`,
  dogfood step `ga-akmkv`, wrap-up `ga-hg9v3`.
- **Run epic:** `ga-40tbg` (created by the setup step).
- **Session (dogfood step):** `gascity.el/gc.implementation-worker-1`
  (`ec-wisp-56bexa`); wrap-up session `gascity.el/gc.implementation-worker-2`
  (`ec-wisp-8021i9`).
- **Window:** ~20:02–20:10 CEST, 2026-10-17 (finish-in-progress, closed early
  once the focus was exercised; 40 min budget, 10 min report cadence, 6 issue
  cap).
- **gascity.el:** `origin/main` @ `f32a8c7`, worktree
  `worktrees/gc-dogfood-20261017-rw`.
- **City:** local `/home/roman/bright-lights` (HQ `bright-lights` +
  `hello-world`).
- **Mode:** rw (full-user operations). Issue cap: 6 → **6 filed**.

> This is the **second** dogfood run on 2026-10-17 (same city/mode path). The
> first run's report (epic `ga-x9gys`, root `ga-v42a7`, 15:02) is archived at
> `report-20261017-1502-prior-run.md`; its raw log is
> `SESSION-LOG-20261017-1502-prior-run.org` in the run worktree. The current
> run is a fresh workflow, not a reclaim.

## Setup

A non-graphical Emacs (`emacs -nw -Q`) on its own tmux server
`gc-dogfood-ga40tbg`, session `gc-dogfood-ga40tbg-rw`, loading gascity.el from
the run worktree plus `~/workspace/beads.el/lisp` and its bundled vui 1.4.0
(`.dogfood-init.el`). City env anchors (`GC_*`, `BEADS_*`) were unset for the
Emacs process so city resolution followed each buffer's `default-directory` —
a real user environment. The worktree has no `city.toml`; views were opened
with `default-directory` bound to `/home/roman/bright-lights/`. Every
emacs/emacsclient/tmux call was wrapped in `timeout`. Target city is local
`/home/roman/bright-lights` (rigs HQ + `hello-world`).

**Focus:** slinging formulas through the `S` transient, especially formulas
with variables — the `--on` (bead-first) and `--formula` (bare) paths, vars
(defaults, required, seeds, choices), the derived Who target, the full preview
(`P`), dry-run, launch and follow (`F`).

## What was exercised

Checklist from the raw log (`SESSION-LOG.org`), read + full-user (`rw`)
navigation:

| View / action | Key | Result |
| --- | --- | --- |
| Cockpit (status) | `j j`/`g` | PASS — `▲ degraded (agent_state_unknown)`, agents 1/5, sessions 3, runs 0→2, ready 12→13, mail ▲7; live ↻ and `g` refresh work |
| Agents list | `j a` | PASS — mayor (active, pi), city + hello-world `core.control-dispatcher` (idle, `1970-01-01`) |
| Agents tree | `T` | PASS — City pool / dispatchers / mayor; hello-world dispatcher |
| Agent `core.control-dispatcher` | `i`/`RET` | **FAIL (repro)** — `last active`/`created 1970-01-01`, transcript fails on ambiguous workdir → open **ga-4mvlw.1** |
| Beads dashboard | `j b` | **FAIL** — empty `RET` on the “Beads for:” prompt → “Could not resolve the bead store for rig” (filed `.2`) |
| Runs | `j r` | **FAIL (repro, not refiled)** — header `3 failed` vs `Failed none · last 24h`; failures counted under `Done` (known **ga-x9gys.2** family) |
| Run detail (`hw-23gq`, `bl-69ao`) | `RET`/`C` | PASS — formula + source + convoy, `Steps 0/0`, control-node view; latch runs stay 0/0 (no live worker, by design) |
| Events | `j e` | PASS — launch `bead.created` rows; heavy `order.fired/completed` churn folds/unfolds |
| Mail | `j m` | PASS — reads/threads/compose open; message bead scoped via beads.el |
| Health | `j h` | PASS with residual — supervisor degraded; gc 1.5.0 / BdStore; store `◐ list timed out: context deadline exceeded` (known `ga-jqt9q.1`) |
| Cities | `j c` | PASS — bright-lights 1/5 ⬣2 ▲7; emacs-city 2/7 ▲7 |
| Orders / Convoys / Dolt | `j o`/`j v`/`j D` | PASS — host-qualified buffer names; orders/convoys render; Dolt owned by bd |
| Sling transient (open) | `S` | PASS — `A` work, `f` formula, `T` target, `s` sling, `P` full preview, `r` recipe, `g` refresh, `x` reset, `q` quit |
| Sling derived Who | — | PASS — no `T` needed; header shows `hello-world/gc.implementation-worker` for build-basic / github-pr-review |
| Sling **build-basic** | `f` | PASS + **FAIL footer** — vars and seeds render; footer false-positive “Missing required vars: artifact_root” while the seed is used (filed `.3`); `P` full preview resolves the target + route command → **ga-x9gys.3 fix confirmed** |
| Sling **e2e-demo-on** (`--on`) | `A`/`f`/`T`/`s` | PASS — `bl-ha1r` + input convoy `bl-vryc` + latch `bl-lwkz`; `note` default substituted; changing `T` cleared the cross-store warning |
| Sling **e2e-demo** (`--formula`) | `f`/`s` | PASS — bare formula launched root `hw-23gq` in the target’s store; `F` opened its run detail when pressed after the echo landed |
| Sling **github-pr-review** | `f` | PASS — footer + `s` correctly refuse `Missing required formula vars: github_pr_url` |
| Sling follow | `s`,`F` | **FAIL** — `F` is only a momentary post-launch keymap; unbound in Runs and race-prone (filed `.4`) |
| Sling terminal fit | `S` | **FAIL** — 34-line transient in an 80×23 frame hides header + Actions for multi-var formulas (filed `.5`) |
| Sling `artifact_root` seed | `A` | **FAIL** — ignores the picked work bead’s title, falls back to the formula name (filed `.6`) |
| Sling Who completion | `T`/Tab | **FAIL** — derived role target not in candidates; Tab reports `[No match]` (filed `.7`) |
| Transient cancel/reset | `C-g`/`x`/`q` | PASS — clean abort/reset/quit, no state leak |

All views rendered against bright-lights; store/SWR behaviour held (`● live`,
repaint on the 2.5 s batch).

## Actions taken (rw)

- Created disposable target bead `bl-ha1r` (“dogfood 2026-10-17 sling target”,
  label `dogfood-target`) in the bright-lights store.
- Slinged `e2e-demo-on` onto `bl-ha1r` (target `core.control-dispatcher`):
  root `bl-69ao`, input convoy `bl-vryc`, latch `bl-lwkz`, finalize `bl-m8iq`.
- Slinged `e2e-demo` bare (derived target): root `hw-23gq`, latch `hw-87v2`,
  finalize `hw-2qyx`.
- Read-only probes on `build-basic` and `github-pr-review` (no launches).
- No destructive operations; no other agents’ in-flight work touched.
- SITREPs: `ec-wisp-8z8t70` (mid-run) and a final report at close, to the
  emacs-city mayor.

## Findings filed (6 of 6 cap), under epic `ga-40tbg`

| id | pri | type | labels | title |
|---|---|---|---|---|
| `ga-40tbg.2` | P3 | bug | dogfood, gc-bug | Cockpit `j b`: empty RET on the “Beads for:” prompt yields “Could not resolve the bead store for rig” |
| `ga-40tbg.3` | P3 | bug | dogfood, gc-bug | Sling footer claims “Missing required vars” for a var whose seed the dispatch actually uses |
| `ga-40tbg.4` | P3 | bug | dogfood, gc-bug | Sling follow (`F`) is only a momentary post-launch keymap and is not bound in the Runs view |
| `ga-40tbg.5` | P4 | bug | dogfood, gc-bug | Sling transient overflows a 23-line terminal: the Actions row is off-screen for multi-var formulas |
| `ga-40tbg.6` | P4 | bug | dogfood, gc-bug | Sling `artifact_root` seed ignores the picked work bead’s title (falls back to the formula name) |
| `ga-40tbg.7` | P4 | bug | dogfood, gc-bug | Sling Who (`T`) completion has no candidate for the derived role target; Tab reports `[No match]` |

`ga-40tbg.1` (“DOGFOOD-ZZZ probe”, an empty in-run probe) was **closed** at
wrap-up — it is not a finding.

### Triage verification

- **Real** — each is reproduced by a pane capture in `SESSION-LOG.org` and
  names the exact divergence in the bead body: `.2` `gascity-jump-beads`
  (`gascity-dashboard.el:2271`) treats an empty `completing-read` result as a
  rig name (empty string is truthy); `.3` `gascity-sling--footer-info` reads
  `transient-args`, missing the `:var-seed` infix; `.4` `gascity-runs-mode-map`
  has no follow binding; `.6` `gascity-sling--work-title` misses a cold
  work-choices payload; `.5`/`.7` are the observed 34-line transient and the
  `[No match]` completion.
- **Deduped** — searched OPEN beads in both rigs before filing (gascity.el:
  `ga-4mvlw.1/.2`, `ga-jqt9q.1`, `ga-x9gys.*`, `ga-40tbg`; the beads.el query
  aliases the same store) for follow / required-var / transient / seed / Who
  terms; no duplicates.
- **Routed** — all six are gascity.el UI defects → gascity.el rig, each labeled
  `dogfood` + `gc-bug` and linked parent-child to `ga-40tbg`.
- **Severity honest** — `.2`/`.3`/`.4` P3 (misleading error, false validation
  block, missing follow affordance); `.5`/`.6`/`.7` P4 (fit, seed quality,
  completion ergonomics).

## Reproes of open beads (not refiled)

- **ga-4mvlw.1** — city `core.control-dispatcher` renders `1970-01-01` and a
  transcript that fails on the ambiguous workdir (same shape as 2026-10-16).
- **ga-x9gys.2 family** — Runs header `N failed` vs `Failed none · last 24h`,
  old failures under `Done`.
- **ga-jqt9q.1** — store-health `list timed out: context deadline exceeded`
  recurs; environmental/backend, already tracked.
- **bl-bdj formulas-v2 warning** — shown for a city-agent target from HQ scope;
  cleared by a rig-scoped target (known open).

## Findings NOT filed

- **`F` follow race** is filed once (`.4`); its “rising edge before the async
  launch echo lands” half is covered there rather than split.
- **Latch runs staying `Steps 0/0`** — same as the prior run’s `e2e-demo`;
  consistent and by design (workflow-latch, no worker), not filed.
- **Over cap:** none — exactly 6 of 6 filed. No non-reproducible finding was
  logged.

## Improvement suggestions

- **`.2`** — treat `choice = ""` as “city” (or re-prompt) instead of passing an
  empty rig name into `gascity-rig-beads`.
- **`.3`** — have `gascity-sling--footer-info` read the same resolved values the
  dispatcher uses (include the `:var-seed` values), so the footer never warns
  about a var that dispatch accepts.
- **`.4`** — bind `F` in `gascity-runs-mode-map` (open/follow the run at point)
  in addition to the momentary post-launch offer.
- **`.5`** — bound the How (vars) group height (own overflow subgroup with
  “N more vars”), or pin the Actions (and derived-Who) rows so `s`/`P` stay
  visible in a 23-line terminal.
- **`.6`** — fall back to the picked bead’s title (via the work id) when the
  work-choices payload does not carry it, so `artifact_root` slugs the title.
- **`.7`** — include the derived default role in the Who completion candidates
  (annotated as a role) so Tab does not read `[No match]`.

## Capability gaps

- **Var validation (`pattern` / explicit `enum`) could not be exercised** as a
  user: no bright-lights formula declares a var `pattern` or `enum`, so only
  methodology-choice prompts on names like `interaction_mode` exercised the
  choice path. A fixture formula with a required pattern/choice var would close
  this coverage hole.
- The control-dispatcher transcript remains unreachable through the UI (no
  `session_key`, ambiguous workdir) — tracked as `ga-4mvlw.1`.

## Cleanup

Disposable sling artifacts closed at wrap-up:

- bright-lights: `bl-ha1r`, `bl-vryc`, `bl-69ao`, `bl-lwkz`, `bl-m8iq`.
- hello-world: `hw-23gq`, `hw-87v2`, `hw-2qyx`.

(`hw-kid5` from 2026-10-15 was left alone; it belongs to an earlier run.)

## Deliverables

- `plans/dogfood/runs/2026-10-17-bright-lights-rw/report.md` (this file).
- `report-20261017-1502-prior-run.md` (archived first run of the day).
- `SESSION-LOG.org` (raw run log, in the run worktree
  `worktrees/gc-dogfood-20261017-rw`).

## Run verdict

- Issues filed: 6 → run epic `ga-40tbg` stays **open** to track them.
- `ga-40tbg.2`–`.7` verified: real, deduped, correctly routed (gascity.el,
  `gc-bug` + `dogfood`), honest severity, parent-child of the epic.
- **Regression check:** prior run’s `ga-x9gys.3` (full-preview derived target)
  is **confirmed fixed** at `f32a8c7`; `ga-4mvlw.1` and the `ga-x9gys.2` Runs
  header family are reproduced.

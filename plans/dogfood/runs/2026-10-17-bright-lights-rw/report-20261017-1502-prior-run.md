# Dogfood run report — 2026-10-17 — /home/roman/bright-lights (rw)

- **Workflow:** `gascity-dogfood` root `ga-v42a7`, dogfood step `ga-pzbuo`,
  setup step `ga-jfcsg`, wrap-up `ga-qbm7a`.
- **Run epic:** `ga-x9gys` (created by the setup step).
- **Session (dogfood step):** `gascity.el/gc.implementation-worker-2`
  (`ec-wisp-mnt0ho`); setup session `ec-wisp-jke1n1`.
- **Window:** ~15:02–15:13 CEST, 2026-10-17 (started at the top of the 30 min
  budget; the recorded pass below is the result).
- **gascity.el:** `origin/main` @ `80f3612`, worktree
  `worktrees/gc-dogfood-20261017-rw`.
- **City:** local `/home/roman/bright-lights` (HQ `bright-lights` +
  `hello-world`).
- **Mode:** rw (full-user operations). Issue cap: 5 (3 filed).

## Setup

A non-graphical Emacs (`emacs -nw -Q`) on its own tmux server
`gc-dogfood-20261017`, session `gc-dogfood-20261017-rw`, loading gascity.el from
the run worktree plus `~/workspace/beads.el/lisp` and its bundled vui 1.4.0
(`.dogfood-init.el`). City env anchors (`GC_*`, `BEADS_*`) were unset for the
Emacs process and tmux server so city resolution followed each buffer's
`default-directory` — a real user environment. The worktree has no `city.toml`;
views were opened with `default-directory` bound to `/home/roman/bright-lights/`.
Every emacs/emacsclient/tmux call was wrapped in `timeout`. Target city is local
`/home/roman/bright-lights` (rigs HQ + `hello-world`).

## What was exercised

Checklist from the raw log (`SESSION-LOG.org`), read + full-user (`rw`)
navigation:

| View / action | Key | Result |
| --- | --- | --- |
| Cockpit (status) | `j j` | PASS — `▲ degraded (agent_state_unknown)`, agents 1/5, sessions 3, runs 0→1 after sling, ready 12→14, mail ▲8→7; live ↻ and `g` refresh work |
| Agents list | `j a` | PASS — mayor (active, pi), city + hello-world `core.control-dispatcher` (idle, `1970-01-01`) |
| Agents tree | `T` | PASS — City → `bd.dog` pool (scaled 0–2, both stopped) → control-dispatcher, mayor; hello-world → control-dispatcher |
| Agent detail (mayor) | `RET`/`i` | PASS — header `active · last active 1s`; session, pool, workdir, created Sep 21; Transcript renders (last 10, `f` follow / `v` peek) |
| Agent detail (`core.control-dispatcher`) | `i` | **FAIL** — `last active 1970-01-01`, `created 1970-01-01`; Transcript dies on ambiguous workdir → reproduces open **ga-4mvlw.1** |
| Agent detail `v peek` | `v` | **FAIL** — header and Transcript advertise `v peek` but `v` echoes `v is undefined`; peek is only on `a v` (→ `.1`) |
| Runs | `j r` | **FAIL** — header `0 active · 8 waiting · 30 done · 3 failed` vs `Failed none · last 24h`; the 3 old failures render as ✕ under history title `Done 33` (→ `.2`) |
| Events | `j e` | PASS — churn rows fold/unfold; `RET` unfolds individual events; `order-tracking-sweep`, `dolt-health`, `gate-sweep` dominate |
| Mail | `j m` | PASS — 8 unread, page 1/2 → 2/2; RET opens the message bead in beads.el; `r` opens read-only thread and marks read; `c` opens the compose buffer |
| Health | `j h` | PASS with residual — supervisor pid 3288 degraded; gc 1.5.0 / BdStore; store ◐ `list timed out: context deadline exceeded` (backend, not filed); `Rig stores 1` (HQ excluded by design) |
| Cities | `j c` | PASS — bright-lights 1/5 ▲8, emacs-city 2/7 ▲7 |
| Rigs | — | PASS — bright-lights (bl, running), hello-world (hw, stopped) |
| Rig dashboard hello-world | `j g` | PASS — 1 running, Ready 5 (5 convoys hidden), In progress 1 (`hw-cjwm`), Orders none, Dolt none |
| Orders / Convoys / Dolt | `j o` / `j v` / `j D` | PASS — 6 orders, 6 open convoys (all `sling-*`/input), Dolt `lifecycle is owned by bd` |
| Costs | `j $` | PASS — 16 runs, `INVOCATIONS 0` with the explicit “no usage recorded … metrics may be disabled” note |
| Sling transient (freeform/work) | `S` | PASS — `A` bead, `f` formula `e2e-demo`, `T` target; cross-store warning is honest |
| Sling full preview | `P` | **FAIL** — ignores the derived Who target: `(no target — T or default)`, `⚠ no target`, no routing plan, while the menu header and `s` both use the derived target (→ `.3`) |
| Sling launch + follow | `s`, `F` | PASS — `Launched workflow hw-cjwm (e2e-demo on hw-cjwm)`; `F` opened the run detail (Moving/Active); `C` shows the `workflow-finalize` control node |
| Beads delegation | `RET` | PASS — mail RET opened `*beads-show[bright-lights]/*`, correctly scoped (DESIGN.md §4.3) |
| Cockpit `c` on Work bead | `c` | PASS — Bead dispatch menu (sling, close, note, compose note, describe, status, priority, assign, reopen, deps, create, visit); not exercised destructively |
| Second city (emacs-city) | — | PASS — host-qualified buffers coexist; moving `ga-v42a7`, agents `gc.implementation-work…` + `mayor`, rigs emacs-city 0/0 / beads.el 0/1 / gascity.el 2/2 |
| Cockpit Rigs HQ row | — | **FAIL** — `0/0 agents` for emacs-city while the header counts city-level agents → reproduces open **ga-4mvlw.2** |

All views rendered against bright-lights; store/SWR behaviour held (`● live`,
repaint on the 2.5 s batch).

## Actions taken (rw)

- **Sling drill:** created disposable `bl-svfj` (bright-lights city store) and
  `hw-l2ip` (hello-world rig store) beads for the test. The first sling attempt
  on a city bead with the derived target `hello-world/gc.implementation-worker`
  warned cross-store; following the warning's `bright-lights/gc.implementation-worker`
  was rejected by gc (`target_resolve_failed … did you mean
  hello-world/gc.implementation-worker`). Slinged `e2e-demo` onto `hw-l2ip`
  targeting `hello-world/gc.implementation-worker` via the `S` transient; result
  `Launched workflow hw-cjwm (e2e-demo on hw-cjwm)`; `F` opened/followed the run.
- Created two stray beads while learning store routing (`ga-t9x2u`, `ga-g6om5`,
  gascity.el store) and closed both as “created in error”.
- Mail: opened the human-gate mail thread and message bead; opened and aborted a
  compose draft. No message sent except the SITREPs.
- No destructive operations; no other agents' in-flight work touched.

## Findings filed (3 of 5 cap), under epic `ga-x9gys`

| id | pri | type | labels | title |
|---|---|---|---|---|
| `ga-x9gys.1` | P3 | bug | dogfood, gc-bug | Agent detail advertises `v peek` but `v` is undefined (peek is on `a v`) |
| `ga-x9gys.2` | P4 | bug | dogfood, gc-bug | Runs: header `N failed` vs `Failed none · last 24h`, and old failures counted under `Done` |
| `ga-x9gys.3` | P3 | bug | dogfood, gc-bug | Sling full preview (`P`) ignores the derived Who target: shows “no target” and no routing plan |

### Triage verification

- **Real** — each is reproduced by a pane capture in `SESSION-LOG.org`. `.1` and
  `.2` are corroborated in the source (`gascity-session.el:753/431`; agent prefix
  in `gascity-section.el:307`; `gascity-runs--count-line`,
  `gascity-runs-partition`, `gascity-runs-lines`). `.3` names the exact
  divergence: `gascity-sling--run` resolves `(or scope-target derived
  (read-agent …))` while `gascity-sling--full-preview` reads only
  `(plist-get scope :target)`.
- **Deduped** — searched OPEN beads in both rigs (gascity.el: `ga-4mvlw.1/.2`,
  `ga-5tboy`, `ga-qbm7a`, `ga-x9gys`; the beads.el query aliases the same store)
  and text-searched both for peek / cross-store / runs-failed terms before
  filing; no duplicates.
- **Routed** — all three are gascity.el UI/gc-CLI defects → gascity.el rig,
  each labeled `dogfood` + `gc-bug` and linked parent-child to `ga-x9gys`.
- **Severity honest** — `.1` P3 (advertised capability unreachable), `.3` P3
  (preview does not preview what `s` would launch — REQ-008), `.2` P4 (misleading
  run counts/categories).

## Reproes of open beads (not refiled)

- **ga-4mvlw.1** — city `core.control-dispatcher` renders `1970-01-01` and a
  transcript that fails on the ambiguous workdir (same shape as 2026-10-16).
- **ga-4mvlw.2** — cockpit Rigs HQ row reads `0/0 agents` while the header counts
  city-level agents.

Both remain real and are still open; not duplicated.

## Findings NOT filed

- **Store-health `list timed out: context deadline exceeded`** — recurs but is an
  environmental/backend condition, already represented by `ga-jqt9q.1`; not filed.
- **Cross-store warning wording** — names a `<city>/<agent>` remedy that does not
  exist when the city HQ has no agents; the warning also says “pick a city agent”
  and the route is documented (mockup §5b). Not filed.
- **Formula var `note` gets key `ot`** — natural `n` is a reserved static binding;
  by design (`gascity-sling-formula--var-key`), not filed.
- **Over cap:** none (3 of 5). No non-reproducible finding was logged.

## Improvement suggestions

- **`.1`** — bind `v` to `gascity-session-peek-at-point` in
  `gascity-session-detail-mode-map`, or change both header strings to `a v peek`
  to match the documented agent-prefix namespacing.
- **`.2`** — make the header `failed` count use the same window as the Failed
  section (or make both windows explicit), and stop counting failures under
  `Done`; a run should not be simultaneously “failed” and “Done”.
- **`.3`** — resolve `(or scope-target derived)` once in
  `gascity-sling--full-preview` and thread it into the header/validation/dry-run
  and the launch closure, so `P` previews exactly what the menu's `s` slings.
- **Cross-store warning** — when the suggested remedy city has no agents, phrase
  the fix as “pick an agent in a city that has one” rather than naming a
  non-existent `<city>/<agent>`.

## Capability gaps

- The control-dispatcher session transcript is unreachable through the UI (no
  `session_key`, ambiguous workdir) — tracked as `ga-4mvlw.1`.
- Reading the `*gascity-log: bright-lights*` after the failed sling confirmed no
  silent errors; no other capability gap was hit.

## Deliverables

- `plans/dogfood/runs/2026-10-17-bright-lights-rw/report.md` (this file).
- `SESSION-LOG.org` (raw run log, in the run worktree
  `worktrees/gc-dogfood-20261017-rw`).

## Run verdict

- Issues filed: 3 → run epic `ga-x9gys` stays **open** to track them.
- `ga-x9gys.1`, `ga-x9gys.2`, `ga-x9gys.3` verified: real, deduped, correctly
  routed (gascity.el, `gc-bug` + `dogfood`), honest severity, linked to the epic.
- Disposable sling artifacts closed at wrap-up: city `bl-svfj`; hello-world
  `hw-l2ip` and the `e2e-demo` workflow chain `hw-cjwm` / `hw-uqpe` / `hw-wms8`.

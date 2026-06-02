# gascity.el — Dogfood QA Report (gce-tbd)

A hands-on, **interactive** dogfood pass over the gascity.el porcelain, driven
against the **live** Gas Town at `/home/roman/bright-lights`. Unlike the earlier
introspection pass (gce-ea7), this one drives a real Emacs with real keystrokes
in a tmux pane and reads back state via `emacsclient -e`. This is **test + file
only** — no code was fixed here; each bug/improvement is a linked follow-up bead.

## Setup

| | |
|---|---|
| Target | `origin/main` @ `05e5c76` (cu7 MVP + ahl pagination/filters + ez4 mutating + 3iq detail views + afq beads delegation + all five gce-ea7 follow-ups merged) |
| Env | GNU Emacs 30.2, tmux 3.6a; deps from the Guix store (transient 0.13.1, sesman 0.3.4, vui 1.0.0, vterm, eat) + the `beads.el` sibling checkout |
| City | `bright-lights` — controller down · health degraded · **10/26 agents running, 7 suspended** at test time; tmux socket = city name `bright-lights` |
| Method | `emacs -nw -q` in a dedicated tmux server (`-L gce-dogfood`) running an Emacs server (`-s gce-tbd`). Driven by **real keystrokes** (`M-x`, `RET`, `g`, `/`, `]`, `K`, `d`, `t`, `S`) sent to the pane, with `emacsclient -e` reading buffers, point, faces, modes, and pagination — and every datum cross-checked against `gc … --json` / `gc bd` / `gc dolt health` at the same instant. |
| Write-side safety | **No destructive mutation was fired against the live town.** The mutating path was exercised via the confirmation-guard **decline** path (a `K` kill prompt answered "no", target unchanged) and a **disposable** throwaway tmux session for the attach test. All live executions against real state were read-only. |

## PASS / FAIL matrix

| # | Feature | Verdict |
|---|---------|---------|
| 1 | Status dashboard (`gascity-status`) — data, faces, collapse, refresh, point | **PASS** |
| 2 | Session/polecat detail (`RET` on agent) | **PASS** |
| 3 | Session list — data, truncation, `/` filter | **PASS** |
| 4 | Rig list — data | **PASS** |
| 5 | Rig dashboard — 6 async sections | **PASS** — 1 improvement (gce-ziz) |
| 6 | Order list — data, `RET`→source, pagination | **PASS** |
| 7 | Dolt list — data, numeric sort | **PASS** |
| 8 | Convoy list — data; `RET`→beads.el | **FAIL on `RET`** (gce-bhr) |
| 9 | Mail inbox — empty state | **PASS** |
| 10 | `gascity` dispatcher transient | **PASS** |
| 11 | Mutating actions — confirmation guard | **PASS** |
| 12 | Agent actions — Dired, tmux attach | **PASS** |
| 13 | Error surface, customization (executable), filter UX | **PASS** — 1 improvement (gce-ey4) |
| 14 | beads.el delegation (bead-show + rig board) | **PASS** (cross-rig caveat → gce-bhr) |

Net: the porcelain is in strong shape — **1 bug + 2 improvements**, all newly
filed. **All five gce-ea7 follow-ups are now closed and independently
re-verified** behaviourally (see below).

## gce-ea7 follow-ups — re-verified CLOSED

| Bead | Fix | Re-verified this pass |
|------|-----|-----------------------|
| `gce-gie` | g-refresh preserves collapse | ✅ collapsed `▶ example-town-cl` stayed collapsed across `g` |
| `gce-rdk` | tmux socket robust outside city tree | ✅ `gascity-resolve-tmux-socket` → `bright-lights` from inside the tree **and** from `/tmp` (gc-backed `city_name` step) |
| `gce-l5x` | long names truncated, not overflowing | ✅ `example-town-cl/gastown.f…` with full-name `help-echo` |
| `gce-dfe` | clean error surface | ✅ bad executable → `gascity: Cannot run …: No such file or directory`, not a raw condition plist |
| `gce-94g` | numeric column sort | ✅ Dolt Commits sort `8, 182, 196, 2529` (not lexical) via `S` |

## Follow-ups filed (linked `discovered-from: gce-tbd`, label `dogfood`)

| Bead | Type | Sev | Title |
|------|------|-----|-------|
| `gce-bhr` | bug | P2 | Convoy list `RET` fails to open convoys — routed to a per-rig bead store instead of the city-level `gc` source |
| `gce-ey4` | task | P3 | Tabulated lists: no visual indicator when a filter is active |
| `gce-ziz` | task | P3 | Rig dashboard Dolt "open beads" always reads 0 (from `gc dolt health`), contradicting Ready/In-progress sections |

## Detail

### 1. Status dashboard — PASS
Header `Gas City: bright-lights · controller down · health degraded · agents
10/26 running` matches `gc status` (10 running, 7 suspended of 26). The
city→rig→agent tree shows exactly the three rigs that have agents in `gc status`
(example-town-cl, example.city *(suspended)*, gascity.el) with city-scope agents
(dogs/boot/deacon/mayor) under "City"; the 4th rig (`bright-lights`, the HQ) has
only city-scope agents, correctly. `●`/`○` running/stopped faces correct.
**Interactive:** `RET` on `▼ example-town-cl` collapses to `▶` (agents hidden);
`g` preserves the collapse (gce-gie). With point on `● gastown.furiosa`, `g`
keeps point on the same row (no jump). `RET` on an agent opens its detail.

### 2. Session/polecat detail — PASS
`*gascity-agent: example-town-cl/gastown.furiosa*` shows state/provider/attached/
last-active, worktree (`~`-abbreviated), tmux session name, mail count, **On hook
`bs-9cfk in_progress`** (verified: `gc bd show bs-9cfk` → same title/status), and
recent history.

### 3. Session list — PASS
10→9 rows tracked the live town exactly (sibling polecat `gastown.nux` was
observed transitioning `active`→`draining`→gone; the porcelain matched `gc
session list` at each instant — an apparent `active`-vs-`draining` mismatch was
pure snapshot staleness, gone after `g`). Columns Agent/Rig/State/Provider/
Working-dir; long names truncated with `…` + full-name `help-echo` (gce-l5x);
city-scope sessions show empty Rig. **Interactive:** `/` opens a transient
(`-s State` server-side, `-r Rig` client substring, Apply/Clear). Applying
`State=active` → 9 rows, all active — matches `gc session list --state active`
= 9. Filter persists across `g`. (Improvement gce-ey4: no active-filter indicator.)

### 4. Rig list — PASS
4 rigs with Prefix/Status/Branch/Beads all matching `gc rig list`: bright-lights
(bl, running, branch `—` for the HQ, initialized), example-town-cl (bs, running,
main), gascity.el (gce, running, main), example.city (gxc, suspended, main).

### 5. Rig dashboard — PASS (improvement gce-ziz)
`RET` on gascity.el renders 6 independent async sections, all matching ground
truth: header (prefix/branch/beads/city); Agents (7, with roles); Ready (3) and
In progress (2) — equal to rig-scoped `gc bd ready` / `--status=in_progress`;
Orders (10); Dolt (`gce: 196 commits` = `gc dolt health`).
**gce-ziz:** the Dolt line's `0 open beads` is faithful to `gc dolt health`
(which reports `open_beads:0` for *every* DB) but contradicts the Ready/In-progress
lists right above it.

### 6. Order list — PASS
48 orders = `gc order list`; columns Order/Rig/Type/Trigger/Schedule/On, with
city orders showing empty Rig and rig-scoped ones their rig. `RET` opens the
order's source TOML (`…/orders/beads-health.toml`). **Pagination is window-sized:**
at a 14-line window the list paged `[1/4]`; `]` advanced to `[2/4]` with the
correct page-2 rows.

### 7. Dolt list — PASS
4 databases = `gc dolt health` (beads 182, gce 196, guix_vc 8, hq 2529). `S`
(`tabulated-list-sort`) on Commits orders **8, 182, 196, 2529** numerically
(gce-94g), not lexically.

### 8. Convoy list — FAIL on `RET` (bug gce-bhr)
34 convoys = `gc convoy list` (32 `bs-*`, 2 `gce-*`), all open. `RET` on a
`gce-*` convoy opens it in beads.el scoped to the gascity.el store. **But `RET`
on any of the 32 `bs-*` convoys renders "Error loading issue … no issues found
matching the provided IDs"** even though `gc bd show`/`gc convoy show` load every
one. Root cause: convoy `RET` prefix-routes the bead to a per-rig store
(`gascity-beads--bead-path`), while the list itself is sourced city-wide via `gc
convoy list`; convoys are `rig: null` city-level beads, and in this town the
`example-town-cl` store resolves to the `gce` database (it finds `gce-of1` but
not `bs-9cfk`/`bs-0q2z`), so every `bs-*` lookup misses. Fix direction: open
convoys via `gc` (same source as the list) or fall back to the city store. This
goes deeper than gce-ea7, which checked only that the buffer was *scoped* to the
right store, not that its content loaded.

### 9–12. Mail / dispatcher / mutating guard / agent actions — PASS
- **Mail inbox:** clean empty state (header row, 0 entries) = `gc mail inbox` (0).
- **Dispatcher** (`M-x gascity`): transient with all Overview/Lists/Dispatch
  bindings.
- **Mutating guard:** `K` on a stopped agent prompts `Force-kill the runtime of
  session example.city/gastown.slit? (yes or no)`; answering "no" aborts before any
  `gc` call (target unchanged, `running=false`). Uses `yes-or-no-p`.
- **Dired** (`d`): opens the agent's worktree. **tmux attach** (`t` path,
  `gascity-terminal-attach-tmux`): a vterm buffer spawns against a disposable
  session on the `bright-lights` socket; a nonexistent session → clean
  `user-error` "Can't find tmux session … (agent may have stopped)".

### 13. Error surface / customization / filter UX — PASS (improvement gce-ey4)
Setting `gascity-executable` to a missing binary and pressing `g` shows a clean
one-line message, not a raw condition plist (gce-dfe). Filters work and persist
but are not surfaced visually (gce-ey4).

### 14. beads.el delegation — PASS (cross-rig caveat → gce-bhr)
`gce-of1` convoy `RET` → `beads-show-mode` scoped `[gascity.el]`; `gascity-rig-beads`
opens `beads-dashboard-mode` for a rig's store. Single-bead routing for
city-level convoys to a misaligned per-rig store is the gce-bhr failure above.

---

## Environment caveat (not a gascity bug)

The `~/common-lisp/example-town-cl` bead store resolves to the **gce** dolt
database in this town (`bd show` there finds `gce-*` but not `bs-*`). This is a
town/store-config issue, out of scope for gascity.el, but it is the in-town
trigger that makes gce-bhr manifest on 94% of convoys. The gascity-actionable
takeaway — open city-level convoys via the same city-level `gc` source the list
uses — stands regardless.

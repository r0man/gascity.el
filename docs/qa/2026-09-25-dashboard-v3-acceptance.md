# Dashboard v3 — acceptance pass (all views, local + ssh:localhost)

Date 2026-09-25 · QA agent · gascity.el `main` @ **d22b276** · beads.el
`main` @ **badee17** · gc 1.4.2 · Emacs 31.1 `-nw` (v3qa, byte-compiled,
views opened by M-x keystrokes) · raw data:
`~/workspace/gascity.el-wt/qa/out/accept/`. Previous pass:
`2026-09-25-dashboard-v3-cockpit-live.md` (ed57b56).

Cities: `~/emacs-city` (read only), `~/bright-lights`, and
`/ssh:localhost:/home/roman/{bright-lights,emacs-city}`. v3qa's TRAMP runs
with `-o ForwardX11=no` (F8b workaround).

Mutations, all on bright-lights:
- 2 × `gc mail send human` probes, both marked read.
- One message read with `r`, then restored with `gc mail mark-unread`.
- `F` doctor --fix: prompt checked, answered **n**.
- The mayor was nudged twice earlier ("harmless test, no action needed").

## Measured pass: 9 views × 4 city forms + rig dashboards — PASS

Views: cockpit, Agents, Agents tree, Runs, Events, Mail, Health, Cities,
costs. Every view opens in every city form; 0 failures.

| | local | remote (ssh:localhost) |
|---|---|---|
| command sync (ms) | 1–122 (cockpit 85–122) | 2–55 |
| max main-loop stall (ms) | 2–176 (rig dashboards 162–176) | 2–95 |
| settle (s) | 1.1–4.3 | 1.1–5.9 |
| peak concurrent gc | 2–14 local | 3 reads + 1 live stream |

Full table: `out/accept/summary.txt`. Against the baseline
(`qa/baseline.md`): remote opens went from 0.45–9 s to ≤ 55 ms, and stalls
from up to 3 s to ≤ 176 ms.

## Live refresh (§8.2, budget ≤ 5 s) — PASS

bright-lights, cockpit + Agents open, no `g`:

| Change | local | TRAMP |
|---|---|---|
| `gc mail send human` → cockpit `mail ▲4→▲5` | 3.7 s | 3.7 s |
| `gc mail mark-read` → `▲5→▲4` | 2.7 s | 2.5 s |
| max stall during scenario | 54 ms | 98 ms |

## Keys, per view

- **Cockpit:** as in the previous report (TAB/S-TAB/SPC/RET/`j`/`/`/`W`/`g`).
- **Agents table:**
  - `TAB`/`S-TAB` work.
  - `SPC` opens and closes the `*gascity-detail*` side window.
  - `i` opens Agent detail, `v` peek, `f` log follow; the follower's gc
    exits on `q` (no leak).
  - `T` toggles tree/table; `q` buries.
- **Agents tree:** TAB over pools and members; SPC on a member says
  "Nothing to toggle here".
- **Runs:** SPC shows the step ladder; RET opens Run detail (steps, loops,
  plan links, convoy).
- **Events:** the header shows window/count/signal/folded/live. SPC
  unfolds churn; SPC on an event opens a detail window. RET on a bead event
  opens beads-show in 147 ms, so the old sync `bd show` block (previous
  bug 4) looks fixed.
- **Mail:** RET shows the thread and it stays unread; `r` marks it read.
- **Health:** `!` doctor runs async (12 s, max stall 8 ms) and shows
  97 passed · 6 warned with warning rows. `F` asks for confirmation.
- **Cities:** RET opens that city's cockpit.
- **costs:** `gc costs` table shown.
- **Lighter:** `gascity-mode-line-mode` shows `GC[ec@localhost ■7▲3]`,
  does zero TRAMP I/O, and has help-echo and mouse-1.
- **beads.el badee17:**
  - Remote SPC fold/unfold on headers: **no wedge**, zero TRAMP I/O, count
    kept on the folded header (B-1/B-2 fixed).
  - `… and 15 more (+)` is a thing (B-4). Links only on real ids
    (`bl-5zi`, `bl-ab8`, not `build-basic`/`hello-world`) (B-3).
    `▾`/`▸` glyphs (B-5).
  - Remote beads-show: 26 ms to open. Remote dashboard warm: 5 ms sync,
    1.6 s settle.

## Bugs, most severe first

### 1. Medium: Mail inbox misses an external `mail.marked_unread`

**Repro:** in the bright-lights inbox, read a message with `r` (4→3
unread), then run `gc mail mark-unread bl-wisp-a7gsqc` in a shell.
**Evidence:** gc emits `mail.marked_unread` (seq 84427, 21:54:01), and
`gc mail count` says 4 unread. More than 60 s later the inbox still shows
the row as read, with the header `3 unread / 4`. The cockpit and Cities
also keep `▲3`.

### 2. Medium: Agent detail lists unrelated session beads as the agent's Work and History

**Repro:** in bright-lights, Agents → `i` on mayor.
**Evidence:** `Work 3` lists `bl-5a5i core.control-dispatcher`, `bl-rpq
mayor`, `bl-mwo2 bd.dog-1`. `History 5` lists `bl-k6d/59o/cpu/42w/s1j
bd.dog-1`. `gc bd show` on `bl-5a5i`, `bl-mwo2` and `bl-k6d`: all are
`issue_type: session` with `assignee: None`. They are not the mayor's
work.

### 3. Medium: remote beads-dashboard first open blocks ~1.6 s

**Repro:** `tramp-cleanup-all-connections`, Dired on the remote
bright-lights, then `M-x beads-dashboard`.
**Evidence:** command sync 1567 ms. The tracer shows 3.0 s of TRAMP round
trips (store root discovery and executable probe on first contact).
Opening through gascity's `j b` (`:directory` given) avoids the walk.
Warm opens take 5 ms.

### 4. Low-Medium (gap): Agents row does not update after a nudge

`gc session nudge mayor` emits no event, while `session list` shows a new
`last_active`. The Agents row still said `active 13m` 30 s later.
Suggest: invalidate the target's sections when an action completes, even
with live on.

### 5. Low: the same city shows different values on its local and remote Cities rows

In one render: emacs-city local `0/5 ▲` vs remote `1/5 ●`, bright-lights
`0/4` vs `2/4`. The Runs column is always blank.

### 6. Low: Agents tree uses `●` for idle agents; the table uses `○` (§6.1: ○)

### 7. Low: Run detail shows no ✕ step for a failed run

The Runs ladder marks `✕ review` (be-bn2, from a failed nested step). The
detail header says `fail`, but no step row carries ✕. The drawer shows
step bead ids (`requirements be-yam`) where the detail shows iteration ids
(`be-59r`).

### 8. Low: after `r` in the Mail inbox, point lands on the in-buffer column header row

`u` then says "No message at point".

### 9. Low: Agents `SPC` detail window repeats the columns under a stray `●` line

### 10. Carried over from the ed57b56 report, still present on d22b276

- Needs-you pool noise: 10 × `■ session bd__dog cold start timeout`, tmux
  prefix label, no grouping.
- Top line `agents 2/6 ●` against "2 idle · 4 stopped" / `degraded
  (no_agents_running)`.
- The event drawer prints the payload as a raw elisp alist.
- Leaked buffers after killing every view: `gascity-gc-stderr`, and now
  `*gascity-log-stderr: mayor*` from the log follower.
- Idle live re-reads on churn are much reduced: 13 processes per 46 s
  (`events --since 2h` ×2, bd lists ×3), max stall 113 ms.

Fixed since ed57b56:
- render stalls (previously ≤ 2.9 s, now ≤ 176 ms)
- sync `bd show` on RET
- the cockpit `RET`/`SPC` costs

## Harness notes

- `qa-reload` keymap order is fixed; the README is updated.
- **Safety:** `M-x` of the removed `gascity-status` completed (with
  `partial-completion`) to `gascity-bead-set-status` and ran it. The
  prompt was never answered, so nothing changed (command history
  confirms). `qa_open_keys` now refuses non-commands, and v3qa uses
  `completion-styles '(basic)`.
- The live stream no longer counts as busy.

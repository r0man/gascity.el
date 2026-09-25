# Dashboard v3 cockpit — live QA pass (local + ssh:localhost)

Date 2026-09-25 · QA agent · gascity.el `main` @ **ed57b56** (final),
first half on 89c287f · beads.el `main` @ 21edfd2 · gc 1.4.2 · Emacs 31.1
`-nw` in tmux (`v3qa`, byte-compiled, views opened by M-x keystrokes) ·
harness and raw data: `~/workspace/gascity.el-wt/qa/` (`out/v3-cockpit/`,
`out/v3-ed57/`, `out/v3-rerun/`, `f8/`). Baseline for comparison:
`qa/baseline.md` (main @ 141b676).

Cities: `~/emacs-city` (read only), `~/bright-lights`, and
`/ssh:localhost:/home/roman/{bright-lights,emacs-city}` (emacs-city read
only). The one mutation: `M` nudge of the bright-lights mayor ("QA v3 live
pass: harmless test nudge, no action needed").

TRAMP in v3qa ran with `-o ForwardX11=no` added to `tramp-login-args`
(F8b workaround, `qa/README.md`). The F8 loop was also run **without** that
override (the user's real `Host *: ForwardX11 yes` config): 0/16 wedges,
see "Baseline findings re-measured".

## Bugs, most severe first

### 1. High: every store notification re-renders the whole cockpit and re-parses every event timestamp

**Repro:** open `gascity-dashboard` on emacs-city or bright-lights (≈1.4–1.6k
events in 2 h) and watch the stall meter while (a) reads land, (b) `g`,
(c) `SPC`, (d) idle with live on, (e) the ssh master is killed.

**Evidence** (ed57b56):

| Situation | Worst main-loop stall | Command duration |
|---|---|---|
| ssh master killed mid-read, offline → recovery (remote bright-lights) | **2899 ms**, 1858, 1314, 1049, 998 | — |
| `g` refresh, local emacs-city | 826 ms | `gascity-dashboard-refresh` 321–845 ms |
| first local open of a city | 722 ms (emacs-city), 436 ms (bright-lights) | sync 363–729 ms |
| idle 46 s, live stream on | 545 ms, 2 gaps > 200 ms | — |
| `SPC` on any thing | — | `gascity-thing-toggle` 117–150 ms per press |
| `M` nudge, RET in the prompt | 880 ms | `exit-minibuffer` 898 ms |

CPU profiles (`out/v3-ed57/prof-masterkill.txt`, `out/v3-rerun/prof-g.txt`):
56–76 % in GC, and the rest is `gascity-store--notify` →
`vui--rerender-instance` → `gascity-dashboard--lines` →
`gascity-dashboard--activity-lines` → `gascity-dashboard--activity` →
`gascity-dashboard--event-time` → `gascity-ui-parse-time` →
`iso8601-parse`. That parse also runs **inside the `sort` comparator**
(5 % of samples). Every read completion or failure triggers one full
re-render, so an offline storm of failing reads means seconds of
re-parsing.

**Fix:** parse `ts` once, when the events payload is decoded (store
transform, cached with the payload). Fold churn once per payload, not per
render. Sort on the precomputed key. Coalesce notifications, or re-render
only the section a payload feeds. R9 (< 100 ms local, < 200 ms remote) is
violated by every row of the table.

The store agent's expectation ("the only stall > 250 ms is the first open
of a city, ~1 s city.toml walk") is **refuted**. First remote opens are
sync 114–193 ms; the > 250 ms stalls are all this render cost, local and
remote.

### 2. High, fixed during the pass (4b78993): store pump did TRAMP I/O from a timer → deterministic remote wedge

On 89c287f, **8 of 8** cold remote cockpit opens wedged (cold rig
dashboards: 8 of 8 fine). Backtrace (`f8/v3main-*-wedge-2/backtrace.txt`,
`out/v3-rerun/wedge-ec-cold/`): `gascity-store--pump` (timer) →
`gascity-remote-connection-locked-p "/ssh:localhost:"` → `file-remote-p` →
`expand-file-name` → `tramp-get-home-directory` → a synchronous `echo ~`
on the main TRAMP connection, issued from a timer while another TRAMP wait
was active. The connection buffer shows the interleave:
`/home/roman\ntramp_exit_status 0\n///…#$/home/roman\n`. A second reply
lands after the prompt, so TRAMP's prompt match never succeeds and it
spins. The guard caused the reentrant call it exists to prevent.

**Verified fixed on ed57b56:** 0/16 cold opens with the X11 override, 0/16
without. Recommend a regression test: `gascity-remote-connection-locked-p`
must be pure (no file-name-handler I/O) for host-only names.

### 3. Medium: live stream re-reads far too much on churn

**Repro:** leave the emacs-city cockpit idle with live on (ed57b56) for 46 s.

**Evidence** (`out/v3-ed57/idle.gc.json`): 23 gc/bd processes spawned
while idle:
- `events --since 2h` ×3
- `bd list --status in_progress,open,blocked` ×6
- `bd list --label-regex` ×2
- `convoy list` ×2

These are driven by wisp/order churn events. §8.2 routes `order.` to
Activity only, and says Events are appended from the stream, not re-read.
Each re-read feeds bug 1. The header's `↻ Ns ago` does not move for these
event-driven reads (it said "59s ago" while they ran).

### 4. Medium: RET on a bead or event row blocks about 1 s (local stores)

RET on `ga-uc7y` (Work) or on a `bead.closed ec-lpwt` event opens
`beads-show`, which runs `bd show` synchronously for a local store:
`process-file` 955 ms / 1002 ms (tracer). This is a D9 violation, on the
beads.el side (`beads-show-async` defaults to async only for remote
stores).

### 5. Medium: `M` nudge blocks input ~0.9 s after RET

The prompt → RET command (`exit-minibuffer`) took 898 ms, with an 880 ms
stall. The nudge itself is async and correct: the row shows `…`, "Nudged
mayor" is echoed, the pending mark clears, and the mayor woke (`active
10s`). The block is most likely bug 1's full re-render when the row turns
pending.

### 6. Low: Needs-you pool noise and label

emacs-city shows `Needs you 10`, all
`■ session  bd__dog  cold start timeout … ec-lpwt` (and ec-srpu, ec-79pj,
…) for **one** dog pool:
- The label is the tmux-name prefix `bd__dog`, not the agent (`bd.dog-1`).
- There is no grouping, so the pool's restarts push real items into `… 5 more`.
- `RET` on such a row says "Nothing to act on here".

Suggest one row per agent/pool with `×N`.

### 7. Low: top-line agent count disagrees with the Agents section

emacs-city: `agents 2/6 ●` next to `Agents  2 idle · 4 stopped` and gc's
own `▲ degraded (no_agents_running)`. The top line counts idle sessions as
running.

### 8. Low: event drawer prints the payload as a raw elisp alist

Seen on 89c287f: `│ payload ((bead (id . "ec-lpwt") (title . "bd.dog-1")
(status . "clo…`. §5.4 wants `key value` lines.

### 9. Low: churn-row fold and RET

`SPC` on a `×164 order.fired/completed` row expands all 164 events inline
(the buffer goes from 37 to 201 lines). `RET` on it says "Nothing to act on
here" instead of the Events-view target ("not available yet").

### 10. Low: `?` dispatch gaps

The transient has no `j $` (costs) entry, and its header has no live state
(§6.2 shows `● live`). Otherwise it matches §6.2, and every suffix key
equals the view key.

### 11. Low: leaked `gascity-gc-stderr` buffer

A buffer named `gascity-gc-stderr` with no process survives killing all
gascity views, on both commits.

## What works

- **Keys (§5):**
  - `TAB`/`S-TAB` visit exactly the things in order and wrap with
    `Wrapped`; decoration lines are skipped.
  - `SPC` toggles a section header, the `▸ stopped` fold, and the agent,
    bead, Needs-you, event, rig and churn drawers. It does **zero** process
    or TRAMP I/O, local and remote.
  - No run drawer or run row could be tested: no active or recent run
    exists in either city today.
  - `N`/`P`, `DEL`, `S-SPC` behave as specified.
- **RET:**
  - Headers: Needs you/Activity → "Events view is not available yet",
    Moving → "Runs view is not available yet", Agents → session list,
    Work → rig prompt (beads), Rigs → rig list.
  - Rows: bead → beads-show, rig → rig dashboard, `… N more` → its jump.
- **`j` jumps:** `j j a r b m e h c o v d g $` all behave. Unbuilt views
  (runs, events, health, cities, costs) echo "The … view is not available
  yet".
- **`/` filter:** applies on change. `-o` shows order churn (fold count
  1479 → 103), `-c` unfolds churn, `x` resets. `-w`/`-n`/`-m` change
  nothing today because `bd list` already excludes those beads.
- **`W`** stops and restarts the per-city `gascity-live` stream
  (`gc events --follow` over the ssh pipe). The header shows `● live` /
  `○ live off`. **`g`** refreshes (slowly, bug 1).
- **Remote transport (ed57b56):**
  - Reads go over local `ssh -T` pipes.
  - ControlPath is `/tmp/beads-ssh-%C`, separate from TRAMP's
    `~/.cache/emacs/tramp.%C`.
  - Remote concurrency peaks at 3 reads + 1 stream; on 89c287f the remote
    rig dashboard hit 4 reads, now fixed.
  - No `ssh … gc` read outlived its 30 s deadline (15-minute watcher,
    `out/v3-ed57/deadline-violations.txt`, only false positives).
  - No process leaks after killing the views: the live stream's ssh
    exits.
  - Killing the ssh master mid-read gives `○ offline @localhost` within
    3 s and automatic recovery to `● live` after about 20 s. No hang, but
    see bug 1's stalls.
- **Header line** `bright-lights @localhost ● live ↻ 4s ago …` (R1).

## Baseline findings re-measured (ed57b56)

| Baseline | Then | Now |
|---|---|---|
| F1 remote open blocks input | dashboard 8853–8981 ms, lists ~450 ms | cockpit sync **114–193 ms**, lists 2–35 ms (one outlier 131 ms on 89c287f) — **fixed** |
| F2 remote main-loop stall | 2892–3041 ms per open | 159–494 ms per open. Still over 200 ms at times (bug 1); 2.9 s during master-kill recovery |
| F3 local JSON stall | 585–855 ms (json.el) | JSON parse gone from profiles (native); stalls now come from render-time timestamp parsing (bug 1), 163–722 ms |
| F4 rig prompt sync `gc rig list` | 851 ms–1.3 s | rig dashboard command 1–3 ms — **fixed** |
| F5 nested reads lose the city | 4 section errors on buffer switch | not reproduced (cockpit reads through the store) |
| F8 remote wedge | 6/14 (baseline), 8/8 on 89c287f (new pump bug) | **0/16 with override, 0/16 without** — fixed |
| F9 content | 176–193 lines, apology lines | 31–36 lines, no apology lines |
| F10 fan-out | 27–31 processes/open, peak 12 | 9 on a warm open (16 cold incl. `bd context` children), peak 7–11 local, 3 remote |

Full per-view numbers (8 views × 4 city forms): `out/v3-ed57/summary.txt`.
`NOT-SETTLED` rows there are a harness artifact (the long-lived live
stream counted as busy), fixed mid-pass.

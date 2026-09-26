# Dashboard v3 — extended QA (real config, long session, active run, destructive actions)

Date 2026-09-26 · QA agent · gascity.el `main` @ **16e1163** · beads.el @
**0bef79f** · Emacs 31.1 `-nw` in tmux · harness `~/workspace/gascity.el-wt/qa/`.
Items run in the order requested: 8, 6, 3, 2.

## 8. The user's real Emacs config — PASS

### Isolation

- A separate `emacs -nw` in tmux session `v3qa-user` (server name
  `v3qa-user`), started with `--init-directory <copy>`. The copy
  (`qa/userconf/emacs.d`) holds dereferenced `init.el` (2066 lines,
  generated from `init.el.org`), `early-init.el`, `custom.el` and `elpa/`,
  but not the 1.6 GB of caches.
- Side effects found in `init.el` and how each was handled:

| Side effect | Handling |
|---|---|
| `custom-file` hard-coded to `~/.emacs.d/custom.el` (early-init) | copy patched to the copy's `custom.el` |
| `savehist-file` = `~/.config/emacs/savehist` | copy patched to `qa/userconf/state/savehist` |
| `abbrev-file-name` = `~/.config/emacs/abbrev_defs` | copy patched to `qa/userconf/state/` |
| `server-start` | `:if window-system`, so not started in `-nw`; the harness server is `v3qa-user` |
| `desktop-save-mode` | `:disabled` in init, nothing to do |
| `comp-deferred-compilation t` | copy's early-init reads the real `eln-cache` read-only as a fallback; new `.eln` files go to the copy |
| `tramp-use-connection-share nil` | TRAMP would multiplex through the user's real `~/.ssh` ControlPersist 4h masters (one exists for burningswell), and an F8-style stall here could block the user's Emacs. So TRAMP's ssh methods got `-o ControlPath=/tmp/v3qau/%%C`: sharing semantics are unchanged, but on private masters. ForwardX11 was left as the user has it |

- Verified afterwards:
  - The user's Emacs processes (1272 `--daemon`, 29038) were not touched.
  - The real `~/.config/emacs/savehist` was last written by the user's own
    Emacs (its history is the user's); mine went to the copy.
  - The private ssh masters were closed with `ssh -O exit`, and the
    `v3qa-user` session was stopped.
- gascity loaded from `~/workspace/gascity.el/lisp` (16e1163, `.elc`);
  beads.el from `~/workspace/beads.el/lisp` through the user's own
  `use-package beads :load-path` (interpreted, as the user runs it).
- The user's config loaded with no errors or warnings in `*Messages*`.
  Active global modes: corfu, flycheck, undo-tree, which-key, so-long,
  auto-revert, beads-eldoc, goto-address, vertico, guix-prettify. The
  ssh direct-async profile (`remote-direct-async-process`) is active.

### Keys and conflicts

- **In a gascity view** (`gascity-dashboard-mode`), bindings resolve to
  gascity's: `TAB`/`<tab>` → `gascity-thing-forward`,
  `<backtab>` → `-backward`, `SPC` → `gascity-thing-toggle`,
  `j` → `gascity-jump-prefix`, `?` → `gascity-dispatch`,
  `+` → `gascity-section-more`, `RET` → `gascity-dashboard-activate`,
  `/` → filter, `q` → `quit-window`.
- **Real keystrokes in the bright-lights cockpit:**
  - TAB ×3, S-TAB: 0 ms each.
  - SPC ×2: 3–4 ms.
  - `?` shows the dispatch with the jump table.
  - `j a` jumps to Agents (2 ms).
- No conflict with vertico, corfu, which-key or undo-tree. The user's
  global `C-c b` → `consult-bookmark` doesn't shadow anything in the views.

### Smoke test: every view × 3 city forms (views opened via the harness timer mode)

| City | sync | max stall | settle | stuck at `…` | *Messages* errors |
|---|---|---|---|---|---|
| bright-lights (local) | 1–4 ms | 1–53 ms | 0.5–4.6 s | 0 | 0 |
| bright-lights (TRAMP ssh:localhost) | 3–7 ms | 5–51 ms | 1.6–4.6 s | 0 | 0 |
| burningswell (TRAMP, read only) | 3–19 ms | 0–57 ms | 1.5–9.2 s | 0 | 0 |

Views in each form: cockpit, Agents, tree, Runs, Events, Mail, Health,
Cities, costs, rig dashboard.

### Harness incidents during item 8 (no product defects; recorded for safety)

1. **Typed M-x under vertico.** Input arrived as `ga`, completed to the
   `gascity` prefix, and the transient opened; later typed text ran as menu
   and view keys.
   - Commands that ran: `gascity-session-suspend-at-point`,
     `gascity-session-wake-at-point`, `gascity-tmux-at-point`,
     `gascity-session-list`. All of them errored with "No session/agent at
     point".
   - Verified: 0 `session.*` / suspend / wake events in 40 min on
     bright-lights and emacs-city; nothing suspended.
   - Fix: a new `QA_OPEN_MODE=timer` in the harness calls the exact command
     from a timer in the selected window's buffer and never types M-x.
     `qa_open_keys` honours it too; I missed that once, and it reopened
     the prefix harmlessly.
2. **My private ControlPath broke TRAMP twice.** `%C` must be written
   `%%C` for TRAMP's format-spec, and my first path was too long for a Unix
   socket, so burningswell failed to connect. Fixed with `/tmp/v3qau/%%C`.

## 6. Long session (2 h 11 min) — PASS

**Setup:**
- The v3qa Emacs on **16e1163** (started before the move to 14ac61a).
- Three live cockpits: bright-lights local, bright-lights over TRAMP, and
  burningswell over TRAMP (read only).
- gascity/beads ssh masters on a **private** ControlPath
  (`beads-remote-ssh-control-path` = `/tmp/v3qa-ssh/%C`). A new user
  Emacs (pid 11435) was live-streaming burningswell through the shared
  `/tmp/beads-ssh-%C` master, so the network-trouble step must not
  touch the shared master.
- Sampled every 10 min by `qa/long-session.sh`; raw data in
  `qa/out/long/`.

| t | RSS | procs | timers | buffers | streams (all `live`) | max stall in window |
|---|---|---|---|---|---|---|
| +0 | 100 MB | 10 | 3 | 20 | bs 61804 · bl 89787 | — |
| +20 | 61 MB | 10 | 2 | 20 | bs 62064 · bl 90173 | 93 ms |
| +50 | 62 MB | 16¹ | 5 | 21 | bs 62443 · bl 90768 | 113 ms |
| +60 | 62 MB | 16¹ | 6 | 21 | bs 62563 · bl 90894 | 109 ms |
| +71 | 63 MB | 10 | 2 | 20 | bs 62698 · bl 91004 | 92 ms |
| +101 | 65 MB | 10 | 2 | 20 | bs 63039 · bl 91286 | 88 ms |
| +121 | 62 MB | 10 | 3 | 20 | bs 63260 · bl 91480 | **520 ms**² |
| +131 | 62 MB | 10 | 6 | 20 | bs 63379 · bl 91581 | 113 ms |

¹ 6 extra processes (3 more ssh children, 1 stderr buffer) held across
**two** consecutive samples (15:53 and 16:03), so these weren't reads
caught in flight. They were gone at 16:14, but the 16:03 network-trouble
step (masters exited, stream clients killed) came in between and may be
what cleared them. The cause wasn't identified, and a slow ssh-child leak
is **not ruled out**. Worth a targeted re-check without the
network-trouble step. **Resolved by the follow-up below:** not a leak.
It was a saturated burningswell read queue caught in flight twice.
² One isolated gap in the 16:54–17:04 window, cause not captured (no
profiler was running). Every other window is 81–125 ms.

- **No growth or leak:**
  - RSS falls from 100 MB and stays flat at 62–65 MB after 20 min.
  - Processes, buffers and timers return to baseline; 0 stderr buffers.
  - Exactly 1 gc child (the local stream) and 4 ssh children at every
    baseline sample (7 during the footnote-1 window).
  - burningswell host: 8–11 gc processes, 6 `events --follow` (including
    the user's own).
- **Samples +40/+50** overlap with item 3's run in the separate v3qa-b
  Emacs (only host counts are affected).
- **Harness nit:** the `localhost-bl-streams` counter reads 0 after
  16:14, because resumed streams carry `--after N` before `--city`, so my
  pattern missed them. The stream stayed `live` (Emacs state).

**Network trouble at +60 min (16:03), private masters only:**

1. `ssh -O exit` on both private masters: burningswell
   `reconnecting` at +5 s → `live` at +10 s. Both bright-lights streams
   showed `live` at every 5 s sample. No drop was observed, so this step
   didn't really exercise their reconnect.
2. Killed all three stream clients: the local `gc events --follow`, and
   the ssh processes of the TRAMP bright-lights and burningswell streams.
   **Deviation:** the requested "kill the host-side gc stream" did not
   happen. My selector (a bright-lights `gc events --follow` younger than
   40 s) matched nothing, because it ran before the streams had
   reconnected. The burningswell host side was deliberately left alone
   (read only). So this was a client-side kill, not a server-side one. All three were back to `live` within 5 s, and seqs kept
   advancing (bs 62569 → 62579, bl 90902 → 90912 over 60 s).

## 3. An active run end to end on bright-lights — PARTIAL PASS (the run failed for an environment reason; gascity behaved correctly)

Setup, in a separate harness Emacs (`v3qa-b`) so the long-session Emacs
wasn't disturbed:
- Smallest real formula: `do-work` (3 steps: prepare-worktree
  `run-operator`, implement `implementation-worker`, close-source-anchor).
- Most trivial task: new bead `hw-7pm` in the hello-world rig, "add
  exactly one line `# QA v3 probe` after the shebang in hello.sh".
- Before state recorded (`qa/out/run3/`): hello-world on `master` @
  e124cf3, pre-existing uncommitted `.beads`/`.gitignore`/`.gc` changes
  (left alone), no extra worktrees; 256 HQ and 28 hello-world beads.

Sling over TRAMP (`/ssh:localhost:/home/roman/bright-lights` cockpit):
- `S` → `A hw-7pm` → `-f do-work` → `-T hello-world/gc.implementation-worker`.
- `p` dry-run: `gc sling hello-world/gc.implementation-worker hw-7pm
  --on=do-work`, "Would run: gc formula cook do-work --attach hw-7pm".
- `s` at 15:05:39 → "GC sling: ok"; the command returned in 6 ms.

Live observation (Runs view and Run detail, no `g`, polled every 10 s):

| t | Runs card for `hw-tgf` |
|---|---|
| +17 s | `⬣ hw-tgf do-work` · `··· prepare-workt… 0/3 no live worker` |
| +47 s | `⬣·· prepare-workt… 0/3 ● run-operator-1 hw-v2r` — the live worker appears |
| +2 m 20 s | `✕·· … no live worker` — prepare-worktree failed |
| 15:12:54 | `✕✕⬣ … ● run-operator-1 hw-lq9` — close-source-anchor running |
| 15:13:54 | `✕ hw-tgf … fail` — "repair attempt exhausted: source anchor hw-h4m still has no gc.work_dir metadata and no worktree (prepare-worktree hw-v2r failed closed: no origin remote); implement stage cannot proceed" |

Run detail matched: `✕ prepare-worktree hw-v2r fail run-operator`, the
implement iterations, and the final `✕ hw-tgf do-work fail`. The run
closed about 8 minutes after the sling, well inside the 15-minute bound.

- **Cause of the failure (environment, not gascity):** `~/hello-world`
  has no `origin` remote. gc's prepare-worktree is fail-closed
  (`gc.failure_class=missing-remote-default-branch`), so no worktree was
  made and the implementation-worker never did real work.
- **Not exercised:** `i`/`v`/`t` on a live *run* worker. run-operator-1
  lived only ~15:05:42–15:14 and had exited by the time I got to it.
  These keys pass on other live agents (Agents detail, peek, log follow,
  tmux attach) in the earlier passes.
- **Cleanup:**
  - Closed `hw-7pm` and convoy `hw-h4m`; the workflow itself had already
    closed hw-tgf, hw-v2r, hw-hp7, hw-cw4/je5/tbx, hw-lq9, hw-53r and
    hw-y78.
  - The run's sessions exited on their own.
  - hello-world `git status`, branches, worktrees and HEAD are identical
    to before; `hello.sh` is unchanged.

To exercise the success path, the rig needs an `origin` remote. For
example, a temporary local bare clone as `origin`, removed afterwards.
That would spawn real implementation-worker work.

## 2. Destructive actions on bright-lights — PASS with 2 medium bugs (D-1, D-2); `F` skipped by agreement

Run in the separate `v3qa-b` Emacs; bright-lights only.

**State before** (`qa/out/destr/`): city running, not suspended, health
`degraded (no_agents_running)` from a partial runtime probe. Sessions:
`core.control-dispatcher` and `mayor`, both active. Pool `bd.dog-1/2`
stopped. Rigs: bright-lights (HQ) running, hello-world not running.

| Action | Confirm prompt | `…` pending | Echo | Live view update | Result |
|---|---|---|---|---|---|
| `w` wake `bd.dog-1` (stopped pool slot) | — (input-free) | yes | "gc session wake bd.dog-1 failed: session not found" | back to `○ stopped` | **FAIL, see bug D-1** |
| `K` kill `core.control-dispatcher` (cockpit Agents row) | "Force-kill the runtime of session core.control-dispatcher? (y or n)" | yes | "Killed the runtime of core.control-dispatcher" | `○ stopped` at +3 s, `● active 2s` at +6 s (the reconciler restarted it as session bl-bbo2) | PASS |
| `R` reset `core.control-dispatcher` | "Restart session core.control-dispatcher fresh (keep its bead)? (y or n)" | yes | "Reset core.control-dispatcher" | the row kept showing `● active 1m`, while gc reported `asleep` until it woke 2.5 min later | PASS for the action; view stale (D-3) |
| `R` rig restart hello-world, **rig list** row | "Restart (kill agent sessions of) rig hello-world? (y or n)" | yes | "Restarted rig hello-world" | `… → stopped` (no agents were running) | PASS |
| `R` rig restart hello-world, **cockpit Rigs** row | — | — | "No rig at point" | — | **FAIL, see bug D-2** |
| `F` doctor --fix | prompt verified earlier ("Run gc doctor --fix in bright-lights? (y or n)"), answered **n** | — | — | — | **Not run on purpose.** The 5 warnings aren't clearly auto-fixable, and `--fix` could rewrite formula files in the shared pack cache `~/.gc/cache` (which emacs-city also uses) or `git checkout main` in the user's dirty hello-world repo (which has no `main`) |

Pool test note: no pool slot could be run up. `bd.dog-1` has no session,
so wake fails. An ad-hoc `gc session new bd.dog --no-attach` stayed
`start-pending` for ~70 s and was then reaped by the reconciler (min 0, no
work), with `session.cold_start_timeout`. So `K`/`R` ran on the non-LLM
`core.control-dispatcher` instead.

State after these actions: the same as before. Sessions
`core.control-dispatcher` (now bl-bbo2) and `mayor` are active, hello-world
is stopped, the city is running.

Bugs:
- **D-1 (medium):** `w` is offered on stopped pool slots (`bd.dog-1`) that
  have no session. gc can't wake them ("session not found"). Either hide
  or disable `w` there, or start the slot a way gc supports.
- **D-2 (medium):** `R` on a cockpit **Rigs** row runs
  `gascity-dashboard-reset`, which says "No rig at point". §5.3 says `R` on
  a rig row restarts the rig. It works in the rig list
  (`gascity-rig-restart-at-point`).
- **D-3 (low):** after a session reset, gc takes the session `asleep` for
  ~2.5 min but emits no event, so the cockpit keeps showing `● active`
  until the next read.

### 3b. Success path rerun (user-approved `origin`) — PASS

gascity.el `main` @ **14ac61a** (v3qa-b restarted on it).

**Created and kept** (per the user's "add"):
- A bare clone `/home/roman/hello-world-origin.git` of ~/hello-world.
- `~/hello-world` remote `origin` → that path, `master` pushed (e124cf3),
  and `origin/HEAD` → `origin/master` via `git remote set-head origin --auto`.

**Run:**
- New bead `hw-aus` ("add one comment line to hello.sh (run 2)").
- `do-work` slung over TRAMP at 15:33:42, same transient path as 3a; root
  `hw-glg`.

Live, with no `g` (Runs view, then Run detail), from
`qa/out/run3b/watch.txt`:

| Time | State |
|---|---|
| 15:34:26 | `⬣·· prepare-workt… ● run-operator-1 hw-dqg` |
| 15:35:07 | `◆ prepare-worktree hw-dqg pass` |
| 15:35:17 | `⬣ implement hw-wo8 iter 1 ● implementation-worker-1` |
| 15:42:31 | `◆ implement` (pass) |
| 15:43–15:50 | `close-source-anchor` alternates `⬣ in_progress ● run-operator-1` ↔ `· pending` (re-claimed ~5×, a new run-operator session bl-c7d0 appeared) |
| 15:50:54 | root closed, outcome **pass**: Run detail `◆ hw-glg do-work pass … closed`, `Steps 3/3`; the Runs view moved it to done (14 done, 0 active) |

- **Duration:** 17 min 12 s from the sling, about 2 min over the
  15-minute bound. It was in its final step and closed on its own, so I
  didn't cancel it.
- **Live-worker keys**, all over TRAMP:
  - `i` on the worker row → Agent detail
    `hello-world/gc.run-operator-1` (session bl-why4, provider pi).
  - `v` → peek of the live pane ("Working…", model z-ai/glm-5.3-flash).
  - `t` on the implementation worker → vterm attach via `ssh -t
    localhost … tmux attach-session -t gc__implementation-worker-bl-5uqh`
    (1 ms command, pane rendered). Killing the buffer detached it with no
    attach process left.
  - When the worker had already left, `t` echoed "No live worker here".

**What the run produced and what I did with it:**

| Artifact | Action |
|---|---|
| worktree `~/hello-world/worktrees/hw-48k` (detached HEAD 6969703 "qa: add QA v3 probe comment after shebang in hello.sh", +1 line in hello.sh) | `git worktree remove --force`, removed the empty `worktrees/`, `git worktree prune`. 6969703 is now an unreferenced object |
| `~/hello-world/.gc/artifacts/hw-3kv-implementation-summary.md` (the dir was created by the run) | copied to `qa/out/run3b/`, then removed with its dir |
| origin `/home/roman/hello-world-origin.git` | nothing was pushed; refs identical to before |
| beads hw-glg, hw-dqg, hw-wo8, hw-3kv, hw-qmm, hw-jdn, hw-3nt, convoy hw-48k | already closed by the workflow |
| source bead hw-aus | closed by me |
| sessions run-operator-1, implementation-worker-1 | exited on their own |

After cleanup: hello-world `git status`, branches, worktrees and HEAD equal
the before state (`qa/out/run3b/*-before.txt`); `hello.sh` is unchanged.

Findings (low):
- **R-1:** the worker's Agent detail listed Work `hw-qmm Close owned source
  anchor` while the worker was running prepare-worktree (`hw-dqg`).
- **R-2:** close-source-anchor was claimed and released about 5 times in
  7 min (gc/agent behaviour). gascity showed each claim and release
  faithfully.

### City stop/start via `C` (run after item 6, in v3qa-b on 14ac61a)

**Before:**
- supervisor pid 22262 (machine-wide, also serves emacs-city)
- bright-lights controller running, health `degraded (no_agents_running)`
- tmux sessions `mayor` and `core__control-dispatcher-bl-bbo2`
- mayor session_key `01a0d256…`
- dolt sql-server for bright-lights running

**Stop:**
- `C` → `K` "Stop the Gas City? (y or n)" → `y`. The command returned in
  8 ms; "gc stop: finished." after about 8 s.
- After: bright-lights `running False`, controller down, sessions
  `asleep`, the bright-lights tmux server gone.
- The supervisor 22262 **kept running**, and **emacs-city stayed
  running**.
- Cockpit live: `■ controller down`, `agents 0/4 ▲`, `sessions 0`. The
  live streams stayed up, since events are served by the supervisor.

**Start:**
- `C` → `S` "Start the Gas City under the supervisor? (y or n)" → `y`.
  "gc start: finished." at +18 s.
- The cockpit header returned to `▲ degraded (no_agents_running)` by
  itself shortly after the finish echo (timing not recorded).
- 17:20: mayor `active` with the **same session_key** (conversation
  resumed), control-dispatcher active, both tmux sessions recreated,
  controller running under 22262, health and rig states the same as
  before. Expected differences: the control-dispatcher came back on a new
  session bead (`bl-wedp`, was `bl-bbo2`), and the dolt sql-server was
  restarted by its watchdog during the stop (new pid 6926, was 23571).

Finding (low): **D-4.** The stop/start prompts say "the Gas City" and
don't name the city. With several cities open (as here), they should say
"Stop bright-lights?".

### Final state of bright-lights and hello-world

- Same sessions, rigs and health as the recorded before state.
- hello-world has the new `origin` (kept by request) and nothing else
  from the runs.
- All QA beads (hw-7pm, hw-aus and both runs' beads) are closed.

## Follow-up A: leak re-check (35 min, no network trouble) — PASS, no leak; 1 new bug (L-1)

**Setup:**
- Ran on **fe95873**. That is main after 7cf867e plus the D-4 prompt fix
  (commit hash only; the fix itself wasn't exercised).
- A separate harness Emacs, `v3qa-c`. `v3qa` was **not** restarted: a
  client was attached to it (pts/28, focused) showing a burningswell Dired
  buffer I hadn't opened, so the user appears to be using it.
- The same three live cockpits as item 6 (bright-lights local,
  bright-lights over TRAMP, burningswell over TRAMP), with private
  masters on `/tmp/v3qac/%C`.
- `qa/leak-check.sh` takes a full sample every 5 min, plus a process
  count every 20 s. If the count stays above baseline for 2 polls in a
  row, it dumps everything: `(process-list)` with names, commands,
  buffers, pids and ages; `gascity-store-host-status` for each city;
  `gascity-live-cities`; and `ps` of the Emacs's children. Data is in
  `qa/out/leak/`.

| t | RSS | procs | timers | buffers | stderr buffers | children | streams |
|---|---|---|---|---|---|---|---|
| +0 | 101 MB | 10 | 2 | 20 | 0 | 1 gc, 4 ssh | all `live` |
| +5 | 71 MB | 10 | 2 | 20 | 0 | 1 gc, 4 ssh | live, seqs advancing |
| +15 | 72 MB | 10 | 4 | 20 | 0 | 1 gc, 4 ssh | live |
| +25 | 72 MB | **11** | 3 | 20 | 0 | 1 gc, **5 ssh** | live |
| +30 | 74 MB | 10 | 4 | 20 | 0 | 1 gc, 4 ssh | live |

Max stall per window was 78–117 ms. RSS drifted 71 → 74 MB over 30 min,
too little over too short a run to call a trend.

**The 15:53 signature reappeared at 17:50–17:51** and was caught in the
dumps: 16 processes, 3 extra ssh children, 1 stderr buffer, 21 buffers,
5–6 timers. That is exactly item 6's shape.
- burningswell's store was saturated: `:reads 3 :queued 5–8`, with 3
  in-flight `gc … bd list …` reads over the ssh pipe.
- Each read is an ssh process plus its `gascity-gc-stderr` pipe, so 3
  reads account for all 6 extra processes.
- Every ssh read was 0–1 s old (ELAPSED 0/1), so these were fresh reads
  in a burst, not stuck ones. burningswell's seq jumped +148 in that
  window (63738 → 63886, against about +60 in a normal 5-min window).
- By the next full sample the count was back to 10.

**Verdict:** no leak. Item 6's two high samples were the same queue
burst, caught in flight on a busy burningswell. The scheduler caps it at
`gascity-remote-max-inflight` (3), as designed.

### L-1 (medium, new): concurrent ssh-pipe reads share one stderr buffer, so one read's completion discards the others' stderr

`gascity-reader--spawn-ssh` creates its stderr pipe with
`(make-pipe-process :name "gascity-gc-stderr" …)` and no `:buffer`.
Emacs uniquifies the process names (`<1>`, `<2>`) but gives every one of
them the **same** buffer, `gascity-gc-stderr`. That is why item 6 and
this run show 3 pipes but only 1 stderr buffer.

When the first read finishes, `gascity-reader--kill-pipe` kills that
shared buffer. `kill-buffer` then also closes the stderr pipes of every
other in-flight read.

**Reproduced with the real function** (batch Emacs, over ssh to
localhost, `gascity-executable` = `sh`):
- Read A: `sleep 3; echo A-stderr-line >&2; exit 3`.
- Read B: a fast `echo`, started second and finishing first.

| Run | Read A's result |
|---|---|
| A with B | `(:exit-code 3 :stdout "A-out\n" :stderr "")` — **stderr lost** |
| A alone (control) | `(:exit-code 3 :stdout "A-out\n" :stderr "A-stderr-line\n")` |

**Impact:** on an ssh-transport city, a read or action that fails while
another request is in flight loses its stderr. The failure echo (the
first stderr line, per D9) and the `*gascity-log*` entry then have no
reason. This is common whenever the lanes are busy, which is exactly the
burst seen above.

**Fix:** give each pipe its own buffer, for example
`:buffer (generate-new-buffer " *gascity-gc-stderr*")`, or use the
filter only with a unique buffer that `kill-pipe` owns.

## Follow-up B: host-side stream kill on bright-lights — PASS

Same `v3qa-c` Emacs on fe95873.
- Setup: every state change, spawn and delivered seq was recorded through
  advice (`qa/kill-lib.el`).
- To match "its current pid after reconnect": the TRAMP stream was first
  restarted (harness setup), so its host gc carries a unique
  `--after N`. The host gc is then the process whose comm is `gc` and
  whose argv contains that `--after N --city /home/roman/bright-lights/`.
- Each trial also created a probe bead in hello-world to force events.
  The probes are hw-vju, hw-6vz and hw-xo0, all closed afterwards.
- Script: `qa/kill-test.sh`; data: `qa/out/kill/`.

| Trial | What was killed | Transitions (from the recorded state changes) | Resume | Leftovers |
|---|---|---|---|---|
| B1 local | the stream's own `gc events --follow` (pid 21464) | `○ live: reconnecting` → respawn at +2.0 s → `● live` at +3.1 s | new gc has `--after 92068`. Event 92069 happened **inside the gap** and was replayed | old gc gone |
| B2 TRAMP, host side | host gc 8724 (`--after 92069`, child of wrapper sh 8723, watcher 8725) | `○ live: reconnecting` "gc exited 143" (the wrapper reported the exit, so it was correctly **not** classified offline) → respawn at +2.0 s → `● live` at +5.0 s | new host gc with `--after 92070` | old gc, wrapper, `cat` watcher and local ssh client 8721 all gone |
| B3 TRAMP, `ssh -O exit` on the private master (pid 23357) | the mux master | `○ offline @localhost` "connection lost (ssh exit 255)" → respawn at +5.1 s (backoff step 2, because the stream had been up <15 s) → `● live` at +8.1 s; new master 13116 | new host gc with `--after 92076` | old host gc 9804, wrapper 9803 and client 9800 all gone when checked 20 s later. I didn't observe which of the watcher or SIGHUP ended it |
| B4 TRAMP, 3 host kills in a row | host gcs 13121, 22220, 22975 | reconnecting ×3 with backoff 2 s → 5 s → 15 s, then `● live` at +24 s | every respawn used `--after 92086`. Events **92087 and 92088 happened inside the 23 s gap** and were replayed | none |

**Seq continuity:** each stream's delivered seqs were compared with
`gc events --since` for the same range.
- Local and TRAMP streams over B1–B3: 92069…92080, 12 each, no missing
  seq, no duplicates, in order.
- B4: 92087…92095, 9 delivered, no missing seq, no duplicates.

**Orphans:** after all trials, the only bright-lights followers on the
host were the current ones. That is the local gc, plus one wrapper sh,
its gc, its watcher sh and `cat` for the TRAMP stream. No stale wrapper,
`cat` or gc was left from any killed stream. `*Messages*` showed no
errors.

**Notes:**
- A dropped master reads `○ offline @localhost` for about 5 s although
  the host is up. That follows the design: no exit report means the
  connection was lost. Once the respawn succeeds it clears on its own.
- The B2 and B3 probe events weren't emitted by gc until 18–38 s after
  `bd create`, so they missed those gaps. B1 and B4 cover replay inside
  a gap for the local and TRAMP streams.

**Cleanup:**
- `v3qa-c` stopped; its private masters exited and `/tmp/v3qac`
  removed.
- Probe beads closed.
- bright-lights is unchanged apart from 3 closed hello-world beads.
- `v3qa` (attached by the user) was left untouched.

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

¹ Transient reads caught in flight plus the three stream stderr pipes after
a respawn; back to 10 at the next sample. Not a leak.
² One isolated gap in the 16:54–17:04 window, cause not captured (no
profiler was running). Every other window is 81–125 ms.

- **No growth or leak:**
  - RSS falls from 100 MB and stays flat at 62–65 MB after 20 min.
  - Processes, buffers and timers return to baseline; 0 stderr buffers.
  - The only gc child is the local stream; 4 ssh children (2 streams,
    2 TRAMP).
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
   were live again within the 5 s sample.
2. Killed all three stream clients: the local `gc events --follow`, and
   the ssh processes of the TRAMP bright-lights and burningswell streams.
   The host-side-gc heuristic found nothing to kill once the clients were
   gone. All three were back to `live` within 5 s, and seqs kept
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
- Cockpit header back to `▲ degraded (no_agents_running)` at +21 s.
- 17:20: mayor `active` with the **same session_key** (conversation
  resumed), control-dispatcher active, both tmux sessions recreated,
  controller running under 22262, health and rig states **identical to
  before**.

Finding (low): **D-4.** The stop/start prompts say "the Gas City" and
don't name the city. With several cities open (as here), they should say
"Stop bright-lights?".

### Final state of bright-lights and hello-world

- Same sessions, rigs and health as the recorded before state.
- hello-world has the new `origin` (kept by request) and nothing else
  from the runs.
- All QA beads (hw-7pm, hw-aus and both runs' beads) are closed.

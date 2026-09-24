# Bright-lights dogfood pass — ga-pf3c (local + TRAMP)

Date: 2026-09-24. Runner: `gascity.el/gc.implementation-worker-2` (pi session
`ec-egbe`), work bead `ga-pf3c`, molecule `ga-2t70` (mol-polecat-commit).
Code: worktree `worktrees/ga-pf3c` at `origin/main` `29bb650` (includes the
ga-hirj fix set `1e124cf` and everything since: ga-wle9, ga-yam7, ga-eyw9,
ga-hvob).

## How this pass was run

Fresh `emacs -nw -Q` 31.1 inside tmux via `scripts/e2e-harness.sh`
(`e2e_start_emacs`, session/server `gce-e2e`), `load-prefer-newer t`,
load-path = worktree `lisp/` + `~/workspace/beads.el/lisp`. Every checklist
item was exercised in that live Emacs with `default-directory` pointing at
the city; `gc`/`bd` were used only to verify what landed, and then only with
a **scrubbed environment** (see "Environment footgun" below).

Access modes, both run:

- **A. local**: `/home/roman/bright-lights`
- **B. TRAMP**: `/sshx:localhost:/home/roman/bright-lights` (plain `ssh`
  TRAMP method hangs on this host — the F4 deviation re-confirmed; still
  `sshx`, not a gascity defect)

## Checklist results

### 1. `gascity-status` — works in both modes, renders identically

City header (controller PID, `health ok · not suspended`, agents 2/4), City
pool tree (`▼ bd.dog scaled`, workers), running `control-dispatcher`, Named
sessions (`core.control-dispatcher awake`, `mayor awake`), hello-world rig
section, store health (131.8→159.7 MB, 0 live rows). TRAMP buffer is
host-qualified and coexists with the local one
(`*gascity-status@/sshx:localhost:…*` vs `*gascity-status@/home/roman/…*`).

- The ga-hirj health-signals fix renders only when degraded (health was
  `ok` on both reads this time) — n/a this pass.
- ga-jhwz target re-confirmed live: the named-sessions section still
  carried the internal-sounding footnote `mode unavailable from gc JSON
  (gce-8ey)` during the pass; the inline dim `(mode —)` fix was landed in
  the worktree mid-pass by the sibling implement worker (ec-y84f) and is
  covered by updated tests.

### 2. Rig list + rig dashboard — works

`gascity-rig-list` shows bright-lights (HQ, running) and hello-world
(stopped) with prefix/store columns; `gascity-rig-dashboard` for hello-world
renders Agents / Ready (`hw-aij`, later also our `hw-smv`) / In-progress /
Orders / Dolt (`hw: 140 commits` — the ga-hvob dolt fix holds).

- **ga-1kdu half 2 confirmed live**: with the same nil `default-branch`,
  HQ bright-lights renders Branch `—` while hello-world renders an empty
  cell. Fix implemented this pass (render `—` for every nil).

### 3. Sessions buffer — works

Rows render (Agent/Rig/State/Provider/Working dir) in both modes; the `/
filter transient opens with `-s` State / `-r` Rig / Apply / Clear over
TRAMP. Auto-refresh reads are async (log shows `Running async` session-list
lines interleaved, no freezes).

### 4. Bead lifecycle through the UI — works end to end

`gascity-bead-create` (store prompt → `hello-world`) created `hw-smv`;
`gascity-bead-set-priority` 3→2 succeeded; the rig dashboard's `RET` path
(`gascity-at-point-visit` on the bead id) opened
`*beads-show[hello-world]/hw-smv …` **correctly rig-scoped** (ga-wle9's
context-aware store resolution working); `gascity-bead-close` closed it
through its confirmation prompt. Store verified via `gc bd show hw-smv` with
scrubbed env; city kept tidy.

- The confirmation prompt is a **minibuffer y-or-n-p that blocks the
  emacsclient eval channel** — headless/harness drivers must answer it via
  the tmux pane (`y` + `Enter`), not via eval. Documented as a harness
  footgun; not a defect (matches the confirm contract).
- `bd show hw-smv` from a rig-repo cwd **without gc's env** still answers
  "not found" while `gc bd … -C <rig-dir>` works — the known gc store-routing
  env-sensitivity family (ga-x40e, upstream). gascity's own reads are
  argv-pinned and unaffected.

### 5. Sling — both paths land

- Simple sling (`gascity-sling` → mayor): created `bl-hyca`
  "dogfood ga-pf3c: trivial sling test", auto-convoy `bl-idfj`; verified in
  the store with scrubbed env, then closed. City tidy.
- Formula path: `gascity-sling-formula--dispatch` with the bright-lights
  `e2e-demo` formula + `--var note=dogfood-ga-pf3c-formula` → workflow root
  `bl-lyxw` (`gc.formula_name=e2e-demo`, `gc.var.note=…`, `routed_to:
  mayor`), full step graph in the payload. Verified, then closed. The
  ga-4ia4 city-pinning fix holds (the catalog resolved bright-lights'
  `e2e-demo`, not emacs-city's).

### 6. Mail — send / read / mark-read work

`gascity-mail-send` opened the host-qualified compose buffer
(`*gc-mail to mayor@/home/roman/bright-lights/*`); `gascity-compose-finish`
delivered `bl-wisp-pji59v` to mayor (verified in `gc mail inbox mayor`).
`gascity-mail-inbox` renders the ambient identity's inbox in both modes;
`gascity-mail-read-at-point` and `-mark-read-at-point` both ran with exit 0
(`Marked bl-wisp-gl3urr as read`); gc's inbox only lists unread, so the
marked message leaves the list. Test mails deleted.

- **UX finding (minor)**: after send, the inbox list does not refresh on its
  own; `g` is required. Consistent with `q`/`g` conventions but a magit user
  composing from the inbox expects the sent message thread to show up
  (it won't — different identity) or at least a refresh nudge.

### 7. "What's going on" — events gap unchanged

`gc event` still has **no list subcommand and no JSON**
(`json_unsupported` envelope, emit only). ga-69kj remains open; no
porcelain-renderable surface exists.

## TRAMP pass (mode B)

Everything re-verified over `/sshx:localhost:/home/roman/bright-lights`:
status dashboard, sessions list, rig list, rig dashboard (Dolt renders),
mail inbox. Latency: sync `session list` read ≈ 1.1–1.2 s wall including the
client roundtrip; remote gc resolves to the host-absolute Guix path in the
log. No connection thrash observed this pass (the 2026-09-22 hazard needs a
long synchronous eval concurrently with auto-refresh ticks; this pass kept
sync evals short).

## Friction found this pass (ranked)

1. **gc env-sensitivity keeps biting verification** (upstream, ga-x40e
   family): a worker shell carrying emacs-city's `GC_DOLT_PORT`/`GC_RIG`
   cannot probe bright-lights' stores at all (`PROJECT IDENTITY MISMATCH`,
   silent wrong-store answers). Every gc/bd probe in an agent session needs
   `env -i`. gascity itself is immune (argv-pinned), but the *dogfood
   workflow* around it is not.
2. **`gc event` has no list/JSON** — "what's going on" remains a gap
   (ga-69kj).
3. **TAB on the bare "City" / "Named sessions" headers** says "No section to
   toggle here" while carrying `gascity-section` — fixed this pass (honest
   "This section has no collapse state").
4. **Rig-list Branch `—` vs `""`** for the same nil — fixed this pass.
5. **Agent-detail mail `(unavailable)` swallowed gc's failure detail** —
   fixed this pass (`mail unavailable — <envelope detail>`).
6. Minor: inbox does not refresh after a send; rig-list provider cell
   renders empty (not `—`) for pool workers with no provider.

## Fixes implemented in this pass (worker-2, ga-pf3c)

1. `lisp/gascity-session.el` — `gascity-session--mail-vnode` error branch
   surfaces the reader's envelope detail (ga-52t8).
2. `lisp/gascity-status.el` — `gascity-status-toggle-section` distinguishes
   "section exists but not collapsible" from "nothing to toggle" (ga-1kdu).
3. `lisp/gascity-tabulated.el` — rig-list Branch cell renders `—` for every
   nil default-branch (ga-1kdu).
4. (Sibling worker ec-y84f, same worktree: ga-jhwz inline `(mode —)`
   placeholder in named-sessions rows.)

## Environment footguns hit during this pass

- **gc env leak into probes**: the worker shell's `GC_DOLT_PORT=37081`
  (emacs-city) made every bright-lights `bd`/`gc bd` probe hit the wrong
  dolt server (`PROJECT IDENTITY MISMATCH`) or a wrong-city store. Use
  `env -i HOME=… PATH=… gc …` for all cross-city verification.
- **Minibuffer confirmation wedges the eval channel**: destructive UI
  actions (`gascity-bead-close`) prompt y-or-n-p; an emacsclient eval
  driving the action blocks until the pane answers. Harness passes must
  `tmux send-keys` the answer (`y`, then `Enter` — the tmux 3.7c key-name
  footgun from ga-rs12).
- **Stale worktree `.elc` files**: without `load-prefer-newer t` the first
  load silently ran older bytecode than source ("using older file"). The
  harness pass should start Emacs with it set, or the worktree should be
  compiled before the pass.

# ga-yam7 — async/no-hang audit + sync-call bounding: e2e & QA pass

Date: 2026-09-23. Session: `gc__implementation-worker-ec-yg6v` (bead ga-yam7).

## What shipped

- `gascity-remote-sync-timeout` (defcustom, 30s, `0`/`nil` disables) — the one
  bound for every synchronous remote primitive.
- `gascity-remote-with-timeout` macro (`gascity-remote.el`): wraps a body in
  `with-timeout` **only on a remote directory** (a local `process-file` waits
  in blocking C code that runs no timers, so a bound could not fire and a
  local spawn has no network to stall on). On timeout: drain the channel
  (`gascity-remote-drain-connection`) so a retried command starts clean, then
  signal `gascity-remote-sync-timeout` (a `gascity-error` child, so the action
  layer's existing handlers display it cleanly).
- `gascity-reader-run` (the one sync `process-file` site) is bounded — covers
  the executable resolution ahead of the spawn plus the read itself; every
  sync gc read (action verbs, peek, transient completions, the memoized
  city/rig lookups) inherits the bound.
- `gascity-reader-read-async`'s up-front directory probe (the one sync TRAMP
  round trip reachable from auto-refresh timers) is bounded and runs with
  `non-essential`; a timeout errbacks ("no such directory (probe timed out)")
  instead of freezing the tick. (The ga-eyw9 companion work in the same
  window hardened this further with the retry-past-cache-flush verdict.)
- The three tmux probes (`gascity-terminal--tmux`,
  `gascity-terminal-tmux-session-exists-p`, `gascity-terminal-pane-cwd`) are
  bounded; a wedged channel answers nil — uniformly with the other failure
  modes — instead of hanging, which is what lets the status-mirror tick keep
  degrading gracefully after the link dies.

New unit tests (lisp/test/gascity-test.el, ga-yam7 section):
`gascity-test-remote-with-timeout-{local-unbounded,remote-disabled-unbounded,
fires-and-drains,completes-within-bound}`,
`gascity-test-terminal-tmux-probe-bounded-remote`. Suite: 353 tests, all
green (336-test baseline intact). `eldev compile --warnings-as-errors` clean.

## Audit classification (what is bounded vs documented-safe)

Timer/auto-refresh reachability:
- Status dashboard tick: fully async (stale-while-revalidate), loads skipped
  while pending/locked; no sync I/O.
- Session list tick: async fetch; the one sync call in its refresh path
  (`gascity-resolve-tmux-socket`) answers from pinned directory context or the
  payload in hand (no-probe) and never spawns gc from a pinned view buffer.
- Terminal status-mirror tick: sync tmux probes — now bounded (nil on
  timeout) and guarded by `gascity-remote-connection-locked-p` +
  `non-essential`.
- Async-spawn directory probe: bounded, `non-essential` (above).
- eldoc/project paths: already spawn-free (rig memo, I/O-free project).

Sync calls that keep the bound rather than going async: interactive action
verbs, peek, transients/completions, memoized lookups — all bounded by
`gascity-reader-run`'s wrapper (30s default); the e2e flow below exercised
exactly these over TRAMP without a hang.

## E2E verification — bright-lights in BOTH access modes

Harness: `scripts/e2e-harness.sh` (every call `timeout`-bounded; tmux
session verified before send/capture). Emacs: `gce-e2e` tmux session, emacs
`-nw -Q`, gascity + beads.el on load-path.

- Local (`/home/roman/bright-lights/`): `gascity-status`,
  `gascity-session-list`, `gascity-rig-dashboard` all opened; TRAMP-qualified
  and local buffer names coexist as expected.
- TRAMP (`/ssh:localhost:/home/roman/bright-lights/`): status dashboard
  rendered the live city ("Gas City: bright-lights … controller supervisor
  (PID 13318)"); session list rendered rows, pinned dir remote; rig dashboard
  for `hello-world` rendered agents/beads identically to the local pass.
  (`gascity.el`/`beads.el`/`emacs-city` rig dashboards correctly error-staled:
  gc resolves those rigs in the emacs-city workspace, not bright-lights' own
  city.toml — data-plane truth, not a UI defect.)
- tmux probes over TRAMP: socket resolution (`bright-lights`), session
  existence, and pane cwd (`/home/roman/bright-lights`, host-local) all
  correct against the remote server (`tmux -L bright-lights`).
- tmux attach over TRAMP: `gascity-terminal-attach-tmux` spawned the local
  `ssh -t … tmux attach-session` backend, live process, status-mirror timer
  running, mode-line mirror painting (`[mayor] 1:pi*`) with probes against
  `gascity-terminal--status-directory`.
- bead create/show/close over TRAMP: `gc bd create` → `bl-kz0v`; `gc bd show`
  → open, then closed with reason "ga-yam7 e2e verification". Note: local
  `bd show bl-kz0v` (cwd-mode) reports "not found" — the documented
  gc-shared-Dolt store routing (gce-bhr), where gc's pack dispatch resolves a
  different store than the cwd `.beads` config; the gc-routed view is the
  authority and shows `closed`.

## Kill -9 the ssh connection mid-refresh — manual test (documented)

1. Established the live pooled connection (`/ssh:localhost:`), confirmed
   `tramp-get-connection-process` non-nil.
2. `kill -9` the ssh ControlMaster mux process
   (`control-localhost-22-roman`) while dashboards + auto-refresh timers were
   armed (sessions auto-refresh 5s, visible).
3. Bounded probes after the kill (t+0s, t+3s, t+17s): emacsclient evals all
   returned instantly — UI never froze.
4. A sync gc read (`gascity-command-status!`) right after the kill returned
   fresh data: TRAMP transparently re-established (a new mux process
   appeared) and the dashboards refreshed.
5. For the half-dead-link case (reconnect hangs instead of failing), the
   unit-level equivalent is proven:
   `gascity-test-remote-with-timeout-fires-and-drains` (a body yielding to
   the event loop forever is abandoned at the bound and the channel drained)
   and `gascity-test-terminal-tmux-probe-bounded-remote` (the timer probe
   answers nil instead of hanging).

## Wedge reproduced during the pass (evidence, not regression of this work)

Mid-pass the e2e Emacs pegged at 100% CPU and emacsclient evals timed out;
`C-g` recovered it instantly. Evidence chain captured before recovery:
`*Messages*` showed 246 pairs of
`Tramp: Opening connection gascity-gc …/Setup connection gascity-gc …done`
(i.e. TRAMP repeatedly setting up connections for the async gc reader
processes named "gascity-gc"), two
`Setup connection … using ssh...failed` lines, then
`Wrong type argument: processp nil`. With several remote dashboards visible
(each spawning 3–4 async reads per auto-refresh tick) plus the vterm attach,
the per-read connection churn dominated the CPU. The sync-read paths are now
bounded (this bead); the remaining hazard is the per-async-read
connection-open cost — worth a follow-up bead (spawn-rate guard or
connection reuse verification under dashboards+attach; note the W1
measurement of 1 ssh login per 10 async reads predates this session's
buffer count). Recorded here as the reproduced-hang documentation the bead
requires; recovery verified (C-g → responsive, attach buffer healthy,
everything still live).

## Verdict

Acceptance criteria met: no unbounded sync call reachable from timers on a
remote directory; every remaining sync call bounded by
`gascity-remote-sync-timeout` or documented spawn-free; kill -9 recovery
verified manually (responsive throughout); suite 353/353 green with the new
timeout-path unit tests; compile gate clean.
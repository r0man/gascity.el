# gascity.el — Dogfood QA Report (gce-nwc): a remote city over TRAMP

The first **remote-city** dogfood pass: every read surface of gascity.el
exercised against a real Gas City running on a **remote Guix host**, reached
purely over TRAMP (`/ssh:user@example.com:/home/user/example-town/` —
placeholder names per repo policy), with **zero TRAMP configuration** — no
`tramp-own-remote-path`, no connection-local variables, nothing in the init
beyond `(require 'gascity)`. This is the live counterpart to the offline
TRAMP-mock coverage that landed with the remote fixes (gce-qke, gce-k5d): a
real Emacs driven by real keystrokes in a tmux pane, state read back via
`emacsclient -e`, cross-checked against `gc … --json` run on the host over
ssh at the same instant.

**Read-only toward the remote city.** No porcelain mutating command was
executed against it (verified to the prompt/confirm boundary only); no real
agent session was attached to; the one throwaway tmux session used for the
attach tests lived on a **dedicated qa socket** and was killed, with its qa
server, at the end. The city's own tmux server was never touched beyond
`list-sessions`.

## Setup

| | |
|---|---|
| Target | `origin/main` @ `0383c45` — includes both remote fixes: gce-qke (`6a28afc`, direct-async + Guix-profile resolver) and gce-k5d (`0383c45`, child-PATH export). |
| Gate | `scripts/gate.sh` on the fresh worktree **before** the pass: byte-compile clean (warnings-as-errors), **ERT 188/188 pass** — offline. |
| Env (local) | GNU Emacs 30.2, tmux 3.6b, TRAMP 2.7 defaults. Terminal backend pinned to built-in `term` so the attach buffer is scrapeable. |
| Env (remote) | The remote Guix host: Emacs 30.2 available, gc/tmux/bd/dolt in `~/.guix-home/profile/bin` (**not** on `tramp-remote-path`), ssh key auth non-interactive. |
| City (remote) | `example-town` — controller **up**, health ok, 1 rig (`example-rig`, prefix `xr`), 4 agents / 1 running, 2 live tmux sessions on the city socket, dolt store with 2 databases. A live town, not a fixture. |
| Method | `emacs -nw -Q -l <harness>` in a dedicated local tmux server, Emacs server for introspection. Real keystrokes (`M-x`, `TAB`, `RET`, `n/p/N/P`, `g`, `G`, `]`, `[`, `/`, `i`, `d`, `q`, `C-g`, `y/n`) sent to the pane; every rendered fact cross-checked against `gc status/rig list/session list/convoy list/mail inbox/order list/dolt health --json` run on the host via ssh. |
| Write-side safety | Remote writes limited to: one throwaway session `qa-attach-target` on the dedicated `gascity-qa` tmux socket (created and killed, server included), plus the reversible `status off/-u` option on that same session that the attach mirror itself manages. No nudge/suspend/kill/sling/order/mail/bd/dolt mutation ran against the remote. Follow-up beads were filed in this rig's own store. |

## PASS / FAIL matrix — the 11 briefed checks

| # | Check | Verdict |
|---|-------|---------|
| 1 | Entry: `M-x gascity` dispatcher + every direct view command from a remote `default-directory` | **WORKS** |
| 2 | Status dashboard: header vs host JSON, TAB/RET collapse, n/p/N/P, g, auto-refresh + in-flight guard | **WORKS** |
| 3 | Tabulated lists ×6, pagination `]`/`[`/`G`, `/` filters, truncation + help-echo | **WORKS** (one adjacent defect: gce-aks) |
| 4 | Rig dashboard + agent detail, empty sections | **WORKS** |
| 5 | Remote path localization: `d` Dired, RET targets (worktree / order source / bead) | **WORKS** for gascity's own targets; bead RET blocked by gce-9hh |
| 6 | Buffer identity: host-qualified names, local+remote coexistence, pinned refreshes | **WORKS** (beads.el buffers are the exception — see observations) |
| 7 | Executable discovery with zero tramp config; `gascity-context-clear-cache` re-resolves | **WORKS** |
| 8 | Direct-async repeat (status + list + refresh) | **WORKS** |
| 9 | tmux attach via the qa socket: attach / reuse / status-mirror | attach + reuse **WORK**; mirror **BROKEN remotely** (gce-m6k, gce-0aq) |
| 10 | Mutating surfaces to the confirm boundary; argv preview for a remote city | **WORKS** |
| 11 | Error surfaces: wrong path, nonexistent session | mixed — clean user-errors where designed, but async hang (gce-q84) and generic exit-N messages (gce-yn9, gce-aks) |

**Net: the remote read porcelain works end-to-end with zero setup** — every
view rendered the remote city faithfully, resolution/localization/identity
all held, direct-async included. The defects cluster at three seams: the
beads.el delegation (bare `bd`), the tmux status mirror's remote probes, and
error surfacing. **7 beads filed.**

## Detail — evidence per check

### 1. Entry points — WORKS
From a TRAMP dired on the city root: `M-x gascity` renders the full
dispatcher (Overview / Lists / Dispatch / Bead / Mail columns). Each list
key routes to its view against the remote (verified `r` live; the rest
opened directly): `gascity-status`, `gascity-rig-list`,
`gascity-session-list`, `gascity-convoy-list`, `gascity-mail-inbox`,
`gascity-order-list`, `gascity-dolt-list`, `gascity-rig-dashboard` (rig
prompt completes from the **remote** rig set), `gascity-rig-beads`,
`gascity-polecat-detail` (via `i`). A garbage rig name at the
`gascity-rig-beads` prompt user-errors cleanly ("Could not resolve the bead
store for rig …").

### 2. Status dashboard — WORKS
Rendered header `Gas City: example-town · controller up · health ok ·
agents 1/4 running` matches `gc status --json` on the host
(`controller.running:true`, `health.degraded:false`, 4 agents / 1 running)
verbatim; City section lists the 3 stopped city-scope agents (`○`), the rig
section the running one (`●`). Agent rows carry the decoded `gascity-agent`
struct (socket = city name) as a text property; rig headers carry
`gascity-rig-dir` with the **host-local** repo path.

- **TAB / RET toggle** on the rig header: `▼ example-rig` ⇄ `▶ example-rig`,
  both directions, via real keystrokes (buffer-level reads confirm the
  subtree appears/disappears; point survives on the header).
- **n/p** walk agent rows, **N/P** jump section headers (City ⇄ rig).
- **g**: instrumented `gascity-status--refresh-instance` — one call per
  `g`; stale-while-revalidate held: the buffer kept showing full data while
  both loads were in flight (never a bare "Loading…" flash on refresh).
- **Auto-refresh**: timer present with the default 5s interval; counter
  advanced 2× in a 12s idle window (ticks that landed mid-flight were
  correctly skipped by `gascity-status--loads-pending-p` — the guard is
  load-bearing on a remote link where a full load takes 1–2s). **G** toggles
  the timer off/on with a clear message.

### 3. Tabulated lists — WORKS (adjacent defect gce-aks)
All six lists open host-qualified and match the host JSON:

| List | Evidence |
|------|----------|
| Rigs | 2 rows (HQ + `example-rig`); columns incl. "Store"; running/stopped faithful. RET on HQ refuses with the friendly gce-6bq message; RET on the rig opens its dashboard. |
| Sessions | 2 rows = the 2 live tmux sessions; long name truncated `…` **with full-name help-echo**; provider column populated. |
| Convoys | 6 rows; `/` opens the filter transient — `--status=closed` → 0 rows, mode-line `Convoys [1/1] (status=closed)`, clean empty render; clear restores 6. |
| Mail | Empty inbox renders cleanly (`Mail [1/1]`, no rows, no error) — matches host (`messages: []`). READ only. |
| Orders | 20 rows (name truncation + help-echo again). RET opens the order's TOML **on the remote** (see §5). |
| Dolt | `xr: 82 commits`, `hq: 2` — matches `gc dolt health --json`. |

**Pagination** (window shrunk so page-size 5 < 6 convoys): mode-line
`[1/2]`; `]` → `[2/2]` showing the tail row; `[` → back; `G 2` → `[2/2]`.
Page size re-derives from the window on refresh.

**Adjacent defect (gce-aks):** a list whose *fetch* fails renders exactly
like an empty list (see §11).

### 4. Rig dashboard + agent detail — WORKS
`*gascity-rig: example-rig@/ssh:user@example.com:*`: header facts (prefix,
branch, store state, city), Agents (1) with the running agent, **Ready
(100)** populated from the remote rig's bead store via gc, `In progress (0)
(none)`, `Orders (0) (none)`, Dolt commit count, footer key hints — empty
sections render placeholders, no errors. The agent detail (`i` on the row)
renders state/provider/attached/last-active, the worktree path, the tmux
session name, mail count, and clean empty "On hook (0) idle" / "Recent
history (0)" sections for this history-less service agent.

### 5. Remote path localization — WORKS (bead RET blocked by gce-9hh)
- `d` on the agent detail → `dired-mode` on
  `/ssh:user@example.com:~/workspace/example-rig/` — **on the host**.
- RET on an order → its source TOML opened at its host path under the gc
  pack cache, TRAMP-prefixed.
- RET on a bead row routes to the beads.el show view scoped to the remote
  store — the routing and store paths are right, but the view errors
  because beads.el invokes bare `bd` (gce-9hh, §Findings).

### 6. Buffer identity — WORKS
Every gascity view opened against the remote is keyed
`*…@/ssh:user@example.com:*`. A **local** `gascity-status` (this town,
read-only) coexisted: `*gascity-status*` showed `bright-lights · 7/25
running` while `*gascity-status@…*` showed `example-town · 1/4` — `g` in
each refreshed only its own city; auto-refresh timers stayed pinned via each
buffer's `default-directory`. Re-invoking `gascity-status` from a
*different* directory on the same host reuses the per-host buffer (keying is
per host, not per directory). Exception: the delegated beads.el buffers
(`*beads-dashboard<example-rig>*`, `*beads-show[…]*`) are **not**
host-qualified — see observations.

### 7. Zero-config executable discovery — WORKS
With no tramp setup at all: sync `gascity-reader-read "status"` from the
remote directory returned the city payload; `gascity-remote-find-executable`
resolved `gc` and `tmux` to their absolute `~/.guix-home/profile/bin` host
paths; `gascity-remote-path-assignment` built the 3-profile `PATH=…:$PATH`
fragment. `gascity-context-clear-cache` emptied the per-connection cache
(count → 0) and the next call re-resolved and re-cached (count → 1).
Async (tramp-sh) returned the same payload. The dispatcher agent's argv on
the host confirms gc's children resolve (the gce-k5d export) — the city was
started from a plain ssh session on this profile.

### 8. Direct-async — WORKS
With connection-local `tramp-direct-async-process` t for the host (set via
profile, views remounted): the status dashboard rendered identically; the
async spawns are visibly the direct handler — local
`ssh -q -l user … cd /home/user/example-town/ && (env …` processes with
paired **local stderr scratch buffers** (the gce-qke no-string-`:stderr`
design). Session list rendered (2 rows) and `g` refreshed it. Profile
removed afterwards.

### 9. tmux attach machinery — attach/reuse WORK; mirror broken remotely
Against `qa-attach-target` on the dedicated `gascity-qa` socket:

- **Attach**: `gascity-terminal-attach-tmux` from the remote context
  spawned a **local** `ssh -t -l user example.com env -u TMUX
  <abs>/tmux -L gascity-qa attach-session -t qa-attach-target` in
  `*gc-agent-qa-attach-target@/ssh:user@example.com:*` — the terminal
  showed the remote shell prompt (live attach), tmux resolved to the same
  absolute host path the probes used.
- **Reuse**: re-invoking returned the **same buffer, same process** — no
  respawn, no "already has a running process".
- **Status mirror**: the remote side *is* reached (the session's tmux
  `status` was set off; teardown restores it under quiet conditions; the
  mode-line segment is spliced) — but **two remote-specific defects**:
  window labels are lost because tmux sanitizes the probe format's TAB
  separator to `_` over tramp-sh's pty (gce-m6k), and the install-time
  refresh / kill-time teardown treat transient TRAMP contention (e.g. an
  auto-refreshing dashboard on the same connection) as fatal — the mirror
  permanently self-cancels, or the session's status bar is left hidden
  after detach (gce-0aq; both verified: quiet ⇒ works, contended ⇒ fails).

### 10. Mutating surfaces — previews correct, nothing executed
- Dispatcher → **Rig control**: `s/r/R/a/x` (no rig start/stop — matches
  gc). `R` prompted (completion from the remote rigs), then the
  yes-or-no confirm *"Restart (kill agent sessions of) rig example-rig?"* —
  answered **n**; host state verified unchanged (same running-agent count).
- **Session control** transient opened (nudge/suspend/kill/wake/drain/…/
  prune) and quit with `C-g` — no prompt reached, nothing ran.
- **argv previews** (`gascity-command-line`, never executed) from the
  remote context resolve the executable to the **absolute host gc** and the
  documented shapes: `…/bin/gc rig restart example-rig` · `…/bin/gc session
  nudge example-rig/core.control-dispatcher qa` · `…/bin/gc session kill
  example-rig/core.control-dispatcher` · `…/bin/gc sling xr-q16w
  example-rig` · `…/bin/gc order run dolt-health` · `…/bin/gc bd close
  xr-q16w -C /home/user/workspace/example-rig/.beads/dolt` (the inherited
  `-C` store routing with the host-local store path).

### 11. Error surfaces — mixed
| Case | Behavior |
|------|----------|
| Attach: empty session | `user-error: No tmux session for this agent` — clean. |
| Attach: nonexistent session (qa socket) | `user-error: Can't find tmux session: … (agent may have stopped)` — clean. |
| Rig prompt: garbage name | `user-error: Could not resolve the bead store for rig …` — clean. |
| Rig dashboard load failure | In-buffer error state *"Could not load rig: … Press g to retry."* — the right pattern. |
| **Sync** read from a nonexistent remote dir | Clean `gascity-command-error` ("gc status failed (exit 1)"). |
| **Async** read from a nonexistent remote dir | **Hangs forever** — no callback, no errback; view stuck at "Loading Gas City status…", TRAMP channels leak (**gce-q84**, P2). |
| Any gc failure with a JSON error envelope | Porcelain shows only "Command failed with exit code 1" — the envelope's precise `error.message` is discarded (**gce-yn9**). |
| Tabulated list whose fetch fails | Renders as a normal **empty list** + transient echo message — indistinguishable from an empty dataset (**gce-aks**); observed via a dolt list opened from a non-city directory (where gc doesn't even have the subcommand — its envelope said exactly that, invisibly). |

## Findings filed (all linked `discovered-from: gce-nwc`, labels `qa`,`dogfood`,…)

| Bead | Type | Pri | Title |
|------|------|-----|-------|
| `gce-9hh` | bug | P2 | remote: beads.el delegation runs bare `bd` — exit 127 on a remote city with zero tramp config |
| `gce-q84` | bug | P2 | remote: async reads from an invalid remote directory hang forever — no errback, leaked channels |
| `gce-m6k` | bug | P3 | remote: tmux status mirror loses window labels — TAB in `-F` format sanitized to `_` over tramp-sh pty |
| `gce-0aq` | bug | P3 | remote: status-mirror install/teardown treat transient TRAMP failures as fatal — mirror dead or status bar left hidden |
| `gce-yn9` | bug | P3 | error surface: gc's structured JSON error envelope is discarded — user sees only "Command failed with exit code N" |
| `gce-aks` | bug | P3 | tabulated lists render a failed fetch as an empty list — indistinguishable from an empty dataset |
| `gce-cxt` | task | P4 | `gascity-rig-dashboard` prompt offers the HQ pseudo-rig, then fails with a generic exit-1 error |

## Minor observations (noted, not filed)

- **beads.el buffer naming**: the delegated buffers key by rig name only
  (`*beads-dashboard<example-rig>*`) — a local and a remote rig with the
  same name would collide. Moot until gce-9hh makes the remote delegation
  work at all; fold the naming into that fix.
- **Latency**: a full remote dashboard load runs 1–2s per gc read over
  tramp-sh (sequential connection setup amortizes after the first view).
  The in-flight guard (§2) is what keeps the 5s auto-refresh usable; no
  further defect.
- **`gc dolt list --json` emits a plain table** with a rollout warning on
  stderr (no JSON contract yet) — gascity correctly uses `dolt health` for
  its dolt list instead; gc-side, nothing to fix here.
- **Prompt inheritance**: view commands invoked from a buffer whose
  `default-directory` left the city tree (e.g. after visiting an order's
  source TOML under the pack cache) target that directory and fail per
  §11's generic-message rows. With gce-yn9 + gce-aks fixed, the failure
  would at least say why. A "reuse the last city context" affordance is a
  design question deliberately not filed as a defect.

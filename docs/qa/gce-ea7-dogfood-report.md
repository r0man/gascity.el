# gascity.el — Dogfood QA Report (gce-ea7)

A real-Emacs-user dogfood pass over the gascity.el porcelain, driven against the
**live** Gas Town at `/home/roman/bright-lights`. This pass is **test + file
only** — no fixes were made here; each bug and worthwhile improvement is filed as
a linked follow-up bead for the Mayor to dispatch.

## Setup

| | |
|---|---|
| Target | `origin/main` @ `3e8f194` (cu7 MVP + ahl pagination/filters + ez4 mutating + 3iq detail views + afq beads delegation + gce-384 review follow-ups) |
| Env | GNU Emacs 30.2, tmux 3.6a; deps from the Guix store (transient 0.13.1, sesman 0.3.4, vui 1.0.0) + the `beads.el` sibling checkout |
| City | `bright-lights` (controller down / health degraded / 9-of-26 agents running at test time); tmux socket = city name `bright-lights` |
| Method | `emacs -nw` hosted in a dedicated tmux server with an Emacs server; driven both by real keys and by `emacsclient -e` buffer/keymap/face introspection — exercising the actual interactive entry points, not batch ERT |
| Write-side safety | **No destructive mutation was fired against the live town.** Mutations were verified by command-line construction, the shared (proven) execute pipeline, safe `gc sling --dry-run`, fake-target gc rejections, and unit tests of the summarize/validate/guard logic. The only real executions against live state were read-only (`gc … list/status`, `gc session peek`) and a disposable throwaway tmux session for the attach test. |

## PASS / FAIL matrix

| # | Feature | Verdict |
|---|---------|---------|
| 1 | vui status dashboard (`gascity-status`) | **PASS** — 1 bug (B1) |
| 2 | Tabulated lists (rigs/sessions/convoys/mail/orders/dolt) | **PASS** — 1 nit (I1), 1 nit (I4) |
| 3 | Agent actions — Dired + tmux attach | **PASS** — 1 nit (I2) |
| 4 | vui detail views — rig dashboard, session/polecat detail | **PASS** |
| 5 | Command dispatch + mutating actions (write side) | **PASS** |
| 6 | beads.el bead-UI delegation (rig-scoped) | **PASS** |
| 7 | Conventions — q/g/RET, keybindings, error surfaces, customization | **PASS** — 1 nit (I3) |

Net: every feature works. **1 bug (medium) + 4 improvements (low/low-med).** The
porcelain is well-built — clean async, graceful error surfaces, confirmation
guards on destructive actions, and correct rig-scoped beads delegation.

## Follow-ups filed (linked `discovered-from: gce-ea7`)

| Bead | Type | Sev | Title |
|------|------|-----|-------|
| `gce-gie` | bug | medium | Status dashboard g-refresh re-expands collapsed rig sections (collapse state not preserved) |
| `gce-rdk` | bug | low-med | Session list tmux-attach/dired uses wrong tmux socket when opened outside the city tree |
| `gce-l5x` | task | low | Tabulated lists: long qualified/scoped names overflow fixed column widths |
| `gce-dfe` | task | low | Tabulated list error surface dumps raw condition plist instead of clean stderr |
| `gce-94g` | task | low | Numeric tabulated columns sort lexicographically |

## Detail

### 1. Status dashboard — PASS (bug gce-gie)
- Renders `Gas City: bright-lights`, `controller down · health degraded · agents 9/26 running` — matches `gc status` (the "controller down" is accurate: JSON `running:false`, health signal `controller_not_running`).
- City→rig→agent tree assembled by splitting each flat agent's `qualified_name` on `/`; city-scope agents (dogs/boot/deacon/mayor) and collapsible per-rig sections (incl. `example.city (suspended)`) all match `gc status`.
- Faces correct (rig headers via overlay): `gascity-city/-running/-stopped/-rig/-suspended`. Collapsible toggle works. Two async loads (`gc status` + `gc session list`) joined client-side; renders before sessions ready (with a "sessions unavailable" note). Keymap g/RET/d/t/N/s/K/w/D/q/n/p correct.
- **BUG gce-gie (medium):** `g` refresh re-expands collapsed rigs — contradicts DESIGN §7 P3 and the refresh docstring/commentary that promise collapse state is preserved. Root cause: the refresh's `pending` branch replaces the whole tree with a "Loading…" text, unmounting the keyed rig components (and causing a refresh flicker across all three vui views). See the bead for the stale-while-revalidate fix.

### 2. Tabulated lists — PASS (nits gce-l5x, gce-94g)
- All six render correct columns from live `--json`; counts rigs 4 / sessions 9 / convoys 31 / mail 0 / orders 48 / dolt 4.
- Sort (Status, Name) reorders. Pagination real on orders (48 over `[1/2]`): `]`→`[2/2]`, `[`→`[1/2]`, `G` goto, out-of-range → `user-error`. Filters work: rig status, session `--state` (server-side) + `--rig` (client substring), order type/enabled, convoy status, mail unread. RET: order→source `.toml`, dolt→echo, mail→field view (verified synthetically; live inbox empty — reader decodes JSON `false`→nil so the unread marker is correct).
- **I1 (gce-l5x, low):** long qualified/scoped names overflow fixed column widths (Agent 26, Order 28) → misalignment.
- **I4 (gce-94g, low):** numeric columns (Dolt commits/open-beads, convoy progress) sort lexicographically (110,161,2351,8 instead of 8,110,161,2351).

### 3. Agent actions — PASS (nit gce-rdk)
- Dired opens an agent's worktree; falls back to the live tmux pane cwd when `work_dir` is unrecorded (gce-384 a); clean `user-error` when neither resolves. tmux exists-check + pane-cwd correct. Attach spawns a real terminal (backend auto → **vterm**; vterm+eat both present) against a disposable session; nonexistent session → clean `user-error`.
- **I2 (gce-rdk, low-med):** the session list resolves the tmux socket via `gascity-context-city-name`, which needs `default-directory` inside the city tree (verified: inside→`bright-lights`, outside→nil). Opened from elsewhere, `t`/`d`-fallback hit the default tmux server and fail. The status & rig dashboards pass `city_name` from a gc payload and stay robust.

### 4. vui detail views — PASS
- Rig dashboard: 6 independent async sections (header, agents-with-roles, ready/in-progress beads, rig-scoped orders, dolt-by-prefix) all render real data.
- Polecat detail: state / mail / on-hook / history. The slow `gc mail inbox <name>` (~7.75s) shows a pending "mail …" while the rest renders immediately, then resolves — the independent-async design working as intended (not a bug; gc/Dolt perf). `peek` captures live output into a `view-mode` buffer.

### 5. Command dispatch + mutating actions — PASS
- Every mutation builds the correct `gc` line (json off for mutations, on for reads) and maps to a verified real subcommand (incl. `gc runtime drain <target>`, distinct from `drain-ack`).
- Action execute+parse+summarize proven via `gc sling --dry-run` (full plan + echo, no routing). Error handling surfaces clean gc stderr (3 real rejections). Validation rejects missing required args locally. Confirmation guards (restart/kill/start/stop): declining aborts before gc, confirming proceeds. Dispatch transients defined; completion sources return live rig/order/session data.

### 6. beads.el delegation — PASS
- Bead id prefix → owning rig store (gce→`~/workspace/gascity.el/`, bs→`~/common-lisp/example-town-cl/`), resolving DESIGN §9.1 via `default-directory` binding. `gascity-bead-show` → `beads-show-mode`; `gascity-rig-beads` → `beads-dashboard-mode`; convoy RET on a `bs-` id correctly opens it scoped to the **example-town-cl** store (cross-rig).

### 7. Conventions — PASS (nit gce-dfe)
- `q` buries (vui-quit / quit-window), `g` refresh, `RET` drill-in consistent. Error surfaces graceful (rig dashboard "Could not load rig… Press g to retry"; list refresh degrades to empty and recovers). Customization works: `gascity-executable`, `gascity-tmux-socket` (incl. literal "default"), `gascity-terminal-backend`, all 8 faces defined.
- **I3 (gce-dfe, low):** the list refresh error message dumps the raw `gascity-command-error` condition plist; it should reuse the action path's clean stderr extraction.

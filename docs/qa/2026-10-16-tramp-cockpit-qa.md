# Live cockpit & views over TRAMP — QA pass (2026-10-16)

Work bead `ga-y00rd` (workflow `mol-scoped-work`, convoy `ga-d76g0`,
owner gascity.el). This is the follow-up the Magit/Forge-parity study
(`plans/ux/magit-parity-plan.md` §9) left open: render the cockpit and the
read surface **live, interactively, over TRAMP**, not by shelling out to `gc`
and not with the batch matrix driver.

## Setup

| | |
|---|---|
| Target city | `~/bright-lights`, read as `/ssh:localhost:/home/roman/bright-lights` |
| Checkout | worktree `worktrees/ga-y00rd` at `origin/main` `9cbc6fb` (clean) |
| Emacs | GNU Emacs 31.1, `emacs -nw -Q` inside tmux session `gce-y00rd` (server `gce-y00rd`), non-graphical |
| gc | 1.5.0 on `m1` via `ssh -o BatchMode=yes localhost` |
| Transport | default `gascity-remote-transport` = `ssh` (local `ssh -T` pipe), ControlMaster shared |
| Load path | worktree `lisp/` + `~/workspace/beads.el/lisp` + bundled `vui-1.4.0` |
| Bounds | `. scripts/e2e-harness.sh`; every emacs/emacsclient/tmux call under `timeout(1)`; per-view settle deadline 90 s |

Method: visit `city.toml` over TRAMP first (so `default-directory` is the
remote city — the real user flow), then open each view with its real `M-x`
command and drive the keys (`g`, `/`, `N`, `j h`, `RET`, `q`) through
`tmux send-keys`. A second pass opened every view programmatically inside the
same live Emacs, timing the open, waiting for the store to settle, and dumping
each buffer for inspection. Rendered pane text and dumped buffers are the
evidence.

## Checklist (read surface)

| View | Command | Result | Open / ready (s) | Note |
|---|---|---|---|---|
| Cockpit | `gascity-dashboard` | **PASS** | 1.54 / 11.7 | first contact; header `● live`, all 8 sections render |
| Agents | `gascity-agents` | **PASS** | 0.02 / 0.8 | 3 idle rows (stopped hidden by filter, `j a all` shows 5) |
| Agents tree | `gascity-agents-tree` | **PASS** | 0.00 / 0.0 | City + hello-world nodes, stopped `bd.dog-1/2` |
| Sessions | `gascity-session-list` | **PASS** | 0.00 / 0.8 | 3 rows incl. `mayor` |
| Session detail | `gascity-polecat-detail` (mayor) | **PASS** | 0.01 / 2.2 | identity, Work, Transcript (peek) |
| Rig dashboard | `gascity-rig-dashboard` hello-world | **PASS** | 0.00 / 0.8 | Agents/Ready/In progress/Orders/Dolt |
| Runs | `gascity-runs` | **PASS** | 0.00 / 1.9 | 1 active · 7 waiting · 29 done · 3 failed |
| Run detail | `gascity-run-show` bl-06hy | **PASS** | 0.00 / 1.1 | steps 2/2 |
| Events | `gascity-events` | **PASS** | 0.00 / 1.5 | churn folded; `/` filter transient renders |
| Mail inbox | `gascity-mail-inbox` | **PASS** | 0.00 / 0.4 | 8 unread |
| Mail thread | `gascity-mail-thread-show` | **PASS** | 0.00 / 0.4 | body + `r R a u q` footer |
| Health | `gascity-health` | **PASS** | 0.00 / 0.8 | renders the city's partial store health (see Friction) |
| Cities | `gascity-cities` | **PASS** | 0.01 / 1.5 | local + TRAMP rows |
| Dolt | `gascity-dolt-list` | **FAIL** | 0.00 / 0.1 | blank body — defect D1 below |
| Convoys | `gascity-convoy-list` | **PASS** | 0.00 / 6.4 | 13 convoys; ready under contention |
| Orders | `gascity-order-list` | **PASS** | 0.00 / 0.0 | 22 orders |
| Costs | `gascity-costs` | **PASS** | 0.11 / 0.1 | 14 runs, all 0 invocations (usage disabled) |

"Open" is the time the command blocked the command loop; the views mount
asynchronously so this is near zero after first contact. "Ready" is open →
store settled (three consecutive settled samples, including a 1 s stability
margin).

## Interactive keys exercised (through the pane)

- `M-x gascity-dashboard` from the TRAMP `city.toml` buffer → cockpit mounts;
  header reads `bright-lights @localhost  ● live  ↻ 0s ago`.
- `g` refresh → header `↻ 0s ago`, no error, live indicator stays.
- `/` on the cockpit → the Filter transient (`Noise`, `Scope`, `Activity`,
  `x reset`).
- `j h` → jumps to the Health view (`*gascity-health: …`), itself `● live`.
- `M-x gascity-mail-inbox` → `RET` on a row previews the thread
  (`*gascity-mail-thread: thread-…*`, echo "Previewed; still unread (r reads
  it)") → `q` buries it and the inbox remains.
- `M-x gascity-events` → `/` → the events Filter transient
  (`-W -t -a -l -c -q`, `x reset`).
- `M-x gascity-dolt-list` → tabulated header `Database / Commits`, no rows.

## Responsiveness

- **Concurrency:** peak 3 concurrent remote `gc` processes (the
  `gascity-remote-max-inflight` cap), even with all 17 views live. Cap
  honored over TRAMP.
- **Main-loop stalls > 200 ms:** exactly one, 0.201 s during the cockpit's
  first contact (the listed §8.5 TRAMP connection-setup exception).
- **Live stream:** `:state live`, seq advancing (`205076`), looked up under
  the view's directory (`:host "localhost"`). `g` reconnects cleanly.
- **Warm first paint:** every view ≤ 2.2 s except the cockpit (11.7 s settle,
  1.5 s blocking) and Convoys (6.4 s) — both opened while the other 13 views
  were live, i.e. under self-inflicted contention, not in isolation.

## Hangs / retries

None. No `■ gc`, no "Process has died", no un-timeouted evaluation, no
restart or backoff retry observed. Every call completed within its bound.

## Friction

- **F1 — city status is `partial` for the whole pass.** `gc status --json`
  returns `"partial": true` with
  `["sessions: loading session snapshot timed out after 1s",
    "store health: counting retained bead rows: hydrating list fallback: list
    timed out: context deadline exceeded"]`.
  The cockpit "Needs you" row (`▲ store  health: …/ j h health`) and the
  Health view's `Store ◐` line render this **correctly** — the UI is doing
  the right thing. It is a bright-lights / gc store latency condition, not a
  gascity.el defect, so it is **not filed** here (the fix belongs to the
  city's Dolt/store, not this package).
- **F2 — `gc status --json` was ~7.4 h stale (`_cache_age_s ≈ 26701`) on the
  first probe**, then fresh (`0`) after the views refreshed. Cosmetic, not
  filed.
- **F3 — opening a view from a buffer whose `default-directory` is not a city
  prompts "No city … choose a city".** Expected and useful; the realistic
  flow (visit a file in the remote city first) avoids it. Not filed.

## Defects

| ID | Owner | Filed | Evidence |
|---|---|---|---|
| **D1** — Dolt view renders an empty table for a `bd`-owned/proxied city | gascity.el | **yes — `ga-zh6ks`** | `gc dolt health --json` returns `{"skipped":{"reason":"bd-owned-proxied-scope","message":"dolt lifecycle is owned by bd for proxied scopes; nothing to do"}}`; `gascity-dolt-list-refresh` reads only `(alist-get 'databases payload)`, so 0 rows. `gascity-dolt-list` renders a tabulated buffer whose body is empty (only the `Database / Commits` header). bright-lights is `BdStore`/`beads.preflight_gate = "proxied_provider"`, now the common case. The rig dashboard's own Dolt section shows `Dolt  none`, so it degrades gracefully — only the standalone list is blank. |

Everything else is PASS or explicitly not filed above.

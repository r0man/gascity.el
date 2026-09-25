# Dashboard v3 — final QA pass

Date 2026-09-25 · QA agent · gascity.el `main` @ **87612b4** · beads.el
`main` @ **82b86f6** · gc 1.4.2 · Emacs 31.1 `-nw` (v3qa, restarted on
this commit, byte-compiled, views opened by M-x keystrokes; TRAMP with
`-o ForwardX11=no`) · data: `~/workspace/gascity.el-wt/qa/out/finalpass/`.
Cities: `~/emacs-city` (read only), `~/bright-lights`, and both over
`/ssh:localhost:`.

| # | Item | Result |
|---|---|---|
| 1 | Re-sling e2e-demo over TRAMP, no catalog workaround, preview → `s` | **PASS** |
| 2 | Stream kill → header `reconnecting` → `● live` | **PASS** |
| 3 | `gascity-remote-transport 'tramp`: cold remote opens of every view, none stuck at `…` | **PASS for B1** (no view stuck at `…`); **FAIL on responsiveness** in `'tramp` mode, see below |
| 4 | Full-view smoke: both cities, local and ssh; beads-dashboard/show remote | **PASS** |
| 5 | Idle cockpit, process count over 60 s | **PASS** |

## 1. Formula sling over TRAMP — PASS

- The `bright-lights/formulas/e2e-demo.formula.toml` file is unmodified
  (no `[catalog]` block).
- Remote cockpit → `S` → `-f`: the picker now offers city-local formulas
  (`e2e-demo`, `e2e-demo-on`, …). S-1 fixed.
- Set `note` = `qa-v3-final` and `-T mayor`, then `p` Preview: the dry-run
  buffer opens and **the transient stays open with formula, target and
  vars kept**; there is a new `x Reset`. S-2 fixed.
- `s` → "GC sling: ok"; the command returned in 14 ms.
- Store: root `bl-6xq5` (`gc.kind=workflow`, routed to mayor) with steps
  `bl-78fm` "e2e demo latch — qa-v3-final" and `bl-b86q`
  workflow-finalize. No agent session was spawned. All three beads were
  closed afterwards.

## 2. Stream reconnect header — PASS

I killed this Emacs's host-side `gc events --follow` (bright-lights,
remote cockpit), sampling the header every 0.5 s:
`○ live: reconnecting (2s)` → `(1s)` → `○ live: reconnecting` →
`● live` at +5.2 s. Max stall 73 ms. S-3 fixed. Gap-free resume
(`--after SEQ`, 0 missed seq) was verified on 6eb28ee
(`2026-09-25-dashboard-v3-e2e-scenarios.md`).

## 3. `gascity-remote-transport 'tramp` — B1 PASS, responsiveness FAIL

Cold opens: `tramp-cleanup-all-connections` before each view, 10 views ×
2 remote cities. The run in `out/finalpass/tramp3.txt` is clean; two
earlier runs were disturbed by the runs agent's parallel TRAMP matrix,
which caused TRAMP "Couldn't find remote shell prompt" login failures.

- **B1 (lost completions): PASS.** No rendered view had a section stuck
  at `…`.
- **Responsiveness: FAIL against the §8.3 budgets** (these hold in `'ssh`
  mode):
  - Command sync is 650–2280 ms for Agents, Events, Mail, Cities and
    costs. The tracer on Agents shows one tramp-sh connection per async
    read, each `echo $$` handshake ~680 ms, 4.2 s total. This is the
    pre-fix F1 behaviour, now confined to the fallback transport.
  - **One 60.8 s main-loop freeze** (emacs-city Agents, cold). It did not
    reproduce in 3 retries with the TRAMP-wait watchdog armed. Most
    likely the F8 ControlMaster deadlock class, which `'tramp` mode
    re-exposes by design (`qa/f8-root-cause.md`).
  - Two views (emacs-city cockpit and rig dashboard) did not settle within
    60 s: a read process outlived the harness window.
  - One 1151 ms stall (emacs-city Events).

Recommendation: keep `'ssh` the default, and document `'tramp` as a
compatibility fallback without the R9 guarantees.

## 4. Full-view smoke — PASS

`qa/pass-accept.sh` over 9 views (cockpit, Agents, tree, Runs, Events,
Mail, Health, Cities, costs) plus rig dashboards × {bright-lights,
emacs-city} × {local, ssh:localhost}: **43 opens, 0 failures, 0 unsettled**.

| | local | remote |
|---|---|---|
| command sync | 1–61 ms | 2–49 ms |
| max main-loop stall | 4–98 ms | 1–84 ms |
| checks with a gap > 100 ms | 0 | 0 |

beads.el 82b86f6, remote bright-lights:
- `beads-dashboard` cold (TRAMP cleaned): sync **3 ms** (was 1567 ms),
  settle 1.6 s. Warm: 6 ms / 1.6 s.
- SPC fold/unfold of a header: zero TRAMP I/O, count kept.
- RET → `beads-show` in 156 ms, zero TRAMP I/O.

## 5. Idle cockpit — PASS

60 s idle after settling:

| Cockpit | gc processes | max stall |
|---|---|---|
| emacs-city (local) | 1 (the live `gc events --follow`), 0 spawns | 52 ms |
| bright-lights (ssh) | 1 (the live stream), 0 spawns | 58 ms |

## State left behind

- bright-lights: the probe beads `bl-6xq5`, `bl-78fm` and `bl-b86q` are
  closed; the formula file is untouched.
- emacs-city: read only; nothing was changed.
- v3qa: running on 87612b4, `gascity-remote-transport` back to `'ssh`,
  no views open. No QA background processes remain.

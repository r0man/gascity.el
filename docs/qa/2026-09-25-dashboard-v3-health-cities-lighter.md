# dashboard-v3 P4/P5: Health, Cities, costs, mode-line lighter — live pass

Date: 2026-09-25 · branch `v3-health` · gc 1.4.2 · Emacs 31.1 ·
design `plans/dashboard-v3/design.md` §7.10, §7.11, §7.12, §5.2 `j $`.

Harness: `qa/qa.sh` with `QA_SESSION=QA_SERVER=v3-health-qa` (own tmux
session and Emacs server), code byte-compiled into a private cache
(`qa-cache-dir` in the scratchpad). Views opened by keystrokes
(`M-x`, `j h`, `j c`, `j $`, `!`, `F y`, `TAB`, `SPC`, `RET`). Stall
meter = longest main-loop gap while the step ran.

## Local (`~/bright-lights`, `~/emacs-city` read-only)

| Step | Result | Max stall |
|---|---|---|
| `M-x gascity-health` (bright-lights) | all five sections from real reads; live `partial_errors` rendered as `Store ◐` + `◐ store health: …` line; `▲ degraded (no_agents_running)` | 71 ms |
| `!` doctor | header `running…` at once, rest usable; report after ~9 s: `88 passed · 5 warned · 0 failed · ran 0s ago`, 5 `▲` rows, `▸ 88 checks ok`; Versions gains `bd 1.3.0 · dolt 2.3.5` | 5 ms |
| `TAB` ×14 | Supervisor → Versions → Store → Rig stores → rig row → Doctor → 5 check rows → fold → wraps (`Wrapped`) | — |
| `SPC` on fold / check row | `▾ 88 checks ok` + rows; drawer with the check's details | — |
| `RET` on rig row | rig dashboard `*gascity-rig: hello-world@…*` | — |
| `F` → `y` (doctor --fix) | confirm prompt, then async; `87 passed · 6 warned · 0 failed`, echo `Doctor bright-lights --fix: …` | 26 ms |
| `M-x gascity-cities` | 2 rows (`● bright-lights ~/bright-lights/ 1/4 · ▲4 ◐`, `● emacs-city … 1/5 · ▲5 ●`) | 62 ms |
| `M-x gascity-costs` (emacs-city) | gc's text table as-is, header `gc costs  emacs-city  ↻ Ns ago` | 23 ms |
| `gascity-mode-line-mode` + two cockpits | mode line `GC[bl ▲2 · ec ■7▲2]` (= the cockpits' Needs you) ; mouse-1 command opens the cockpit | — |

## Remote (`/ssh:localhost:/home/roman/bright-lights`)

| Step | Result | Max stall |
|---|---|---|
| `M-x gascity-health` | identical layout, title `Health  bright-lights @localhost`, `dolt ok` rig row | 3 ms |
| `!` doctor | `running…` → `87 passed · 6 warned · 0 failed` | 74 ms |
| `M-x gascity-cities` | 4 rows: local ×2 + `/ssh:localhost:~/bright-lights/`, `/ssh:localhost:~/emacs-city/` (host picked up from the store, no config); mode line `Cities 4 · 2 remote` | 73 ms |
| `RET` on the remote row | remote cockpit opens; lighter `GC[bl@localhost ▲1]` | 100 ms |
| `M-x gascity-costs` | remote `gc costs` table | — |
| cockpit `j h` / `j c` / `j $` | health / cities / costs buffers of the remote city | — |

## `gc doctor --fix` on bright-lights — what changed

Snapshot before (file list with mtime/size, `hello-world` git status,
tarball of the city minus dolt data). After `F`: gc reported `fixed 0`.
Content changes: none. Three files were rewritten byte-identical
(mtime only: `.pi/extensions/gc-hooks.js`,
`.gc/agents/bd.dog-1/.pi/extensions/gc-hooks.js`,
`.gc/nudges/state.json`); the rest were the running city's own logs
(`events.jsonl`, runtime traces, `dolt.log`). `~/hello-world`
unchanged. Nothing to restore.

## Findings outside this branch

1. **Remote first contact can wedge Emacs (P1 store/reader).** First
   remote open wedged the QA Emacs at 100 % CPU for >2 min. Backtrace
   (SIGUSR2): `gascity-store--pump` → `gascity-reader--spawn-ssh` →
   `gascity-reader--bounded-executable` → `gascity-remote-find-executable`
   → `executable-find` over TRAMP → `tramp-wait-for-regexp`, inside
   `with-timeout-suspend` — so the `gascity-remote-with-timeout` bound
   is suspended by TRAMP and never fires. Same F8 ControlMaster
   mechanism (`qa/f8-root-cause.md`; `ForwardX11=no` was already set).
   With `tramp-use-connection-share 'suppress` the rest of the pass ran
   clean. The resolution of `gc` on a new host should move off the
   TRAMP channel (e.g. resolve through the ssh pipe) or run with
   connection sharing suppressed.
2. **qa-reload drops top-level keymap additions (harness).**
   `qa-reload` re-evaluates `defvar-keymap` forms in place *after*
   loading each file, which erases keys added by later top-level forms
   (`gascity-thing-define-keys` on `gascity-section-mode-map` and
   `gascity-tabulated-base-map`): after a reload `TAB` is
   `vui-forward` in every view. Re-run those forms after `qa_reload`.

# E2E harness hardening — bounded blocking calls (ga-mict)

Date: 2026-09-16 · Bead: `ga-mict` (context: city bead `ec-abvq`,
MAYOR-NOTES.md) · Result: **PASS**

## Problem

pi's bash tool has no default timeout, so a blocking call in the e2e harness
can freeze a worker for hours. Two real incidents:

1. A batch-emacs elisp diagnostic with a buggy `(while t ...)` loop spun a CPU
   core **17h20m** (2026-09-13..14).
2. An e2e emacs (`server-name gce-e2e`) spun 100% CPU **23h** in a TRAMP/ssh
   retry loop; its emacsclient evals blocked the worker **54min+** (2026-09-15).

There was no in-repo harness: every dogfood pass re-typed raw `tmux
send-keys` / `emacsclient -e` commands, so the discipline (timeouts,
has-session checks) lived nowhere.

## Deliverable

`scripts/e2e-harness.sh` — source it from any dogfood pass
(`. scripts/e2e-harness.sh`). Helpers:

| Helper | Hardening |
| --- | --- |
| `e2e_send_keys` / `e2e_capture` | `tmux has-session` checked **first** (a dead tmux server makes send-keys a silent no-op while the test still blocks); call wrapped in `timeout $E2E_TMUX_TIMEOUT` (15s); fail fast with a clear message if the session is gone |
| `e2e_eval` / `e2e_eval_quiet` | every `emacsclient -e` wrapped in `timeout $E2E_EVAL_TIMEOUT` (60s); a wedged Emacs (TRAMP retry loop, modal prompt) self-terminates instead of hanging the worker |
| `e2e_start_emacs` / `e2e_kill_emacs` | fresh `emacs -nw -Q` + `(server-start)` in a dedicated tmux session; refuses to clobber an existing session |
| `e2e_emacs_ready` | bounded readiness poll probing `(emacs-pid)` (`server-name` is void under `-Q`; server.el is not preloaded) |
| `e2e_wait_for ELISP [TOTAL] [POLL]` | polling with a total deadline; every probe individually bounded |
| `e2e_emacs_batch` | batch emacs for diagnostics that do not need a running server (the preferred form); `timeout $E2E_BATCH_TIMEOUT` (120s) |

Tunables via environment: `E2E_EMACS_START_TIMEOUT` (120s),
`E2E_EVAL_TIMEOUT` (60s), `E2E_BATCH_TIMEOUT` (120s), `E2E_TMUX_TIMEOUT`
(15s), `E2E_SESSION`/`E2E_SERVER_NAME` (`gce-e2e`).

Coding rules encoded in the header comment: never call emacs/emacsclient or a
foreground tmux attach without `timeout(1)`; never assume a tmux session
exists; prefer batch emacs; **any elisp loop in a diagnostic must carry a
hard iteration cap** (capped-`while` idiom in the `e2e_emacs_batch` docstring)
— this is the guard against incident 1 recurring.

## Acceptance evidence (live, this host)

1. **Send-keys to a nonexistent session fails fast.**
   `e2e_send_keys gce-e2e-acc 'M-x'` →
   `e2e: tmux session 'gce-e2e-acc' does not exist ... refusing to send
   keys / capture into a no-op target`, exit 1 in **3ms**.
2. **A deliberately blocked emacsclient call self-terminates within its
   timeout.** Real daemon (`emacs --daemon=gce-e2e-acc`) occupied by a
   background `emacsclient --eval '(sleep-for 120)'` so subsequent evals
   queue; `e2e_eval '(+ 1 1)'` with `E2E_EVAL_TIMEOUT=5` → exit **124**
   after **exactly 5s**. (During the first pass a leftover daemon was killed
   with `pkill -f`; nothing kept running.)
3. **Full interactive loop through the harness.** `e2e_start_emacs` →
   `e2e_emacs_ready` (rc=0 after 3s) → `e2e_eval '(emacs-version)'` →
   `e2e_send-keys M-x` → `e2e_capture` shows the `M-x` prompt in the pane →
   `e2e_kill_emacs`; no leftover emacs processes.

## Notes

- Interactive emacs in this environment is PGTK; `--daemon` prints a
  Wayland display-disconnect warning but works. The harness uses a tmux-hosted
  interactive emacs with `(server-start)` instead of a daemon, matching the
  AGENTS.md protocol.
- Nothing in `lisp/` changed; `scripts/gate.sh` still run before commit.

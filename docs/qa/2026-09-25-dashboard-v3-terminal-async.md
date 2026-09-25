# dashboard-v3: tmux attach and status mirror without TRAMP — live pass

Date: 2026-09-25 · branch `v3-terminal` · audit finding 3
(`docs/qa/2026-09-25-dashboard-v3-8.4-audit.md`).

Harness: `qa/qa.sh` with `QA_SESSION=QA_SERVER=v3-term-qa`, private elc
cache, `TAB` keys re-applied after `qa_reload` (harness artifact). City:
`/ssh:localhost:/home/roman/bright-lights`, agent `mayor` (tmux socket
`bright-lights`). Terminal backend: the built-in `term` (no vterm/eat on
the QA load path). Counters: advice on `tramp-file-name-handler`
(operations seen) and on `process-file` (calls); stall meter = longest
main-loop gap.

| Step | Result |
|---|---|
| Agents view (remote), `t` on the mayor row, warm Emacs | command returns in 1 ms; pre-step + terminal open 7 ms; max stall 5 ms; `process-file` 0; TRAMP saw only `expand-file-name`, `file-remote-p`, `file-name-as-directory` (pure) |
| same, first attach in a fresh Emacs | max stall 234 ms, all inside the synchronous command (242 ms): the one-time load of the terminal backend library (`term` not loaded before, loaded after) while deciding the TERM; the async remainder 7 ms |
| attached, 16 s (three status ticks) | mode line `[mayor]  1:pi*`; host shows `status off` for the session; `process-file` 0; TRAMP only pure name ops (redisplay of the remote buffers); max stall 48 ms |
| detach (kill the attach buffer) | max stall 4 ms; `process-file` 0; host's session-level `status` override removed; mayor session still running |

Before (main 4c9d9f9): the attach ran `tmux has-session`, the TERM probe
(`infocmp` + file checks) and `set-option status off` through
`process-file` over TRAMP, pinned the buffer after a `file-directory-p`
over TRAMP, and the status mirror's timer ran two `process-file` tmux
calls every 5 s (sync TRAMP inside a timer).

Static check: `gascity-test-audit-callback-file-io-reviewed` finds no
terminal pair (the runner uses the pure `gascity-remote-prefix`); the
audit's D9 guard runs `t` locally and remotely with no exemption.

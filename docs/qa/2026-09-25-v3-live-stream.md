# dashboard-v3 P3 — live event stream, live check (2026-09-25)

Branch `v3-live`. Script: `scripts/v3-live-e2e.el` (batch Emacs,
`gascity-live-in-batch` t, debounce 0.5 s), run under `timeout 400`
against bright-lights, locally and as `/ssh:localhost:/home/roman/bright-lights/`.
The remote stream got a private ssh ControlPath
(`$XDG_RUNTIME_DIR/v3live-%C`, spliced in front of gascity's own
`gascity-ssh-%C`) so `ssh -O exit` could not touch the master that other
Emacsen (the QA agent's) share for their reads.  Re-run after rebasing
on the P1 store: the remote stream is now built with
`gascity-remote-ssh-pipe-argv … :resolve nil` — the run used no TRAMP
connection at all.

| Check | Local | Remote (ssh pipe) |
|---|---|---|
| attach → header | `● live` | `● live` |
| first event received (order/bead churn), view invalidated | yes | yes |
| `pkill` the host `gc events --follow` | `reconnecting`, resumed `--after`, seqs contiguous | `reconnecting (gc exited 143)`, resumed, contiguous |
| `ssh -O exit` on the stream's master | — | `○ offline @localhost` (ssh exit 255), recovered in the 2 s retry, contiguous |
| kill the view buffer | no process left, stream table empty | same; no `gc events --follow` left on the host 3 s later |

Cockpit (`gascity-dashboard` on ~/bright-lights, batch): header
`bright-lights  ● live`; within seconds `bead.created`, `order.fired`,
`order.completed` batches reached `gascity-store-invalidate-event` and
the cockpit's store entries were re-read (18 reads started); killing
the cockpit stopped the stream (only the store's in-flight `gc` reads
were still finishing).

No bright-lights state was mutated (the city's own order churn produced
the events; no `gc mail send` needed).

Findings fixed during the pass:
- The default `:stderr` pipe's sentinel wrote "Process … stderr
  finished" into the stderr buffer, which then read as the exit reason.
  The stream now owns a quiet stderr pipe.
- A remote `gc events --follow` outlived its stopped stream until its
  next write (no pty → no SIGHUP), and a killed gc was indistinguishable
  from a dropped link (ssh 255 either way).  The host-side wrapper
  (`gascity-live--exit-reporter`) now kills gc when the session's stdin
  hits EOF and reports gc's exit status on stderr.

Not exercised live: `○ live: supervisor down` (would need stopping the
bright-lights supervisor; covered by ERT with a fake gc that fails like
`gc events --api <dead>`), and the polling fallback for non-ssh methods
(ERT only).

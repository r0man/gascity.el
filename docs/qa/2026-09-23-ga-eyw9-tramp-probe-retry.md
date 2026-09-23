# ga-eyw9 QA report — TRAMP "no such directory" false negatives

**Bead:** ga-eyw9 · 2026-09-23 · verified against `/ssh:localhost:/home/roman/bright-lights`

## What shipped

1. **Probe retry + cache flush** (`gascity-reader.el`,
   `gascity-remote-flush-file-cache` in `gascity-remote.el`): the async
   read path's up-front `file-directory-p` probe no longer treats one
   clean negative as ground truth. On an "absent" verdict the reader
   flushes TRAMP's cached file properties for the path and re-probes
   once, still bounded by `gascity-remote-sync-timeout`
   (`gascity-remote-with-timeout`). The "no such directory" errback
   fires only when both probes agree; a reversed retry proceeds with
   the spawn and logs the reversal (`gascity--log`).
2. **Retry may reconnect**: the retry deliberately declines to
   (re)bind `non-essential`, so a manual `g` can re-establish a
   dropped TRAMP connection while a timer tick — which binds
   `non-essential` itself — keeps its no-reconnect guarantee.
3. **Auto-refresh error hygiene** (`gascity-tabulated.el`, session
   list): one visible error per distinct failure message per episode,
   a `[stale: N failed refreshes]` mode-line marker
   (`gascity-tabulated--stale-errors`), an exponential tick backoff
   (1, 2, 4 … capped at six ticks = interval × 6), silent self-heal on
   the next successful refresh, and full reset on a manual `g`.
4. **Regression tests** (`lisp/test/gascity-test.el`): retry-reversal,
   absence-confirmed-twice, local-no-probe, absent-errbacks-no-spawn,
   reversed-probe-spawns, flush no-op locally + works on the mock
   remote, dedupe/backoff state machine, tick backoff consumption,
   manual-`g` reset, wiring of the hygiene handlers through
   `gascity-tabulated--refresh-async` (new optional ERROR-FN /
   SUCCESS-FN), and the stale mode-line marker.

## Live verification (bright-lights over TRAMP)

Scripted, bounded acceptance: `scripts/ga-eyw9-acceptance.el`, wired as
`gascity-test-remote-ga-eyw9-acceptance-live` (skips itself when the
city is unreachable). Phases:

1. Open the remote session list, wait for a live read. ✔
2. Kill the pooled TRAMP connection (`*tramp/ssh localhost*`)
   mid-session. ✔
3. Eight auto-refresh ticks: **exactly one** visible error line
   (`gascity: gc session list --json failed: no such directory: …`),
   where the observed incident produced seven over ~35s. ✔
4. Manual `g`: the connection re-establishes, the read succeeds, the
   stale marker clears, no further error line. ✔ — this check caught a
   real defect during development (the retry initially inherited the
   probe's `non-essential t`, so a manual `g` could never reconnect;
   fixed by letting the retry honor the caller's binding).

Result: `ACCEPTANCE PASS` (run: 2026-09-23 17:45, eldev test).

## Gate

- `scripts/gate.sh` → PASS: `eldev compile --warnings-as-errors` clean,
  348/348 ERT tests green (includes the live acceptance test when
  bright-lights is reachable).
- The ga-yam7 scaffolding the probe composes with
  (`gascity-remote-sync-timeout`, `gascity-remote-with-timeout`,
  bounded `process-file`/tmux probes) is landed in the same commit —
  ga-yam7's lease had expired; the hunks are prerequisites of this
  probe and compile/tests cover them.

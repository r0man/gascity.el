---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-hg6u
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-30zs
      hash: bead:ga-30zs
      ids:
        - ga-7pq7
    - path: plans/dashboard-v2/implementation-plan.md
      hash: sha256:1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f
    - path: plans/dashboard-v2/requirements.md
      hash: sha256:912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07
    - path: lisp/gascity-reader.el
      hash: sha256:43127076ff509a5258738e1972b16cc841b790070e502e3e27e83442dfda4860
    - path: lisp/gascity-dashboard.el
      hash: sha256:1bed5e1875d52408b53feac169bec7ab5d32fb6dc3e730be65064efb0a025beb
    - path: lisp/test/gascity-test.el
      hash: sha256:fd3bfacdc0367955aded2e6bbbfc4cf76c591e5c2a8c0dc06e9c64291016b8bb
  coverage:
    - id: ga-7pq7
      status: covered
---

# Implementation Summary: S3 — Activity feed from `gc events` JSONL (source anchor ga-30zs)

## Summary

Implemented S3 of the approved Dashboard v2 plan
(plans/dashboard-v2/implementation-plan.md §S3) for source anchor bead
ga-30zs, in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-30zs`, committed as
`dffc4ae` ("feat(dashboard): Activity feed from gc events JSONL
(ga-30zs)") on the worktree's detached HEAD.  Gate: `scripts/gate.sh`
PASS (byte-compile with `--warnings-as-errors` clean + 389/389 ERT
tests, 10 of them new).

The Activity section of the city dashboard now renders a real feed of
recent `gc events` output read as JSON Lines, replacing the documented
gap pointer (ga-69kj).  All reads stay on the CLI data plane through
the existing per-section async plumbing; no HTTP, no `.gc/events.jsonl`
reads.

## Intended Behavior

- **Reader JSONL mode (`lisp/gascity-reader.el`).**
  `gascity-reader-read-async` gained `&key lines`: with `:lines t` the
  output is decoded as JSON Lines — accumulated process output is
  split on newlines, each non-empty line decoded independently, and
  CALLBACK receives a cons `(GOOD-LINES . BAD-COUNT)`.  A malformed
  line is a per-line decode-error count in the payload, never a
  whole-feed failure (`gascity-reader--parse-json-lines`, pure and
  unit-tested; empty lines and a trailing newline are ignored).  The
  `--json` flag is NOT appended in lines mode (the `gc events` leaf
  always emits JSON Lines).  Every other reader guarantee is kept:
  remote spawn handling, stderr separation, the up-front directory
  probe, envelope-aware failure messages.
- **Async section load.**  `gascity-dashboard-app` gained an
  independent `gascity-reader-read-async '("events" "--since" "2h")`
  read with `:lines t`, wired through the same
  `gascity-dashboard--effective-load` stale-while-revalidate rule as
  every other section (a pending load never unmounts the feed; a
  failing refresh keeps the last good rows and surfaces the error dimly
  with a retry hint).
- **Cap.**  `defcustom gascity-dashboard-events-limit` (default 500)
  caps the feed to the MOST RECENT events (the payload tail — `gc
  events` emits ascending sequence numbers); events dropped by the cap
  render a trailing dim "N older events hidden" line.
- **Filter.**  New root-component state `event-types-excluded` (default
  `("order.fired" "order.completed" "bead.updated")`) is applied before
  render; it is lifted to the root component, so it survives a refresh
  like `collapsed`/`bead-rig`.  The `/` transient
  (`gascity-dashboard-filter-dispatch`) gained an events submenu
  (`gascity-dashboard-events-filter-dispatch`): `t` toggles the
  default-chatty types as a set (`gascity-dashboard--events-toggle-chatty`
  — any member excluded removes all, none adds the full set, other
  exclusions preserved), `c` clears the exclusion entirely.
- **Rendering.**  The Activity section is now a full collapsible
  vui section (collapse state lifted to the root, `N`/`P` navigation):
  rows of ts (HH:MM:SS out of the RFC3339 payload value), type,
  subject, and the first line of `payload.title` (preferred) /
  `payload.summary` when present; an event with `ok` nil renders in the
  failed face.  A non-zero malformed-line count renders a dim inline
  "N malformed event lines skipped" line; a read failure renders the
  standard dim error line with the retry hint.  The header count is the
  filtered-and-capped row count, computed from the same processed view
  as the rows.
- **No synchronous gc** anywhere on the new paths; the events read goes
  through the same remote-aware reader plumbing as the other sections
  (TRAMP parity by construction — nothing buffer-local or path-based
  was added).

## Changed Files

- `lisp/gascity-reader.el` — `gascity-reader--parse-json-lines` plus
  the `:lines` mode on `gascity-reader-read-async` (JSONL branch of the
  sentinel's decode; no `--json` appending in lines mode).
- `lisp/gascity-dashboard.el` — the events limit defcustom, chatty
  default, pure selectors (`--events-visible`, `--events-cap`,
  `--events-view`, `--event-ts`, `--event-summary`,
  `--events-toggle-chatty`), the Activity section (rows + dim cap/error
  lines) replacing `gascity-status--events-pointer-vnode`, the events
  async read, the lifted `event-types-excluded` state with its toggle
  and clear commands, and the `/` transient's events submenu.
- `lisp/test/gascity-test.el` — new ERT coverage and widened stub
  signatures (the JSONL read carries a 4th `:lines` argument, so every
  dashboard async stub accepts `&rest`); the section-render assertion
  moved from the gap pointer to the real feed header.

All three files' sha256 digests are recorded in the front-matter
`trace.upstream[]` as committed at `dffc4ae`.

## Verification

- First verification command: `eldev compile --warnings-as-errors`
  (from the worktree root) — observed PASS (whole package byte-compiled
  clean; `--warnings-as-errors` also proves the cross-file wiring of
  `gascity-reader-read-async`'s new keyword is arity-consistent).
- Final proof command: `scripts/gate.sh` — observed PASS: "gate: PASS
  (compile clean + tests green)", 389/389 ERT tests (10 new: JSONL
  good/bad split + chatter tolerance, chatty-type exclusion default,
  filter toggle as a set, N-cap trimming, ts formatting, summary
  extraction, feed render with cap/malformed lines, events failure
  inline, filter state lifted across refresh).
- Live spot check of the payload shape against the emacs-city city
  (`gc events --since 2h`): each line carries `actor`, `payload`,
  `seq`, `subject`, `ts`, `type`, `ok` — the row/column projection
  above matches; chatty types (`order.fired`, `bead.updated`) dominate
  the raw feed, confirming the default exclusion is meaningful.

## Remaining Risks

- The events window is hardcoded `--since 2h` (per plan S3); a
  follow-up could make it configurable if feeds feel sparse.
- `--events-view` treats any non-cons payload as an empty feed; real
  gc always delivers the `(GOOD . BAD)` cons, so this only affects
  degenerate payloads.
- TRAMP parity of the new read was verified structurally (same reader
  plumbing as the other sections, `:file-handler t`, no sync gc on
  render paths); the live `/ssh:localhost:/home/roman/bright-lights`
  pass is S5's acceptance gate and has not run in this step.

| ID | Status |
| --- | --- |
| ga-7pq7 | covered |

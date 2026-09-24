# City dashboard — live TRAMP e2e report (ga-d63b, WI-1)

Date: 2026-09-24 · Implementer: gascity.el/gc.implementation-worker (session
ec-51a1) · Harness: `scripts/e2e-harness.sh` (all emacs/emacsclient/tmux calls
bounded). Requirement: AC-6 / REQ-011 — live verification against
`~/bright-lights` in local and TRAMP access modes, including one
intentionally-failing-section check over TRAMP.

## Setup

Fresh `emacs -Q` inside tmux (`gce-e2e` session, `timeout(1)` bounds from the
harness), `EMACSLOADPATH` carrying the worktree `lisp/` plus the beads.el
checkout and its bundled vui/sesman/transient. `(require 'gascity)` loads the
new `gascity-dashboard` module (required by `gascity.el` after
`gascity-rig.el`).

## Sections implemented (REQ-001…REQ-009)

All eight sections of the plan's Step 3, each backed by its own
independent `gascity-reader-read-async` read:

| Section | Read | Notes |
| --- | --- | --- |
| Cockpit | `gc status` | reuses `gascity-status--header-vnode`; API URL renders as a dim `(api —)` placeholder — gc exposes no API URL in any `--json` payload yet (same gap the status board documents) |
| Work in flight | `gc bd list --status in_progress` + `gc session list` | port of the SPA's `work-in-flight.ts` (`gascity-dashboard--parse-assignee`, `--work-in-flight`) |
| Needs you | `gc status` agents + session join | port of the SPA's `needsYou.ts` (`gascity-dashboard--needs-you`); roster highlight reads the same selector output |
| Agents | `gc status` | needs-you rows marked `!reason` |
| Sessions | `gc session list` | live rows + named-session derivation + census line |
| Beads | `gc bd ready`, `gc bd list --status in_progress` / `--status blocked`, `gc convoy list` | `/` filter transient (rig prefix, client-side) |
| Activity | — | documented events pointer only (ga-69kj); no `.gc/events.jsonl` access |
| Rigs | `gc status` rigs | `RET` opens the rig dashboard |

## Reuse vs new

Reused: `gascity-status--header-vnode`, `--sessions-label`,
`--named-session-row`, `--events-pointer-vnode`, `--error-vnode`,
`gascity-status--session-map(-rows)`, `gascity-status--agent`,
`gascity-domain-named-sessions-from-sessions`, `gascity-agent-from-session`,
`gascity-resolve-tmux-socket` (`no-probe`), `gascity-view-get-buffer-create`,
`gascity-section-beads`, `gascity-section-refresh-instance`, the shared
`gascity-section-mode` infrastructure (N/P, q bury, semantic cursor
preservation), and the beads.el delegation (`gascity-bead-show`, §4.3
store scoping). New: the two pure selectors, the section wrapper
(`--effective-load` / `--section-body`), the mode/component, and the
`/` filter transient.

## Verification results

All runs through the harness bounds (start 120s, eval 60s, tmux 15s).

1. **Local mode** (`/home/roman/bright-lights`): dashboard mounts as
   `*gascity-dashboard@/home/roman/bright-lights/*`; all sections render with
   live data — Work in flight (0), Needs you (0), Agents (4), Sessions (2)
   with the mayor + core.control-dispatcher named sessions, Beads
   Ready (21)/In progress (0)/Blocked (0)/Convoys (7), activity pointer, rigs
   (hello-world, prefix hw).
2. **TRAMP mode** (`/ssh:localhost:/home/roman/bright-lights`): identical
   rendering from remote async reads — same counts, host-qualified buffer
   name `*gascity-dashboard@/ssh:localhost:/home/roman/bright-lights/*`
   (pane capture archived at `/tmp/ga-d63b-e2e/tramp-pane.txt`).
3. **Intentionally-failing section over TRAMP** (AC-6): the convoy read was
   parked and rejected (`boom-over-tramp`) after a successful first load —
   the Convoys group keeps its stale rows AND renders
   `gc error: boom-over-tramp (showing last good data)` dimly with
   `press g to retry`, while every other section (cockpit, agents, sessions,
   ready beads, rigs) keeps rendering from its own payload. A dataless
   failing section renders `gc error: <msg>` + retry hint (covered by
   `gascity-test-dashboard-section-failure-isolated`).
4. **`g` refresh preserves point**: point parked on the
   `core.control-dispatcher` agent row; after refresh the semantic line id
   (`(agent . "core.control-dispatcher")`) is restored.
5. **Collapse**: `RET` on the Agents header toggles `▼`→`▶` and back; state
   lifted to the root component (survives refresh, pinned by ERT).
6. **`/` filter**: setting the rig filter to `hello-world` narrows the bead
   groups and updates the header to `Beads (/hello-world)`; clearing restores
   `/all`.
7. **`N` section jump**: from the top, `N` lands on the Work in flight header.
8. **Gate**: `scripts/gate.sh` PASS (eldev compile `--warnings-as-errors` +
   377 ERT tests, 0 unexpected — includes 15 new dashboard tests: the
   selector tables with the SPA tricky cases `polecat-gc-335825`,
   `scix-worker-gc-335812`, bare ids, role-without-handle; the work-in-flight
   join; needs-you precedence + count parity; failing-section rendering;
   pending-nil-not-unmount; stale-refresh-error-inline; buffer keying; wiring).

## Known gaps / follow-up candidates

- **Awaiting-input has no live source**: gc exposes no pending-interaction
  surface in JSON, so `awaiting-input` rows (and `errored`/`rate-limited`
  agent states) only fire with data the web SPA gets from the supervisor
  API. The stalled reason works live (running-with-no-session via the
  session join). Follow-up bead candidate: `gc` pending-interaction read.
- **API URL**: still absent from every `gc --json` payload; the cockpit
  renders the documented `(api —)` placeholder (same gap as the status
  board's `(mode —)`).
- **Work-in-flight join in this city**: live assignees here embed 2-letter
  session prefixes (`ec-…`), which the SPA-faithful parser (prefix
  `gc`/`td`/`th`/4-letter city code) deliberately does not admit — beads
  degrade to unjoined rows. Widening the gate to 2-letter city codes would
  be a gc-side/information-model decision, tracked as a follow-up candidate,
  not silently patched here.
- Mail operator-inbox UI, transcript rendering, screenshots: deferred per
  the plan's Non-Goals.

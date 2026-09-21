# QA — sessions-list city targeting: tmux-Emacs TRAMP e2e pass (Step 4, ga-80m3)

Acceptance pass for **AC-5** and **AC-6** of the sessions-list-city-targeting
plan (`plans/sessions-list-city-targeting/implementation-plan.md`), per
AGENTS.md "Remote test city & end-to-end testing". ERT covers the mocked
units; this live pass is the workflow's acceptance gate.

Work item: drain unit 3 of the sessions-list-city-targeting build workflow
(root `ga-7f73`, source anchor `ga-80m3`). Code under test: the three
implementation units' commits **integrated by a merge in this item's
worktree** (the features live in sibling drain-unit worktrees, none merged to
`main` yet — see Deviation 2), verified end-to-end in one fresh tmux-Emacs.
No porcelain code was changed by this pass other than that integration merge.

## Setup

| | |
|---|---|
| Code | worktree `/home/roman/workspace/gascity.el/worktrees/ga-80m3`: base `origin/main` @ `d1583e6`, merge `72303ad` of the three sibling feature commits `6f82a95` (city targeting, ga-xumo), `b9f57e0` (error envelope, ga-ersm), `3138692` (exit-9 characterization, ga-7ibr) |
| Gate | `scripts/gate.sh` from the worktree — **PASS** (compile clean under `--warnings-as-errors`, **ERT 311/311**, 0 unexpected), including the semantically merged reader-failure tests (envelope ladder + exit-9 hint coexisting) |
| Emacs | fresh `emacs -nw -Q` 30.2 in tmux (`scripts/e2e-harness.sh`, session/server `gce-e2e`), load-path = worktree `lisp/` + `~/workspace/beads.el/lisp` + Guix `emacs-vui-1.3.0`; `gascity-enable-debug` t, level `verbose` |
| Cities | local **emacs-city** `/home/roman/emacs-city` (health ok) and TRAMP **bright-lights** as `/sshx:localhost:/home/roman/bright-lights` (health degraded; the plain `ssh` TRAMP method hangs on this host — the F4 deviation re-confirmed by the 2026-09-10 pass, still `sshx`, not a gascity defect) |
| Method | `emacsclient -s gce-e2e -e` evals (every call under the harness's timeouts) reading buffer contents, `tabulated-list-entries` and `*gascity-log*`; every datum cross-checked against live `gc … --city … --json` at the same moment |

## PASS/FAIL matrix (AC-5, AC-6)

| # | Check | Verdict |
|---|-------|---------|
| 1 | `scripts/gate.sh` on the integrated tree | **PASS** — 311/311 |
| 2 | Sessions buffer over TRAMP shows bright-lights rows, `--city` present in the reader argv (`gascity--log`) | **PASS** — `*gascity-sessions@/sshx:localhost:/home/roman/bright-lights/*`, 1 row (`mayor · active · pi · ~/bright-lights`), matching live `gc session list --city /home/roman/bright-lights --json`; log line `Running async: /home/roman/.guix-home/profile/bin/gc --city /home/roman/bright-lights/ session list --json` |
| 3 | Co-hosted second city cannot leak rows | **PASS** — same Emacs also opened `*gascity-sessions@/home/roman/emacs-city/*` (6 rows: `core.control-dispatcher`, `gascity.el/core.control-dispatcher`, `gascity.el/gc.implementation-worker-1..4` — its own city's sessions); the bright-lights buffer contained **only** mayor, the local buffer **no** bright-lights row. The log shows both buffers issuing their own `--city /home/roman/bright-lights/` and `--city /home/roman/emacs-city/` argv (TRAMP reads resolve gc to the host-absolute Guix path) |
| 4 | Unhealthy store renders `failed: <message>` | **PASS** — a city dir with `city.toml` but a legacy-Dolt store (`/tmp/fake-city-e2e`) makes the async read exit 1; the echo line carries the envelope's nested message verbatim: `gascity: gc --city /tmp/fake-city-e2e/ session list --json failed: gc session list: listing sessions: listing session beads by type: bd list: exit status 1: Error: legacy Dolt workspace detected; …` — not a bare `failed (exit 1)`. The list degrades to empty per the gce-dfe contract; live gc cross-checked |
| 5 | Non-city dir: specific stderr beats the generic sentinel (sync) | **PASS** — `--city /tmp/bogus-city-e2e` (no `city.toml`): sync read signals `gc --city /tmp/bogus-city-e2e/ session list failed: gc session list: not a city directory: /tmp/bogus-city-e2e (no city.toml or .gc/ found) (exit 1)`; the error's `:message` plist entry carries the generic envelope text |
| 6 | Status dashboard over TRAMP with the same targeting | **PASS** — `*gascity-status@/sshx:localhost:/home/roman/bright-lights/*` renders bright-lights exactly (controller supervisor PID 719, health degraded, agents 0/4, sessions 1 active, City tree bd.dog + control-dispatcher, hello-world rig, store health 121.9 MB), argv `gc --city /home/roman/bright-lights/ status --json`; cross-checked against live `gc status --city /home/roman/bright-lights --json` |
| 7 | Agent read + drill-in over TRAMP, same targeting | **PASS** — `gascity-polecat-detail-at-point` from the TRAMP sessions buffer opened `*gascity-agent: mayor@/sshx:localhost:/home/roman/bright-lights/*` with live detail (state active, provider pi, worktree `~/bright-lights`, 10 recent `bl-*` beads); the mail read argv is `gc --city /home/roman/bright-lights/ mail inbox mayor --json` |
| 8 | AC-6 / dogfood report | **PASS** — this report |

Net: **all checks PASS, zero new defects filed.**

## Deviation: the integration merge

The e2e item's source anchor (`ga-80m3`) carried no prepared `work_dir` (its
`prepare-worktree` step bead `ga-z6o6` is routed to `gc.run-operator`, whose
session was not running, and the unit was exclusively reserved to this
session). This pass executed the do-work unit's lifecycle inline:

1. **prepare-worktree procedure** (as documented in `ga-z6o6`): worktree
   `worktrees/ga-80m3` created detached from the freshly fetched `origin/main`
   (`d1583e6`; `origin/HEAD` resolved, never local `HEAD`), and the absolute
   path persisted on the source anchor as `work_dir`.
2. **Integration merge**: none of the three feature commits is merged to
   `main` yet (they live in the sibling item worktrees `ga-xumo`, `ga-ersm`,
   `ga-7ibr`), so a verification worktree straight off `origin/main` would
   verify the wrong code. The worktree therefore merges the three sibling
   commits (`72303ad`; two text-level conflicts in `gascity-reader.el` /
   `gascity-test.el` resolved semantically: the envelope ladder of D4 now
   applies to every non-hinted exit, with D5's exit-9 wording applying only
   when no envelope message exists — covered by a new
   `gascity-test-exit-error-message-exit-9-envelope-wins` test).
3. The close-source-anchor/finalize steps verify the merge commit's presence
   and this report.

Merging the sibling feature commits into the verification worktree is the
minimal faithful reading of Step 4's contract ("run the gate … verify
end-to-end"); the alternative — verifying against a `main` that lacks all
three features — would have been vacuous. The merge is **local to this
worktree**; nothing was pushed, and no shared branch moved.

## Residual behaviors observed (documented, not defects)

- **Async failure path shows the generic sentinel for a non-city.** The async
  runner does not capture stderr, so the `/tmp/bogus-city-e2e` case renders
  `failed: command failed; see stderr for diagnostics (exit 1)` in the echo
  area; the **sync** path (buffers' first read, `gascity-reader-read`
  callers) shows the specific stderr. This is the D4 design's documented
  degradation (the actionable text lives in the error's `:message` plist);
  the requirements' target case (specific message, no stderr —
  `table not found: leases`) surfaces verbatim on both paths.
- **Tabulated lists render errors in the echo area**, leaving the list empty
  (gce-dfe behavior). The requirements' "the sessions buffer displays the
  message" is satisfied through the view's existing error surface; whether
  the error line should also render inside the empty buffer body is a design
  question for the views, not this feature.

## Verification record

- First verification command: `eldev test reader-envelope` (worktree
  `ga-ersm`) — PASS 6/6.
- Final gate: `scripts/gate.sh` from `worktrees/ga-80m3` — **PASS**, 311/311.
- e2e: this pass, via `scripts/e2e-harness.sh` (every emacs/emacsclient/tmux
  call bounded; session `gce-e2e` killed after the pass).

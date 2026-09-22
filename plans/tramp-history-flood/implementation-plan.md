---
schema: gc.build.plan.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: plan
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
    - path: beads/ga-llhb
      hash: bead:ga-llhb
      ids:
        - ga-llhb
  coverage:
    - id: ga-llhb
      status: covered
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
---

# Implementation Plan: Reduce TRAMP connection churn and neutralize host-side history pollution

### Trace Coverage

| ID      | Status  |
| ------- | ------- |
| ga-llhb | covered |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |

## Summary

The user's `~/.bash_history` is flooded with TRAMP's ssh login lines (474 of 500
lines are `exec env TERM='dumb' INSIDE_EMACS='ghostel,tramp:…' … /bin/sh -i`),
one per connection, plus `~/.tramp_history` holds 655 KB of inner-shell bloat.
gascity.el does not write the history, but its remote views may drive the
*volume*: every auto-refresh tick issues an async `gc … --json` read, and the
asynchronous read path (`gascity-reader-read-async`, `lisp/gascity-reader.el`)
may open a fresh ssh login per tick instead of reusing TRAMP's pooled
connection.

The implementation plan is:

1. **Diagnose first (REQ-001, REQ-006).** Measure, with a reproducible count of
   ssh login lines (or sshd log entries), whether N consecutive async remote
   reads against `/ssh:localhost:/home/roman/bright-lights` open a new ssh
   process per read or reuse the pooled one, and determine which TRAMP handler
   (`tramp-sh` channel vs `tramp-direct-async-process` direct-async login
   process) is active for gascity.el's async reads. In the same pass, attribute
   the stray non-TRAMP `cd emacs-city/` history line as far as the evidence
   allows.
2. **Fix or document pooling (REQ-002).** If the diagnosis shows async reads
   bypass pooling, confine the change to gascity.el's remote/read setup
   (`gascity-remote.el`, `gascity-reader.el`) so repeated async reads reuse the
   connection; if pooling is already in effect, record the conclusion as a code
   comment/rig-doc note instead of changing code.
3. **Neutralize the inner-shell history in code (REQ-004).** Recommend — and,
   per this plan's approval, implement — a connection-local
   `tramp-remote-process-environment` override setting `HISTFILE=/dev/null` for
   gascity.el's remote buffers, plus documentation of a user-run truncation of
   the existing 655 KB `~/.tramp_history`.
4. **Ship the host-side recipe as documentation only (REQ-003).** A copy-paste
   `~/.bashrc` guard that stops sshd-spawned login shells from recording
   history goes into the rig docs; the workflow never edits the user's
   dotfiles.
5. **Verify (REQ-005, AC-2, AC-5).** A repeatable measurement (ERT where
   automation is practical, documented manual procedure otherwise) proves
   N ≥ 10 consecutive async reads produce at most 2 new ssh connections, and
   `scripts/gate.sh` stays green.

## Current System

- **Data plane.** `gascity-reader.el` is the only module that runs `gc`.
  `gascity-reader-read` is the sync `process-file` call site;
  `gascity-reader-read-async` is the `make-process` variant backing
  `vui-use-async`, which drives the status dashboard, rig dashboards, and
  session/polecat detail — including their auto-refresh timers.
- **Remote handlers.** On a TRAMP directory, async `make-process` dispatches
  through one of two handlers (both discussed in `gascity-reader.el`'s
  commentary):
  - `tramp-sh` shares the single pooled ssh connection channel with every
    other `process-file` user of the connection.
  - `tramp-direct-async-process` (connection-local) spawns a **fresh local
    ssh login process per `make-process` call**. gascity.el already has code
    that is aware of both handlers (stderr wrapping, executable resolution via
    `gascity-remote-find-executable`), which strongly suggests direct-async may
    be the active handler and therefore the churn source — but this is not yet
    measured (that is REQ-001's job).
- **Remote setup.** `gascity-remote.el` already installs connection-local
  machinery: `gascity-remote-search-path` (Guix profile probing, cached per
  connection), `gascity-remote-path-assignment` (PATH prepending for gc's
  children), executable resolution caching keyed by `(REMOTE-PREFIX . NAME)`.
  There is currently **no** `tramp-remote-process-environment` override, so
  TRAMP's default applies: the inner shell runs with `HISTFILE=~/.tramp_history`
  (hence the 655 KB bloat), and the sshd-spawned login shell still appends the
  login command to `~/.bash_history`.
- **Host-side behavior (verified outside Emacs).** Even plain
  `ssh localhost true` grows `~/.bash_history`, so the login-line recording is
  the sshd-spawned login shell sourcing the user's `~/.bashrc` (whose line 69
  sets a multi-window `PROMPT_COMMAND` history trick) — independent of
  gascity.el and fixable only by a user-applied guard (REQ-003).
- **Unexplained signal.** A bare `cd emacs-city/` line appeared at 22:27 and is
  not yet attributed (REQ-006): candidates are pi agent bash subshells and the
  sshd login shell sourcing `~/.bashrc`.
- **Quality gate.** `scripts/gate.sh` (byte-compile with `--warnings-as-errors`
  + the whole ERT suite in `lisp/test/gascity-test.el`) must stay green. Any
  new ERT for the remote path must stub the gc boundary (`gascity-reader-read`
  / `-read-async`) per repo convention, or guard live-`gc` cases with
  `skip-unless`.
- **Test city.** The remote verification target is the real second city at
  `/home/roman/bright-lights`, opened as `/ssh:localhost:/home/roman/bright-lights`.

## Proposed Implementation

Work items are ordered so the diagnosis informs every later decision; the
decomposition stage may split them further.

### W1 — Pooling diagnosis (REQ-001, AC-1)

- Inspect, on the bright-lights connection, which async handler is active:
  read the connection-local value of `tramp-direct-async-process` for the
  `/ssh:localhost:` VEC and check `tramp-get-connection-property`/process list
  after a manual `gascity-reader-read-async` call.
- Measure: record the number of ssh login lines in `~/.bash_history` (or sshd
  auth-log entries, or `who`/`ss` snapshots) before and after N = 10
  consecutive `gascity-reader-read-async` calls. Read-only access to the user's
  history files is evidence gathering, never modification.
- Record the finding — file/function references plus before/after counts — in
  the implementation summary artifact. The conclusion must be one of:
  direct-async spawns a new ssh per read (fix in W2), or tramp-sh pooling
  already holds (document in W2).
- In the same pass, gather evidence for the `cd emacs-city/` line attribution
  (REQ-006): correlate timestamps with pi agent activity and the sshd login
  shell's `~/.bashrc` sourcing. Anything unattributable goes to Open Questions,
  not guesses.

### W2 — Fix or document connection reuse (REQ-002, AC-2)

- If W1 shows direct-async spawning a new ssh per async read: prefer disabling
  direct-async for gascity.el's async reads (connection-local
  `tramp-direct-async-process` nil in `gascity-remote.el`'s setup), so all
  reads share the tramp-sh channel and the pooled connection. Confirm the
  existing reader code paths (stderr wrapper, executable resolution) still
  hold under tramp-sh — they were explicitly built to behave identically under
  both handlers, so the change should be a one-line connection-local default.
  If instead a targeted fix keeps direct-async but reuses connections, evaluate
  it against the same constraint: no fresh ssh login per refresh tick.
- If W1 shows pooling already holds: add a code comment in
  `gascity-reader.el`/`gascity-remote.el` and a rig-doc note stating the
  conclusion with the measured evidence; change no behavior.
- Constraint from the architecture: the one-gc-call-site data plane stays
  intact; only the remote/read setup changes. Verify remote city views still
  work identically over TRAMP (status dashboard, tabulated lists, rig
  dashboards) — per repo protocol, check against
  `/ssh:localhost:/home/roman/bright-lights`, not only locally.

### W3 — `HISTFILE=/dev/null` for TRAMP inner shells (REQ-004, AC-4)

- In `gascity-remote.el`'s connection-local setup, extend
  `tramp-remote-process-environment` with `HISTFILE=/dev/null` so TRAMP inner
  shells stop accumulating `~/.tramp_history` bloat. **Append** the entry to
  the variable's existing list (TRAMP's own default environment entries like
  `HISTORY=/dev/null` must survive); never rebind the variable wholesale. Ensure the override is
  applied where gascity.el owns remote buffers (the existing
  connection-local install site), not globally for the user's other TRAMP
  usage outside gascity.el buffers — scope it the same way the existing
  path/executable connection-locals are scoped.
- Add an ERT asserting the override reaches TRAMP's remote process
  environment (pure test: stub the boundary, assert the connection-local
  environment vector contains `HISTFILE=/dev/null`).
- Document the truncation of the existing 655 KB `~/.tramp_history` as a
  **user-run** command (e.g. `: > ~/.tramp_history`), explicitly marked as
  never executed by the workflow.

### W4 — Host-side `.bashrc` guard recipe (REQ-003, AC-3)

- Write a copy-paste recipe into the Texinfo manual (`doc/gascity.texi`, a
  short node near the remote/TRAMP material under Customization) plus a
  `docs/qa/` dogfood note: an early guard
  in `~/.bashrc` for non-interactive sshd-spawned shells (e.g. return early or
  unset `HISTFILE` when `$SSH_CONNECTION` is set and the shell is
  non-interactive, before the multi-window `PROMPT_COMMAND` history trick on
  line 69). The recipe must work regardless of gascity.el.
- The workflow only writes the recipe into the repository; it never edits
  `~/.bashrc` or `~/.tramp_history` on the user's host (counterexample in the
  requirements is a hard non-goal).

### W5 — Verification artifact (REQ-005, AC-2, AC-5)

- Provide the connection-count verification: an ERT where automation is
  practical (drive N async reads through `gascity-reader-read-async` against a
  stubbed or guarded-remote boundary and count spawned ssh processes), plus a
  documented manual procedure for the live-city case (before/after count of
  ssh login lines or sshd log entries over N ≥ 10 refresh ticks).
- Record the measurement procedure and the result in the implementation
  summary so the review/publish stages can link REQs to evidence (AC-6).
- Full quality gate green: `scripts/gate.sh` from the repo root.

### Sequencing

W1 → W2 (informed by W1) → W3 and W4 (independent of W1's outcome) → W5.
The implementation summary accumulates evidence from every step; the review
stage checks REQ-by-REQ traceability.

## Non-Goals

- **No editing of user dotfiles.** `~/.bashrc`, `~/.tramp_history`, and
  `~/.bash_history` are read (read-only) as evidence but never modified by the
  workflow; truncation is documented as a user-run command (REQ-003/REQ-004
  counterexample).
- **No changes to the `gc` CLI or other Gas City components.** All code
  changes stay inside gascity.el's remote/read path (`gascity-remote.el`,
  `gascity-reader.el`, refresh wiring if strictly needed).
- **No reimplementation of TRAMP pooling** — reuse TRAMP's own mechanisms
  (connection-local variables, `tramp-remote-process-environment`); no custom
  connection cache.
- **No changes to beads.el or vui** — their bundled behavior is out of scope.
- **No rework of the view layer** (tabulated/vui rendering, filters, keys);
  views must keep working unchanged.
- **No silencing of legitimate history.** The recipe and overrides target
  non-interactive/inner shells only; the user's interactive shell history is
  untouched.
- **No guessing on REQ-006** — unresolved attribution is recorded in Open
  Questions with gathered evidence, not asserted.

## Verification

- **Schema gate.** The plan artifact validates against `gc.build.plan.v1` via
  `.gc/scripts/checks/build-artifact-valid.sh` (this file, front matter and
  coverage table above).
- **Quality gate.** `scripts/gate.sh` passes: byte-compile with
  `--warnings-as-errors` (whole package — this catches missing
  `declare-function` for action verbs wired across files) plus the full ERT
  suite.
- **Pooling verification (AC-2).** After W2: N ≥ 10 consecutive async remote
  reads against `/ssh:localhost:/home/roman/bright-lights` produce at most 2
  new ssh connections, measured by login-line counting (or sshd log), recorded
  in the implementation summary; remote views verified working over TRAMP
  (status dashboard, lists, rig dashboards), including the interactive
  tmux-Emacs acceptance pass per the repo's e2e protocol when the change is
  user-facing.
- **Environment override (AC-4).** ERT asserts `HISTFILE=/dev/null` is applied
  through `tramp-remote-process-environment` in gascity.el's remote setup.
- **Docs (AC-3).** The `.bashrc` guard recipe exists in the rig docs with an
  exact copy-paste snippet; `git status` shows no modification outside the
  repository.
- **Traceability (AC-6).** The publish/final-report artifacts link every REQ
  (and `ga-llhb`) to the change or document that satisfied it.

### Open Questions carried from requirements

- `cd emacs-city/` attribution (REQ-006): if W1 cannot attribute it
  conclusively, record the evidence and the unresolved status in the
  implementation summary's open questions rather than blocking.
- The recipe location question (requirements Open Questions) is resolved:
  `doc/gascity.texi` plus a `docs/qa/` note (see W4).
- If W1 finds direct-async is *not* active and pooling already holds, W2
  becomes documentation-only; the connection-count verification (W5) then
  guards against future regressions (e.g. a later Emacs changing the default
  handler).

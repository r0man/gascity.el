---
schema: gc.build.requirements.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: requirements
  attempt: 1
status: approved
trace:
  upstream:
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

# Requirements: Reduce TRAMP connection churn and neutralize host-side history pollution

## Problem Statement

`~/.bash_history` on the user's host fills up with lines that look like they come
from Emacs/TRAMP. 474 of 500 lines are TRAMP's standard ssh shell-login line
(`exec env TERM='dumb' INSIDE_EMACS='ghostel,tramp:…' … /bin/sh -i`), one per
TRAMP connection. The inner shell behaves as designed (`HISTFILE=~/.tramp_history`
holds the bloat, 655 KB), but the sshd-spawned login shell still records the
login command into `~/.bash_history` — verified host-side, since even plain
`ssh localhost true` grows the file. gascity.el does not write the history, but
it plausibly drives the *volume*: its TRAMP remote views (`gascity-remote.el`,
async reads via `gascity-reader-read-async` backing auto-refresh timers) may open
a fresh ssh connection per refresh tick if async `process-file` reads bypass
TRAMP connection pooling. This workflow must fix what is fixable in gascity.el
and document the rest; it must not silently edit the user's dotfiles.

### Trace Coverage

| ID       | Status  |
| -------- | ------- |
| ga-llhb  | covered |
| REQ-001  | covered |
| REQ-002  | covered |
| REQ-003  | covered |
| REQ-004  | covered |
| REQ-005  | covered |
| REQ-006  | covered |

## W6H

- **Who** — the user (Emacs user "roman" / "ghostel" emacs client) affected by
  polluted `~/.bash_history`; the gascity.el maintainer who implements the fix;
  gascity.el's remote views (status dashboard, tabulated lists, rig dashboards)
  that generate TRAMP traffic.
- **What** — (1) verify whether async TRAMP reads bypass connection pooling and
  fix or document the reuse; (2) document a host-side `.bashrc` guard recipe that
  neutralizes login-shell history recording regardless of gascity.el; (3)
  recommend `HISTFILE=/dev/null` for TRAMP inner shells via
  `tramp-remote-process-environment` in gascity.el's remote setup and document
  truncation of the existing `~/.tramp_history` bloat; (4) add a repeatable
  verification that N consecutive async remote reads produce at most 1–2 ssh
  connections.
- **When** — during this build workflow (requirements → plan → implement →
  review → publish); the verification check must keep passing in `scripts/gate.sh`
  afterwards.
- **Where** — the gascity.el repository (`~/workspace/gascity.el`, remote city
  `/home/roman/bright-lights` reachable as `/ssh:localhost:/home/roman/bright-lights`
  is the test target), plus documentation locations inside the repo for the
  host-side recipe. The user's actual dotfiles (`~/.bashrc`, `~/.tramp_history`)
  are read as evidence but never modified by the workflow.
- **Why** — auto-refresh-driven connection churn wastes resources (an ssh login
  per tick), makes `~/.bash_history` and `~/.tramp_history` unusable as real
  history, and obscures genuine shell activity.
- **How** — diagnose TRAMP pooling behavior under async `process-file` calls
  (connection-local settings, `tramp-connection-pool` semantics); fix or document
  reuse in gascity.el's read path; ship the host-side recipe as documentation;
  add an ERT or documented manual check counting connections.

## User Stories

- As a user of gascity.el's remote city views, I want auto-refresh to reuse
  existing TRAMP ssh connections so that hours of idling with a dashboard open
  do not flood my host with ssh logins.
- As a user, I want `~/.bash_history` to contain only commands I actually typed,
  so my shell history is trustworthy.
- As a user, I want a copy-paste recipe I can apply myself to stop sshd-spawned
  login shells from recording history, because the workflow must not touch my
  dotfiles for me.
- As a maintainer, I want a repeatable verification (ERT or documented manual
  procedure) that N consecutive async remote reads open at most 1–2 ssh
  connections, so regressions in connection reuse are caught.

## Technical Stories

- As a maintainer, I want the diagnosis recorded with concrete evidence (file,
  function, measured connection counts) so the plan stage can choose between a
  code fix and documentation-only handling without re-investigating.
- As a maintainer, I want any gascity.el change confined to the remote/read path
  (`gascity-remote.el`, `gascity-reader.el`, tabulated/status refresh wiring) and
  the whole package byte-compile and test gates green (`scripts/gate.sh`).
- As a maintainer, I want the recommended `tramp-remote-process-environment`
  setup (if adopted) to be verifiable by an ERT that asserts the environment
  override reaches TRAMP's remote process environment, keeping the one-gc-call-site
  data plane untouched.

## Behavior Requirements

- **REQ-001** — Diagnose TRAMP connection behavior for gascity.el's async remote
  reads: determine (with evidence from the code and a reproducible measurement,
  e.g. sshd/login-line counts before and after a run) whether each async
  `process-file` read opens a new ssh connection or reuses the pooled one, and
  record the finding in the build artifacts.
- **REQ-002** — If the diagnosis shows async reads bypass pooling, fix or
  document the reuse in gascity.el so that auto-refresh timers do not open a
  fresh ssh connection per tick. If the behavior is already pooled, document
  that conclusion where a reader would look for it (code comment or rig docs)
  instead of changing code.
- **REQ-003** — Document a host-side neutralization recipe (e.g. an early guard
  in `~/.bashrc` that unsets `HISTFILE` or returns before the multi-window
  `PROMPT_COMMAND` history trick for non-interactive sshd-spawned shells) in the
  rig docs or mayor notes. The recipe works regardless of gascity.el. Do not
  silently edit the user's dotfiles.
- **REQ-004** — Recommend and, if the plan approves, implement setting
  `HISTFILE=/dev/null` for TRAMP inner shells via `tramp-remote-process-environment`
  in gascity.el's remote setup, and document how to truncate the existing
  `~/.tramp_history` bloat as a user-run command (never executed by the workflow).
- **REQ-005** — Provide a verification artifact: an ERT (or a documented manual
  procedure where automation is impractical) that demonstrates N consecutive
  async remote reads against the remote test city produce at most 1–2 ssh
  connections, using sshd logging, ssh `LogLevel`, or login-line counting as the
  measurement.
- **REQ-006** — Investigate the suspicious non-TRAMP write (a bare
  `cd emacs-city/` line observed at 22:27): attribute which process writes it
  (pi agent bash subshells vs the sshd login shell sourcing `~/.bashrc`, whose
  line 69 sets the multi-window `PROMPT_COMMAND` trick), or record the unresolved
  attribution in Open Questions with the evidence gathered.

## Example Mapping

- **Example 1** — Given an open remote status dashboard with auto-refresh,
  when 10 refresh ticks elapse, then the number of new ssh login lines in
  `~/.bash_history` is at most 2 (REQ-001, REQ-002, REQ-005).
- **Example 2** — Given the pooling diagnosis finds async reads bypass the
  connection pool, when the fix lands, then the same 10-tick experiment shows
  connection reuse after the fix and the delta is recorded in the build
  artifacts (REQ-002).
- **Example 3** — Given the user applies the documented `.bashrc` guard recipe,
  when `ssh localhost true` runs, then `~/.bash_history` gains no new line
  (REQ-003).
- **Example 4** — Given gascity.el's remote setup applies the recommended
  `tramp-remote-process-environment` override, when a TRAMP inner shell starts,
  then its history goes to `/dev/null` and `~/.tramp_history` stops growing
  (REQ-004).
- **Counterexample** — A change that edits the user's `~/.bashrc` or deletes
  `~/.tramp_history` from within the workflow violates REQ-003/REQ-004 and must
  not be merged.

## Acceptance Criteria

- **AC-1 (REQ-001, REQ-006)** — The plan/implementation artifacts state the
  pooling conclusion and the `cd emacs-city/` attribution with concrete
  evidence: file/function references from the codebase plus a measured
  before/after count of ssh login lines (or an equivalent sshd-log measurement).
  Anything not attributable is listed in Open Questions rather than guessed.
- **AC-2 (REQ-002)** — After the gascity.el change (or documented no-fix
  conclusion), running N ≥ 10 consecutive async remote reads against
  `/ssh:localhost:/home/roman/bright-lights` produces at most 2 new ssh
  connections, and the measurement is recorded. The remote city views keep
  working identically (status dashboard, lists, rig dashboards) over TRAMP.
- **AC-3 (REQ-003)** — The host-side recipe exists in the rig docs (or mayor
  notes) with an exact copy-paste snippet; `git status` in this repository shows
  no modification to the user's dotfiles and the workflow never ran a command
  that altered `~/.bashrc` or `~/.tramp_history`.
- **AC-4 (REQ-004)** — The `HISTFILE=/dev/null` recommendation is documented;
  if adopted in code, an ERT asserts the override is applied through
  `tramp-remote-process-environment`, and the truncation instructions for the
  existing 655 KB `~/.tramp_history` are written as a user-run command.
- **AC-5 (REQ-005)** — The verification check (ERT and/or documented manual
  procedure) is present, and the full quality gate passes: `scripts/gate.sh`
  (byte-compile with `--warnings-as-errors` + ERT suite) is green.
- **AC-6** — The workflow's publish/final-report artifacts link each REQ above
  to the change or document that satisfied it, preserving traceability to
  `ga-llhb`.

## Out Of Scope

- Editing the user's dotfiles (`~/.bashrc`, `~/.bash_history`,
  `~/.tramp_history`) — recipes and user-run commands are documented instead.
- Fixing sshd or the operating system's login-shell history behavior beyond the
  documented recipe.
- Changing beads.el or vui (dependencies outside this repository).
- General TRAMP performance work unrelated to connection churn and history
  pollution.
- Replacing the one-gc-call-site data plane (`gascity-reader.el`) with a
  different remote-execution mechanism.

## Open Questions

- The recipe's target location is ambiguous: "rig docs or mayor notes" — the
  plan stage should pick one (default: `doc/` Texinfo manual plus a dogfood
  note under `docs/qa/`).
- Whether the `HISTFILE=/dev/null` override should be unconditional for all
  gascity.el remote reads or opt-in per city/rig; default per the bead is to
  recommend it in gascity.el's remote setup, but the plan may scope it.
- Truncating the existing 655 KB `~/.tramp_history` needs user consent and is
  therefore documented only; confirm with the user before any execution outside
  this workflow.
- If the `cd emacs-city/` write cannot be attributed with the evidence
  available during implementation, REQ-006 resolves to an Open Questions entry
  rather than a code change; downstream stages should treat that as a pass for
  REQ-006 provided the evidence gathered is recorded.

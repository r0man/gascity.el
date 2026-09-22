Plan review for `plans/tramp-history-flood/implementation-plan.md`
(schema `gc.build.plan.v1`, produced by workflow root ga-2ea1 / step
build-basic.plan-review, bead ga-q7hp).

## Verdict

**approved** — no blockers for decomposition. The plan passes the
`gc.build.plan.v1` schema gate (re-validated after review edits) and every
requirements id is traced to a concrete work item. Two minor refinements were
folded into the plan during review (listed below); nothing remains unresolved.

## Schema and trace integrity

- Front matter declares the required shape (`schema`, `workflow`, `methodology`,
  `producer`, `status: approved`, `trace` with mapping objects); the Markdown
  coverage table matches `trace.coverage` exactly (7 ids, status `covered`).
- The `sha256:` hash recorded for the requirements upstream entry matches the
  actual `plans/tramp-history-flood/requirements.md` digest
  (`85adb522…687bea`) — verified during review.
- Coverage statuses use `covered` only; no `approved` leakage into coverage.

## Technical grounding (verified against the code)

- The plan's claim that `gascity-reader.el` is aware of both async handlers
  (tramp-sh pooled channel vs `tramp-direct-async-process`) holds: the module
  commentary and the `make-process` adapter discuss both, including the
  string-`':stderr'` incompatibility and the pty/token quirks (gce-m6k).
- The plan's claim that `gascity-remote.el` already owns the connection-local
  machinery (search-path probing, `gascity-remote-path-assignment`, executable
  resolution cache) holds; there is currently **no**
  `tramp-remote-process-environment` override anywhere in the tree, so W3's
  premise is accurate.
- Auto-refresh timers do drive repeated async reads
  (`gascity-session-list--auto-refresh-tick` and the status dashboard's
  mirror), so the churn hypothesis is testable as W1 states.

## Implementation readiness pass

- **Requirements traceability** — W1→REQ-001+REQ-006, W2→REQ-002, W3→REQ-004,
  W4→REQ-003, W5→REQ-005 (+AC-2/AC-5); ga-llhb is the root. Every REQ maps to
  at least one work item and the Verification section maps ACs to proof.
- **Task boundaries** — each of W1–W5 can become a clear implementation bead:
  W1 is a no-code-change diagnosis with a recorded deliverable; W2 is
  explicitly conditional on W1's conclusion (fix vs document-only) and the bead
  description must carry that decision gate; W3 and W4 are independent of W1;
  W5 is the verification artifact. Sequencing (W1 → W2 → W3/W4 → W5) is
  compatible with exclusive member access.
- **Test commands / strategy** — the plan names the focused proof: ERT for the
  `HISTFILE` override and the connection-count check (stubbed boundary per repo
  convention, `skip-unless` for live cases), the documented manual N≥10-read
  measurement against `/ssh:localhost:/home/roman/bright-lights`, the TRAMP
  e2e protocol, and `scripts/gate.sh` as the package gate.
- **Risk** — changes are confined to `gascity-remote.el` /
  `gascity-reader.el` (+docs); the one-gc-call-site data plane, view layer,
  beads.el/vui, and `gc` CLI are declared non-goals. Public interface risk is
  low (connection-local defaults + docs). Rollback is a plain git revert of the
  confined file set; no migrations or persistent state are involved. The
  counterexample guard (never touch user dotfiles) is explicit and testable via
  `git status`.

## Findings folded into the plan during review

1. **W3 append-not-replace caution (added).** `tramp-remote-process-environment`
   carries TRAMP's own defaults (e.g. `HISTORY=/dev/null`); a gascity.el
   connection-local override must **append** `HISTFILE=/dev/null` to the
   existing list rather than rebind the variable wholesale, or it would clobber
   TRAMP's defaults for every TRAMP user on the connection.
2. **W4 recipe location resolved (added).** The requirements carried an open
   question ("rig docs or mayor notes"); the plan now fixes it to
   `doc/gascity.texi` (short node near the remote/TRAMP material) plus a
   `docs/qa/` dogfood note, matching the requirements' default.

## Non-blocking observations for the decomposer

- W2's bead description must restate the W1 decision gate (direct-async active
  → code fix; pooling holds → comment/rig-doc note only) so the implementer
  does not re-litigate the diagnosis.
- The W5 ERT "count spawned ssh processes" variant is inherently
  environment-sensitive; the plan already permits the documented manual
  procedure as the primary proof — prefer that as the AC-2 evidence and keep
  the ERT for the stubbed/regression level.

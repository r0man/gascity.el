# Test evidence review: build-basic starter factory (workflow root ga-2ea1)

- Reviewer: starter factory test evidence review lane (bead `ga-aelq`, step
  `review.test-evidence-review`, iteration 1)
- Date: 2026-09-21
- Context authority: `starter-review-context.md` §Implementation Worktrees
- Verdict: **approve** (`code_review.test_evidence_verdict=approve`)

## Method

Every accepted task's recorded evidence was checked for the five required
fields (intended behavior, first verification command, proof command, changed
files, remaining risks), and the recorded proof commands were **re-executed
from the listed implementation worktrees** — `cd "$WORKTREE"` with `pwd -P`
verified equal to the worktree before each command. The launcher rig root was
used only where the recorded proof command itself runs from there (the schema
validators). The live TRAMP connection-count procedure (W2/W5 proof) was
re-executed from the `ga-ldrg` worktree against
`/ssh:localhost:/home/roman/bright-lights`.

## Per-task evidence checklist

| Task | Plan item | Intended behavior | First verification cmd | Proof cmd | Changed files | Remaining risks | Commands cover ACs | Re-executed here |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ga-o98t | W1 (REQ-001, REQ-006) | ✓ | ✓ pooling experiment | ✓ schema validator | ✓ (none — diagnosis-only, consistent with scope) | ✓ | ✓ AC-1 | validator **pass** (`{"ok": true}`) |
| ga-x4j3 | W2 (REQ-002) | ✓ | ✓ `scripts/gate.sh` | ✓ live TRAMP SSH-PROCS | ✓ (3 files, verified present) | ✓ | ✓ AC-2 | gate **pass**, 322/322 |
| ga-sfnj | W3 (REQ-004) | ✓ | ✓ histfile ERT | ✓ full gate | ✓ (4 files, verified present) | ✓ | ✓ AC-4 | ERT **pass**; gate **pass**, 323/323 |
| ga-5b9m | W4 (REQ-003) | ✓ | ✓ `make -C doc` | ✓ gate + `git status` non-modification | ✓ (2 files, verified present) | ✓ | ✓ AC-3 | forced-fresh doc build **pass**; gate **pass**, 322/322; porcelain clean |
| ga-ldrg | W5 (REQ-005) | ✓ | ✓ gate | ✓ pooling ERT + live manual procedure | ✓ (2 files, verified present) | ✓ | ✓ AC-2, AC-5 | ERT **pass**; gate **pass**, 323/323; live re-run within bound |

Worktree anchors all verified: each path exists, is a git worktree, HEAD
matches the context table (`3e3fc20`, `0ff5454`, `15b33b7`, `02de86a`;
`ga-o98t` at `9fb54c5` with no commit — correct for a diagnosis-only item),
and `git status --porcelain` is empty in all five.

## Acceptance-criteria coverage

- **AC-1 (REQ-001, REQ-006)** — Covered by W1's recorded measurement
  (handler identity, 10 reads → 1 ssh at establishment, exec-line delta 501 →
  501; `cd emacs-city/` attribution with residual uncertainty in Open
  Questions, as the requirements permit). The summary artifact passes its
  schema gate (re-run here).
- **AC-2 (REQ-002)** — Covered by W2's live re-check and W5's ERT + manual
  procedure. Re-executed live in this lane from `worktrees/ga-ldrg`:
  `done=10 errs=0`, ssh connections `before=2 after=3 new=1` — the single
  pooled-connection establishment, zero per read, inside the at-most-2 bound.
- **AC-3 (REQ-003)** — Recipe present in `doc/gascity.texi` (*Host-side shell
  history guard*, with the copy-paste `unset HISTFILE` guard) plus
  `docs/qa/2026-09-21-bashrc-guard-recipe.md`. All worktrees porcelain-clean;
  the only changed files are the documented repo files; no dotfile writes
  anywhere in the evidence chain.
- **AC-4 (REQ-004)** — ERT `gascity-test-remote-connection-local-histfile-override`
  re-run **pass** (1/1); the override content (`HISTFILE=/dev/null`,
  `gascity-remote-history-silencer`/`-environment`/`-silence-shell-history`,
  factory wiring in `gascity-context.el`) verified present in the worktree;
  `: > ~/.tramp_history` user-run truncation documented in
  `doc/gascity.texi` (line ~1081) and the module commentary.
- **AC-5 (REQ-005)** — Verification artifact present (ERT
  `gascity-test-remote-async-reads-pool-connections`, re-run **pass** 1/1,
  plus the README live procedure with the at-most-2 bound); all four
  worktree gates re-run **pass** with exactly the recorded test counts
  (323 / 322 / 322 / 323 — the ±1 deltas are the per-branch doc-only vs
  one-new-test deltas, internally consistent).
- **AC-6** — Publish-stage traceability; not this lane's scope (the
  final-report stage owns it).

## Findings

No product defects and no missing proof were found. Three observations,
recorded for the record (none require the fix lane to change code):

1. **Ephemeral measurement script (missing-proof-class, low).** W1's first
   verification command references `/tmp/w1-pooling-experiment.el`, which is
   not preserved under the artifact tree; the experiment is not byte-for-byte
   reproducible from the artifacts alone. Mitigated: W5's standing ERT and
   README procedure cover the same regression class, and W1's results are
   fully recorded with before/after values. Suggested follow-up (optional):
   copy future experiment scripts into `plans/<workflow>/` next to the
   summary that cites them.
2. **Stale doc artifacts can make the W4 `make -C doc` proof a no-op.** In
   this re-run the recorded command completed without rebuilding (stale
   `doc/gascity.info`/`gascity.html`); a forced fresh build passes clean.
   Suggested follow-up (optional): proof as `make -C doc clean all` or remove
   generated files before the recorded run.
3. **Live connection-count runs are environment-dependent (as already
   recorded in the summaries' risks).** Recorded runs observed `new=0`; this
   lane's re-run observed `new=1` (the burst's own pooled connection
   establishment). Both are inside the at-most-2 bound and consistent with
   the diagnosis (one login per new connection, zero per read).

## Verdict

All five accepted tasks recorded the required evidence fields; every recorded
proof command was located in its proper implementation worktree (never the
launcher root) and re-executed successfully with results matching the
recorded outcomes; the commands cover the acceptance criteria they claim.
**Approve** — no fix-lane code changes are required; the three observations
above are procedural suggestions only.

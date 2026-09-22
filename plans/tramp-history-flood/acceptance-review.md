---
schema: gc.build.review.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: review
  stage: acceptance-review
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - ga-llhb
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
      ids:
        - W1
        - W2
        - W3
        - W4
        - W5
    - path: plans/tramp-history-flood/implementation-summary.md
      hash: sha256:75cddc09ec077f474704df67fb75439ee636f15cc6621342c88472e6750c080c
      ids:
        - ga-o98t
        - ga-sfnj
        - ga-5b9m
        - ga-x4j3
        - ga-ldrg
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
    - id: AC-1
      status: covered
    - id: AC-2
      status: covered
    - id: AC-3
      status: covered
    - id: AC-4
      status: covered
    - id: AC-5
      status: covered
    - id: AC-6
      status: out_of_scope
      rationale: >-
        Publish-stage REQ-to-change traceability (AC-6) is owned by the
        finalize/final-report stage, not by the acceptance review lane; the
        canonical summary already records the per-item linkage for it.
    - id: W1
      status: covered
    - id: W2
      status: covered
    - id: W3
      status: covered
    - id: W4
      status: covered
    - id: W5
      status: covered
    - id: ga-o98t
      status: covered
    - id: ga-sfnj
      status: covered
    - id: ga-5b9m
      status: covered
    - id: ga-x4j3
      status: covered
    - id: ga-ldrg
      status: covered
---

# Acceptance review: build-basic starter factory (review bead ga-6gi4)

### Trace Coverage

| ID      | Status       |
| ------- | ------------ |
| ga-llhb | covered      |
| REQ-001 | covered      |
| REQ-002 | covered      |
| REQ-003 | covered      |
| REQ-004 | covered      |
| REQ-005 | covered      |
| REQ-006 | covered      |
| AC-1    | covered      |
| AC-2    | covered      |
| AC-3    | covered      |
| AC-4    | covered      |
| AC-5    | covered      |
| AC-6    | out_of_scope |
| W1      | covered      |
| W2      | covered      |
| W3      | covered      |
| W4      | covered      |
| W5      | covered      |
| ga-o98t | covered      |
| ga-sfnj | covered      |
| ga-5b9m | covered      |
| ga-x4j3 | covered      |
| ga-ldrg | covered      |

Reviewed the build against the approved requirements, plan, decomposition, and
per-item implementation summaries, per the review context
(`gc.build.code_review_context_path`,
`plans/tramp-history-flood/starter-review-context.md`). Every relative source
path and proof command was resolved against the five implementation worktrees
recorded in the context's **Implementation Worktrees** section; the launcher
rig root (`/home/roman/workspace/gascity.el`, still at base `9fb54c5`) was NOT
used as the review target, per the bead contract.

## Verdict

**approve** — the factory built the requested behavior: pooling was diagnosed
with a measured experiment (W1), the pooled conclusion is documented where a
reader looks (W2), the `HISTFILE=/dev/null` override is implemented in code
with append semantics and an ERT (W3), the host-side `.bashrc` guard recipe
ships as documentation only (W4), and the connection-count verification exists
as an ERT plus a documented manual procedure (W5). No out-of-scope changes
were found: all four item commits touch only the files the summaries record
(remote/read setup, tests, docs); the one-gc-call-site data plane, view layer,
beads.el/vui, and user dotfiles are untouched.

## Findings

No blocking findings. Two non-blocking observations for the synthesis lane
(no code change required for approval; record or fold in at will):

1. **W3 scope guarantee is connection-granular, not buffer-granular
   (observation, REQ-004).** The buffer-local
   `tramp-remote-process-environment` append is correct per AC-4 and the ERT
   (`gascity-test-remote-connection-local-histfile-override`, re-run: pass)
   asserts exactly what AC-4 asks. Source-verified mechanism (TRAMP
   2.7.3.30.2, `tramp-sh.el`): the override lands in the shared connection
   shell via the "Setting default environment" export loop at connection
   setup, and inner async shells inherit it — so the W3 claim that "the async
   make-process path is covered directly" holds **when a gascity view buffer
   establishes the connection environment**. Two boundary notes: (a) if a
   non-gascity buffer opens the connection first, the override does not reach
   the connection shell (gascity's later buffer-local value is not
   re-exported; only the W3 summary's "sync path environment timing" risk
   covers this, and the async path has the same timing); (b) once exported,
   `HISTFILE=/dev/null` is visible to the *whole connection*, so other
   non-gascity buffers on the same connection also get it — the docstring's
   "the user's other TRAMP usage keeps the untouched global value" is true of
   the variable, not strictly of the shared connection shell. Both are
   benign for the target behavior (silencing history) and the plan's W3 intent
   ("scope it the same way the existing path/executable connection-locals are
   scoped" — read at gascity's own invocation sites — is honored). No fix
   required; synthesis may note the nuance in the manual section.
2. **AC-2 measured bound is looser than observed (observation, no action).**
   The at-most-2 bound of `gascity-test-remote-async-reads-pool-connections`
   and the README procedure is the requirements' own bound; observed deltas in
   W1/W2/W5 and this review's independent re-run were 0.

## Verification

Every check below was run from the recorded implementation worktree (each
verified `pwd -P` equals the recorded absolute path; HEADs match the context
table: `3e3fc20`/ga-sfnj, `0ff5454`/ga-5b9m, `15b33b7`/ga-x4j3,
`02de86a`/ga-ldrg, `9fb54c5`/ga-o98t diagnosis-only):

- `scripts/gate.sh` in `worktrees/ga-sfnj` — pass (compile clean, 323/323).
- `scripts/gate.sh` in `worktrees/ga-5b9m` — pass (322/322).
- `scripts/gate.sh` in `worktrees/ga-x4j3` — pass (322/322).
- `scripts/gate.sh` in `worktrees/ga-ldrg` — pass (323/323).
- `eldev test gascity-test-remote-connection-local-histfile` (ga-sfnj) —
  pass 1/1.
- `eldev test gascity-test-remote-async-reads-pool-connections` (ga-ldrg) —
  pass 1/1.
- `make -C doc` in `worktrees/ga-5b9m` — pass (clean rebuild, no warnings).
- `git diff --stat 9fb54c5 HEAD` per changed worktree — changed-file sets
  match the per-item summaries exactly (W2's `.el` edits verified
  comment/docstring-only; W4 only `doc/gascity.texi` + the `docs/qa/` note);
  `git status --porcelain` clean in all four.
- Independent live re-verification of AC-2 from `worktrees/ga-ldrg` code
  against `/ssh:localhost:/home/roman/bright-lights` (bounded batch Emacs):
  `ASYNC-READS ok=10 pending=0`, `SSH-PROCS before=4 after=4 new=0` — 10/10
  async reads, zero new ssh connections.
- Dotfile non-modification (AC-3): `.bashrc` on this host is a symlink into a
  read-only `/gnu/store` path (not modifiable by the workflow); item
  worktrees show no changes outside the repository; no truncation command was
  executed by any item.
- Correctness spot-checks: W3's `gascity-remote-history-environment` preserves
  TRAMP defaults and is idempotent (asserted by the ERT, confirmed by source
  reading); the W2 documentation-only branch is exactly the plan §W2
  "pooling already holds" outcome of W1's measurement; the W4 guard snippet is
  correct bash (`$- != *i*`, `unset HISTFILE`, `return … || exit`) and is
  positioned before the `PROMPT_COMMAND` history block as the plan requires.

Out of scope for this lane: AC-6 (publish-stage REQ→change traceability in
the final report) — owned by the publish/finalize stage, not by the
implementation.

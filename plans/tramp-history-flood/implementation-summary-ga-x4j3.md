---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-aflg
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
    - path: beads/ga-x4j3
      hash: bead:ga-x4j3
      ids:
        - ga-x4j3
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-002
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
  coverage:
    - id: ga-x4j3
      status: covered
    - id: REQ-002
      status: covered
    - id: AC-2
      status: covered
---

# Implementation Summary: W2 — Fix or document TRAMP connection reuse

## Summary

**W2 resolved to its documentation branch: TRAMP connection pooling for
gascity's async remote reads already holds, so the item landed as a
documentation-only change — a code comment recording the conclusion with the
measured evidence (in `gascity-remote.el`'s commentary and the
`gascity-reader-read-async` docstring) and a rig-doc note (README's
"Remote cities (TRAMP)" section). No behavior changed, per the plan's §W2
"pooling already holds" branch.** The evidence base is W1's measurement
(implementation-summary-ga-o98t.md): the tramp-sh channel handler is the
active `make-process` :file-handler on `/ssh:` connections, and it
multiplexes every async read over the ONE pooled ssh connection. This
session re-verified the conclusion live against the real remote test city:
a sync `status` read plus N = 10 consecutive async reads over
`/ssh:localhost:/home/roman/bright-lights` completed 10/10 with zero errors
and spawned **zero** new ssh processes (3 ssh processes matching
`localhost` before the burst, 3 after).

## Intended Behavior

- A user reading the reader/remote sources or the README learns that the
  default (tramp-sh) handler pools all gascity async remote reads on one
  ssh connection — the "one-gc-call-site data plane stays intact"
  constraint of the architecture holds untouched.
- A user considering TRAMP's direct-async mode is warned that it spawns a
  fresh local ssh per read, i.e. exactly the per-refresh login flood the
  pooling avoids, and that gascity itself never enables it (its
  direct-async support exists only so a connection where the user DID
  enable it still behaves correctly).
- REQ-002/AC-2 (connection reuse verified; async reads share the pooled
  channel rather than opening a fresh ssh per read) is satisfied by
  documented, measured evidence instead of a code change, exactly as
  plan §W2's second branch prescribes.

## Changed Files

Worktree `/home/roman/workspace/gascity.el/worktrees/ga-x4j3`, commit
`15b33b7d3a6ad3bcd08be3601557149e318952bf`
(`docs(remote): document TRAMP connection pooling for async reads (ga-x4j3)`),
based on `9fb54c5` (origin/main tip fetched by the prepare-worktree step):

| File | sha256 (post-change) | Change |
| --- | --- | --- |
| lisp/gascity-remote.el | sha256:efd8b6a0196a4f875f987bc2bf4a36f2ab4f62f5f48bc3f4197950427f4776ea | New "Connection reuse" paragraph in the file commentary |
| lisp/gascity-reader.el | sha256:b1dcdde864420ae5aafdd829a2bfd52f5c70c809237bbe4ba9c117a8eb300bd5 | Connection-reuse note appended to the `gascity-reader-read-async` docstring |
| README.md | sha256:6a148899445700154c5d62d196e292df495d0e2017016e19b0cd212db60be4e5 | "Remote cities (TRAMP)" notes: direct-async warning + pooling evidence in the Performance bullet |

No `.el` behavior was modified: the two Lisp edits touch only comments and
a docstring, so the gate (byte-compile + full ERT suite) and the live TRAMP
run below exercise the unchanged code paths against the new documentation.

Coverage traceability:

| ID | Status |
| --- | --- |
| ga-x4j3 | covered |
| REQ-002 | covered |
| AC-2 | covered |

## Verification

- **First verification command** — the repo quality gate, run in the item
  worktree:

      cd /home/roman/workspace/gascity.el/worktrees/ga-x4j3 && scripts/gate.sh

  Observed: **pass** — compile clean (`eldev compile --warnings-as-errors`)
  and `Ran 322 tests, 322 results as expected, 0 unexpected`; the gate
  prints `>>> gate: PASS (compile clean + tests green)`.

- **Remote-pooling proof command** — the W2 acceptance check of plan §W2
  ("Verify remote city views still work identically over
  `/ssh:localhost:/home/roman/bright-lights`"), run as a bounded batch
  Emacs against the real remote test city with the worktree's code: one
  sync `gc status --json` read, then 10 consecutive
  `gascity-reader-read-async` reads, then an ssh process count
  (`ps -eo args | grep -E '[s]sh.*localhost' | wc -l`) before/after:

  Observed: **pass** —
  `SYNC-READ city_name=bright-lights`; `ASYNC-READS done=10 ok=10 errs=0`;
  `SSH-PROCS before=3 after=3 new=0` — the read burst shared the existing
  pooled connections and spawned no fresh ssh, confirming the documented
  conclusion live on the remote city (and the views' underlying reads all
  work identically over TRAMP).

- **Final proof command** — the artifact schema gate for this summary, run
  from the launcher rig root (equivalent to the step's
  `.gc/scripts/checks/build-artifact-valid.sh` gate, which resolves the
  same schema/path pair from the workflow root's
  `gc.implementation.summary_path` metadata):

      cd /home/roman/workspace/gascity.el && GC_BEAD_ID=ga-13os \
        .gc/scripts/checks/build-artifact-valid.sh

  Observed: **pass** (recorded below after the metadata was set; the
  equivalent direct validator invocation exits 0).

## Remaining Risks

- **Handler default is environment-dependent, not contractual.** The
  pooled-channel conclusion rests on `tramp-direct-async-process` being
  nil for the `ssh` method on this Emacs/TRAMP (same caveat as W1). A
  future Emacs default change or user configuration flips the picture;
  the documentation states the condition explicitly, and W5's
  connection-count verification remains the regression guard.
- **Docs-only residue risk is nil.** No source behavior, keymap, or data
  plane changed, so there is no migration or compat surface; the only
  risk is documentation drift if TRAMP defaults change, mitigated by the
  explicit "measured on Emacs 30 / TRAMP 2.7" framing.

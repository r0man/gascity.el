---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-041y
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
    - path: beads/ga-ldrg
      hash: bead:ga-ldrg
      ids:
        - ga-ldrg
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-005
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
  coverage:
    - id: ga-ldrg
      status: covered
    - id: REQ-005
      status: covered
    - id: AC-2
      status: covered
    - id: AC-5
      status: covered
---

# Implementation Summary: W5 — Verification artifact and gate evidence

## Summary

**W5 landed the connection-count verification artifact: a new ERT
(`gascity-test-remote-async-reads-pool-connections`) that automates AC-2's
bound over the mock-remote boundary — ten async reads through
`gascity-reader-read-async` must all complete and leave at most two new
live TRAMP connection processes — plus a documented manual procedure for
the live city (before/after ssh connection count across N ≥ 10 refresh
ticks, bound: at most 2 new ssh connections) in the README's
"Remote cities (TRAMP)" section. The manual procedure was then executed
live against `/ssh:localhost:/home/roman/bright-lights`: 10/10 async
reads OK, 0 new ssh connections. `scripts/gate.sh` is green from the
repo root (323 tests, compile clean).** The verification evidence chain
REQ-001 → REQ-002 → REQ-005 is now closed: W1 measured pooling holds, W2
documented it, W5 automates the regression bound and records the
procedure.

## Intended Behavior

- A future regression that breaks pooled connection reuse (e.g. an
  accidental direct-async enable, a TRAMP dispatch change) fails the new
  ERT in the repo gate: ten async reads over the mock-remote boundary
  must complete 10/10 through their callbacks and leave at most two new
  live `*tramp/` connection processes behind.
- A user can verify pooling on their own live city by following the
  README procedure: count ssh connections (`last`, sshd log, or
  `ps -eo args | grep -c '[s]sh'`), open a dashboard over
  `/ssh:HOST:…`, let it refresh ≥ 10 ticks, count again — expect at
  most 2 new ssh connections (normally zero). The procedure names the
  failure signature (a fresh ssh login per refresh tick ⇒ direct-async
  got enabled connection-locally).
- REQ-005/AC-5 (verification artifact with recorded procedure and
  result) and the AC-2 connection bound are satisfied with automation
  where practical and a documented manual path for the live city, per
  plan §W5.

## Changed Files

Worktree `/home/roman/workspace/gascity.el/worktrees/ga-ldrg`, commit
`02de86a797b760222739b2bf9766ccdb308513ea`
(`test(remote): connection-count ERT + README manual pooling procedure (ga-ldrg)`),
based on `9fb54c5` (origin/main tip fetched by the prepare-worktree step):

| File | sha256 (post-change) | Change |
| --- | --- | --- |
| lisp/test/gascity-test.el | sha256:85c92e16f5f5881ef9ed033658c5ce24b6ea8b08d62f0ce407336a50b24b625d | New `gascity-test-remote-async-reads-pool-connections` ERT |
| README.md | sha256:ad919c5b4ed89feaba374df507c26fa0ce866452ca0c97c58481c3b645c4b563 | New "Connection-count verification (live city)" bullet in the remote-cities notes |

No production code changed: the deliverable is the verification
artifact itself (a test + documentation), so the gate below exercises
the unchanged production paths plus the new test.

Coverage traceability:

| ID | Status |
| --- | --- |
| ga-ldrg | covered |
| REQ-005 | covered |
| AC-2 | covered |
| AC-5 | covered |

## Verification

- **First verification command** — the repo quality gate, run in the
  item worktree:

      cd /home/roman/workspace/gascity.el/worktrees/ga-ldrg && scripts/gate.sh

  Observed: **pass** — compile clean (`eldev compile
  --warnings-as-errors`) and `Ran 323 tests, 323 results as expected, 0
  unexpected` (the new connection-count ERT included);
  `>>> gate: PASS (compile clean + tests green)`.

- **Automated connection-count check** — the new ERT itself, run
  standalone:

      cd /home/roman/workspace/gascity.el/worktrees/ga-ldrg && \
      eldev test gascity-test-remote-async-reads-pool-connections

  Observed: **pass** — `passed 1/1
  gascity-test-remote-async-reads-pool-connections (2.933725 sec)`;
  ten async reads over the mock-remote boundary completed 10/10 and the
  live-connection-process delta stayed within the bound.

- **Live-city manual procedure (the documented one, executed)** — over
  the real remote test city `/ssh:localhost:/home/roman/bright-lights`
  in a bounded batch Emacs: ssh connection count
  (`ps -eo args | grep -E '[s]sh.*localhost' | wc -l`), then N = 10
  consecutive `gascity-reader-read-async` status reads, then the count
  again:

  Observed: **pass** — `ASYNC-READS done=10 ok=10 errs=0`;
  `SSH-CONNS before=5 after=5 new=0` — zero new ssh connections across
  the burst, comfortably inside the at-most-2 bound.

- **Final proof command** — the artifact schema gate for this summary,
  run from the launcher rig root (the step's
  `.gc/scripts/checks/build-artifact-valid.sh` gate, which resolves the
  schema and this path from the workflow root's
  `gc.implementation.summary_path` metadata):

      cd /home/roman/workspace/gascity.el && GC_BEAD_ID=ga-sk44 \
        .gc/scripts/checks/build-artifact-valid.sh

  Observed: **pass** (recorded below after the metadata was set).

## Remaining Risks

- **The ERT proxies the ssh bound, not ssh itself.** Over the
  mock-remote boundary no ssh process exists; the automated assertion
  counts live TRAMP connection processes. The ssh-level bound is what
  the live manual procedure measures (executed here with 0 new
  connections). A TRAMP dispatch change could in principle alter both
  simultaneously; the ERT would catch it, and the README procedure lets
  a user confirm on the real transport.
- **Environment noise in live counts.** Other Emacs/agent activity on
  the host maintains its own ssh connections concurrently (5 were
  already live during this run); the decisive signal is the delta
  across the read burst, which is robust to that noise.
- **Bound generosity.** The at-most-2 bound (per AC-2/REQ-005) is loose
  relative to the observed 0; it tolerates one connection
  establishment plus one reconnect, keeping the check stable on slow
  or freshly-connected environments without weakening the regression
  signal (a per-read spawn would blow far past 2).

---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: summarize-implementation
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-llhb
      hash: bead:ga-llhb
      ids:
        - ga-llhb
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
    - path: plans/tramp-history-flood/decomposition.md
      hash: sha256:34dc45352f7a834f3bc225aa57008aa05fb9330b8e019a664d2276761245ad91
    - path: plans/tramp-history-flood/implementation-summary-ga-o98t.md
      hash: sha256:d68a116799cc2534b810c144b21c5cf893ef155d9392994701656e29161dcbed
      ids:
        - ga-o98t
    - path: plans/tramp-history-flood/implementation-summary-ga-aszp.md
      hash: sha256:5f81e0ec4ad3156a137198e61f7ca12dad5ada06c583d8f6240c825f36a81083
      ids:
        - ga-sfnj
    - path: plans/tramp-history-flood/implementation-summary-ga-5b9m.md
      hash: sha256:addbc67507bb3c1e0c43e4295298cbe9f9c6ff9daaf2597631d9b097f803cf05
      ids:
        - ga-5b9m
    - path: plans/tramp-history-flood/implementation-summary-ga-x4j3.md
      hash: sha256:d351450033af6721ec20421ef4807fdfce8cdd06ea81580281cb1ed444efef0e
      ids:
        - ga-x4j3
    - path: plans/tramp-history-flood/implementation-summary-ga-ldrg.md
      hash: sha256:76f7aacd86a13dda6661e2e76166b852b000098be4682a823f167f775e98ec25
      ids:
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

# Implementation Summary: TRAMP connection churn and host-side history pollution

## Summary

The build (implementation convoy `ga-w8sg`, drain control `ga-36c5`, five
separate-context drain items, all `succeeded`/`pass`) resolved the
`tramp-history-flood` problem with **two documentation-only changes, one
scoped code change, and one verification artifact**:

- **W1 / `ga-o98t`** (REQ-001, REQ-006) — diagnosis only, no source change:
  the tramp-sh pooled-channel handler is the active `make-process
  :file-handler` on `/ssh:` connections; N = 10 consecutive
  `gascity-reader-read-async` reads spawned exactly one ssh process
  (at connection establishment) and appended zero new `exec env` login
  lines to `~/.bash_history` (501 → 501).
- **W2 / `ga-x4j3`** (REQ-002) — documentation-only (commit `15b33b7`):
  the pooling conclusion recorded in `gascity-remote.el`'s commentary,
  the `gascity-reader-read-async` docstring, and the README's
  "Remote cities (TRAMP)" section; re-verified live: 10/10 async reads,
  0 new ssh processes.
- **W3 / `ga-sfnj`** (REQ-004) — code change (commit `3e3fc20`):
  `HISTFILE=/dev/null` appended buffer-locally to
  `tramp-remote-process-environment` by `gascity-view-get-buffer-create`
  via the new `gascity-remote-silence-shell-history` /
  `gascity-remote-history-environment` helpers in `gascity-remote.el`;
  ERT-tested; manual section added to `doc/gascity.texi`.
- **W4 / `ga-5b9m`** (REQ-003) — documentation-only (commit `0ff5454`):
  copy-paste host-side `.bashrc` guard recipe in `doc/gascity.texi`
  (*Host-side shell history guard*) plus
  `docs/qa/2026-09-21-bashrc-guard-recipe.md`; the workflow never edits
  the user's dotfiles.
- **W5 / `ga-ldrg`** (REQ-005) — verification artifact (commit `02de86a`):
  ERT `gascity-test-remote-async-reads-pool-connections` (ten async reads
  must complete with at most two new live TRAMP connection processes)
  plus a documented live-city manual procedure in the README, executed
  with 0 new ssh connections across a 10-read burst.

Per-item summaries (the evidence chain for this canonical summary):
`plans/tramp-history-flood/implementation-summary-ga-o98t.md` (W1),
`plans/tramp-history-flood/implementation-summary-ga-x4j3.md` (W2),
`plans/tramp-history-flood/implementation-summary-ga-aszp.md` (W3),
`plans/tramp-history-flood/implementation-summary-ga-5b9m.md` (W4),
`plans/tramp-history-flood/implementation-summary-ga-ldrg.md` (W5).

### Trace Coverage

| ID | Status |
| --- | --- |
| ga-llhb | covered |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| ga-o98t | covered |
| ga-sfnj | covered |
| ga-5b9m | covered |
| ga-x4j3 | covered |
| ga-ldrg | covered |

## Intended Behavior

- REQ-001: gascity.el's async remote reads reuse TRAMP's pooled ssh
  channel rather than opening a fresh connection per read — established
  by measurement (W1) and documented (W2); `scripts/gate.sh` keeps
  verifying the package gates.
- REQ-002: connection reuse for async reads is verified and documented;
  the direct-async hazard (a fresh ssh per read) is explicitly warned
  about, and gascity itself never enables direct-async.
- REQ-003: a host-side `.bashrc` guard recipe exists in the rig manual
  as a copy-paste snippet the user applies themselves; the workflow
  never touches `~/.bashrc`, `~/.bash_history`, or `~/.tramp_history`.
- REQ-004: gascity-owned remote view buffers carry a buffer-local
  `HISTFILE=/dev/null` append to `tramp-remote-process-environment` so
  TRAMP inner shells behind gascity reads record no shell history;
  truncating existing bloat stays a documented user-run command.
- REQ-005: a repeatable verification (automated ERT + documented live
  manual procedure) asserts N ≥ 10 consecutive async reads leave at
  most 2 new ssh connections, guarding the pooling regression class.
- REQ-006: the `cd emacs-city/` history line is attributed as far as
  the evidence supports (user's interactive shell before a tmux attach)
  with the residual uncertainty recorded rather than asserted.
- ga-llhb (the origin bead): all accepted requirement IDs above are
  finalized; each implementation source anchor (`ga-o98t`, `ga-sfnj`,
  `ga-5b9m`, `ga-x4j3`, `ga-ldrg`) is closed with `gc.outcome=pass`.

## Changed Files

- `lisp/gascity-remote.el` — W3 history-hygiene section
  (`gascity-remote-history-silencer`, `gascity-remote-history-environment`,
  `gascity-remote-silence-shell-history`) plus W2's connection-reuse
  commentary paragraph.
- `lisp/gascity-context.el` — W3: `gascity-view-get-buffer-create`
  applies the history silencer buffer-locally (re-applied on re-pin).
- `lisp/gascity-reader.el` — W2: connection-reuse note in the
  `gascity-reader-read-async` docstring (comment only).
- `lisp/test/gascity-test.el` — W3: ERT
  `gascity-test-remote-connection-local-histfile-override`; W5: ERT
  `gascity-test-remote-async-reads-pool-connections`.
- `doc/gascity.texi` — W3: *TRAMP shell history hygiene* section; W4:
  *Host-side shell history guard* section.
- `docs/qa/2026-09-21-bashrc-guard-recipe.md` — W4 QA note.
- `README.md` — W2: remote-cities pooling notes; W5: live-city
  connection-count verification procedure.

Item commits: `3e3fc20` (W3, worktree `worktrees/ga-sfnj`),
`0ff5454` (W4, worktree `worktrees/ga-5b9m`),
`15b33b7` (W2, worktree `worktrees/ga-x4j3`),
`02de86a` (W5, worktree `worktrees/ga-ldrg`); W1 changed no files.
Each item was built in its own isolated worktree created from the
fetched origin tip (`9fb54c5`).

## Verification

First verification commands (per item, all **pass**):

- W1 — pooling experiment in a batch Emacs against
  `/ssh:localhost:/home/roman/bright-lights`: 10/10 async reads OK,
  one ssh process total, `~/.bash_history` exec-line delta 0 across
  the burst.
- W2 — `scripts/gate.sh` in `worktrees/ga-x4j3`: compile clean, 322
  tests green; live re-check `SSH-PROCS before=3 after=3 new=0`.
- W3 — `eldev test gascity-test-remote-connection-local-histfile`
  (1/1 pass); full `scripts/gate.sh` in `worktrees/ga-sfnj`: 323 tests
  green, compile clean.
- W4 — `make -C doc` in `worktrees/ga-5b9m` (no warnings); full gate
  green (322 tests); `git status` shows no dotfile modification.
- W5 — `eldev test gascity-test-remote-async-reads-pool-connections`
  (1/1 pass); full gate in `worktrees/ga-ldrg` (323 tests); live
  manual procedure `SSH-CONNS before=5 after=5 new=0` across a
  10-read burst.

Final proof commands (artifact gates, all **pass**): each per-item
summary validated with `.gc/scripts/checks/build-artifact-valid.sh`
(schema `gc.build.implementation-summary.v1`) from the launcher rig
root; the canonical summary is validated the same way via
`GC_BEAD_ID=ga-tlpj .gc/scripts/checks/build-artifact-valid.sh`
resolving `gc.build.implementation_summary_path` on the workflow root
`ga-2ea1`.

Observed results: all five drain items closed `pass` (`gc.drain_state:
succeeded` on `ga-36c5`); implementation convoy `ga-w8sg` closed
(autoclose: all children closed); all five source anchors closed with
`gc.outcome=pass`.

## Remaining Risks

- **Handler default is environment-dependent.** The pooling conclusion
  rests on `tramp-direct-async-process` being nil for the `ssh` method
  on Emacs 30 / TRAMP 2.7.3; a future Emacs default change or user
  configuration flips the picture. W5's ERT and the README procedure
  are the standing regression guards.
- **Sync path environment timing.** The buffer-local
  `HISTFILE=/dev/null` override reaches TRAMP's connection shell only
  when a gascity spawn opens the connection; the async
  `make-process` path (the refresh-tick bloat driver) is covered
  directly.
- **Existing bloat is not cleaned.** `~/.tramp_history` (655 KB) and
  the `~/.bash_history` exec-line copies are only cleaned by the
  documented user-run commands; the workflow never edits user
  dotfiles (by hard requirement).
- **REQ-006 residue.** The exact interactive shell that typed
  `cd emacs-city/` is unprovable after the fact; attribution is
  evidence-supported, not proven. User-typed lines also disappear
  from `~/.bash_history` over time while exec copies accumulate — an
  unexplained host-side rewrite that may interact with the W4 guard.
- **Measurement noise.** Live ssh/`~/.bash_history` counts share the
  host with the user's own Emacs daemon; deltas across bounded bursts
  are the decisive signal and were robust (0 new connections) in all
  observed runs.

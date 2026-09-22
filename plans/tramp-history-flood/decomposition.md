---
schema: gc.build.decomposition.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: decompose
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
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
      ids:
        - ga-llhb
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

# Decomposition: Reduce TRAMP connection churn and neutralize host-side history pollution

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

The approved requirements and implementation plan decompose into five work
items mirroring the plan's W1–W5. W1 diagnoses whether gascity.el's async
remote reads open a fresh ssh login per refresh tick (and attributes the
stray `cd emacs-city/` history line); W2 fixes or documents connection reuse
in `gascity-remote.el`/`gascity-reader.el` informed by W1; W3 adds a scoped
connection-local `HISTFILE=/dev/null` override for TRAMP inner shells; W4
ships the host-side `~/.bashrc` guard recipe as documentation only; W5
produces the connection-count verification and implementation summary
evidence. Sequencing: W1 → W2 → W3, W4 (independent) → W5, per the plan's
"Sequencing" section. Every work item cites its plan section and REQ
traceability in its description.

## Selected Downstream Formulas

- `implement` (implementation stage) drains the implementation convoy
  recorded in `gc.input_convoy_id` / `gc.build.implementation_convoy_id` on
  the workflow root bead.
- Per-item execution uses `implementation_item_formula = do-work-item`
  targeting `gc.implementation-worker`, as configured on the workflow root.
- `review` (`code_review_formula = review`) and the publish/final-report
  stage consume the implementation summary accumulated by W5.

## Implementation Convoy

A new implementation convoy `tramp-history-flood-impl` holds exactly the five
work-item beads created by this decomposition (GA-W1-POOLING, GA-W2-REUSE,
GA-W3-HISTFILE, GA-W4-BASHRC-GUARD, GA-W5-VERIFY). The source/launch convoy
`ga-xyem` (`gc.var.convoy_id`) is **not** reused. The convoy id is recorded
on the workflow root as `gc.input_convoy_id` and
`gc.build.implementation_convoy_id`.

## Work Items

Each work item is an open bead with `gc.root_bead_id=ga-2ea1`, tracked in the
implementation convoy. Dependencies encode the plan's sequencing.

| Bead | Plan section | Title | REQ traceability | Depends on |
| ---- | ------------ | ----- | ---------------- | ---------- |
| (created below, id recorded in convoy) | W1 | Pooling diagnosis for async remote reads | REQ-001, REQ-006, ga-llhb | — |
| (created below) | W2 | Fix or document TRAMP connection reuse | REQ-002, ga-llhb | W1 |
| (created below) | W3 | `HISTFILE=/dev/null` for TRAMP inner shells | REQ-004, ga-llhb | — |
| (created below) | W4 | Host-side `.bashrc` guard recipe (docs only) | REQ-003, ga-llhb | — |
| (created below) | W5 | Verification artifact and gate evidence | REQ-005, ga-llhb | W2, W3, W4 |

Constraints carried into every work item (from the plan's Non-Goals):
never edit user dotfiles (`~/.bashrc`, `~/.tramp_history`,
`~/.bash_history`); no changes outside gascity.el's remote/read path; no
reimplementation of TRAMP pooling; `scripts/gate.sh` stays green; remote
changes are verified against `/ssh:localhost:/home/roman/bright-lights`
per the repo's TRAMP protocol.

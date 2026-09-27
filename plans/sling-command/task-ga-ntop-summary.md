---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-bv0z
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
    - path: beads/ga-ntop
      hash: bead:ga-ntop
      ids:
        - REQ-005
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: lisp/gascity-action.el
      hash: sha256:5b653e9316674f9b261bda2b08fa1b31621fd65d80c6ea036f7a86ea377a1108
    - path: lisp/gascity-domain.el
      hash: sha256:2e31b81b10dceffb83a2b9d25933c129e3e19738d5036f5e73d5df29e5d01688
    - path: lisp/test/gascity-sling-test.el
      hash: sha256:beda1049211f245ee399f9bf049cc7f3d140e00fad1f6d76f61911e0d394e762
    - path: lisp/test/gascity-test-helpers.el
      hash: sha256:8fba0b87dfd32c98ed0ed75349a429d7cd11e039f3285b1b9837293af54ba4a9
    - path: lisp/test/gascity-test.el
      hash: sha256:b21bb81f65817024013c90b8307a38929279c712a10793838d2bc3343ca04f75
    - path: doc/gascity.texi
      hash: sha256:6ef001b52dc1dbdabf4eef2a41a7c799844b032c02daadd3bc601b3d73fb095a
  coverage:
    - id: REQ-005
      status: covered
---

# Implementation summary — WI-3: derived Who default (ga-ntop)

## Summary

Work item WI-3 of the sling command redesign is implemented in
worktree `worktrees/ga-ntop`, commit `9d2acbf15437`
("feat(sling): derived Who default (ga-ntop)"), on top of origin/main
`69eed1c`.  `gascity-sling--derive-target` now answers the sling
menu's Who from cached data alone, in the design's order: (1) the work
bead's rig `default_sling_target` / `default_sling_targets` — read
from the rig memo gascity already holds, fail-soft when the rig
reports none (gc does not emit the field today, recorded under Open
Implementation Details); (2) the per-(city, formula) target memory —
the new `gascity-sling--target-memory` alist, recorded on every real
launch and surviving launches; (3) the implementation-worker
convention — the roster's exactly one rig-scoped
`gc.implementation-worker` when that is unambiguous.  `s` uses a
derived target without prompting; the header shows it with a
`(derived)` tag; the `T` picker's completing read is pre-seeded with
it (RET keeps it).  Only when nothing derives does `s` prompt.  The
derivation is pure over (scope, roster, memory) and reads only store
caches and the rig memo, so it never spawns gc on the render path
(D9).

## Intended Behavior

Per `plans/sling-command/implementation-plan.md` WI-3 and
`design.md` REQ-005:

- **Derivation order (REQ-005)**: `gascity-sling--derive-target`
  returns the first rule that answers, as `(:target NAME :source
  SOURCE)` with SOURCE one of `rig-default`, `memory`,
  `implementation-worker`; nil when no rule derives.  A target set in
  the scope (`-T`) wins at dispatch; the derivation never consults
  it.
- **Rule 1 — rig default**: the work bead's owning rig is resolved by
  the bead id's prefix against the rig memo (`gascity-rigs-cached`)
  alone — never a gc read; freeform work, a prefixless id, an unknown
  prefix or a cold memo give nil and the rule skips fail-soft.
  `default_sling_target` wins over the first of
  `default_sling_targets` (gc picks one of the list at random
  server-side; what the menu SHOWS must be deterministic).  The rig
  class grew the two decode slots.
- **Rule 2 — launch memory**: `gascity-sling--remember-target`
  records every real launch's target under `(city . formula)` in
  `gascity-sling--target-memory`; a plain sling records under
  FORMULA nil.  A hit is the same city and the same formula; another
  formula, another city or no entry is a miss.  Unlike the
  remembered menu state (`gascity-sling--remembered`, cleared after
  a launch) the memory survives launches.  A preview records
  nothing — only a real launch is a choice.
- **Rule 3 — the convention**: the roster is the configured agents
  of the cached `gc agent list` payload (live sessions carry
  instance suffixes and name no config); exactly one
  `<rig>/gc.implementation-worker` derives its name.  Two or more
  (one per rig) are ambiguous; a city-scoped worker never counts;
  duplicate entries of the same agent are one.  A cold or failed
  agent-list read is an empty roster — the rule skips fail-soft.
- **`s` uses it without prompting**: dispatch reads the scope's
  target, then the derivation, then prompts.  The arg just read
  (`Bead id or task text:`) is put into the scope before the
  derivation runs, so a bead id typed at the prompt still
  rig-defaults its target.
- **Header and `T`**: the header's Target field renders the derived
  target with a `(derived)` tag when only derivable (a `-T` set
  target renders bare); `T`'s completing read is seeded with the
  derived target as its initial input (RET keeps it).
- **Cache warming**: menu entry requests `gc agent list` through the
  store (async, TTL-gated) beside the formula caches, so the
  convention rule answers from memory shortly after entry; a cold
  session's first dispatch may still derive from rules 1–2 only —
  never a block, never a spawn on render.
- **Manual**: the fail-soft rig-default behavior and the derivation
  order are documented in the manual's Dispatch and lifecycle
  section (the plan's Open Implementation Details requirement).

## Changed Files

- `lisp/gascity-action.el` — the derived Who default: the
  `gascity-sling--target-memory` variable and its
  `--remember-target` / `--memory-target` accessors; the
  derivation (`--work`, `--work-rig`, `--rig-default-target`,
  `--implementation-worker-target`, `--derive-target`); the
  roster accessor (`--roster`, from the store's cached `gc agent
  list`) and the session-state gatherer (`--derived-target`); `s`
  dispatch using the derivation before prompting and recording the
  launch target; the header's `(derived)` tag; `T` seeded with the
  derived default; entry prefetching `gc agent list`; the
  `--read-session` DEFAULT argument.
- `lisp/gascity-domain.el` — `gascity-rig` slots
  `default-sling-target` and `default-sling-targets` (JSON keys
  `default_sling_target` / `default_sling_targets`), decoding nil
  today.
- `lisp/test/gascity-sling-test.el` — nine new tests: derivation
  precedence (all three rules and their order), rig-default
  fail-soft, the exactly-one ambiguity rule (two rig-scoped workers
  ambiguous, a city-scoped worker not counting, live-instance
  suffixes not counting, duplicates collapsed), memory hits and
  misses (same city + same formula hit; other formula, other city,
  no entry miss; a real launch records, a preview does not), the
  roster reading the cached `gc agent list` payload, `s` using the
  derived target without prompting, the preview showing it but
  recording nothing, the header's derived tag, and `T`'s seeded
  read.
- `lisp/test/gascity-test-helpers.el` — the per-test reset also
  clears `gascity-sling--target-memory` (session-wide table, must
  not leak between tests).
- `lisp/test/gascity-test.el` — the two existing
  `gascity-action--read-session` stubs updated to the new optional
  DEFAULT argument.
- `doc/gascity.texi` — the sling entry documents the derivation
  order, the fail-soft rig-default rule, the `(derived)` tag and
  the seeding of `T`.

## Coverage

| ID | Status |
| --- | --- |
| REQ-005 | covered |

## Verification

First verification command (from the worktree, the repo's standard
gate):

    scripts/gate.sh

observed: PASS — `eldev compile --warnings-as-errors` clean and the
full ERT suite green (675/675 tests passed, 2026-09-27 16:36) on the
implementation as inherited from the interrupted attempt, before the
final commit.

Final proof commands (from the worktree, after the manual update and
tidy, commit `9d2acbf15437`):

    scripts/gate.sh

observed: one run read 674/675 with an intermittent failure of
`gascity-test-agent-detail-follow-log-stderr-goes-with-it` (a known
flake — see Remaining Risks), which passed in isolation immediately
after (1/1 green); the repeated full gate read PASS — compile clean
and 675/675 tests green (2026-09-27 16:39).

## Remaining Risks

- **Sibling-wave seams**: WI-3 lands in a parallel drain whose base
  (origin/main `69eed1c`) does not yet carry the sibling waves.  The
  derivation's rule 1 decodes `default_sling_target(s)` that gc does
  not emit today, so in production the rig-default rule is dormant
  until gc grows the field — exactly the plan's Open Implementation
  Details disposition (fail-soft skip; rules 2–3 drive).  The `T`
  picker keeps session completion annotated as WI-2 built it — this
  item only seeds its initial input.  The one-sentence shape header
  and live footer are WI-1/WI-6 deliverables; the header line this
  item tags is the interim `:info` form.  Each seam is the sibling
  bead's named deliverable; the publish chain merges them in wave
  order.
- **Roster freshness**: the convention rule reads the store's cached
  `gc agent list` (TTL-gated, warmed on menu entry).  A
  configuration change mid-menu (worker removed) could derive a
  stale target; gc then routes the sling to a nonexistent agent and
  the failure surfaces in the echo area as today's dispatch error —
  no worse than a hand-typed stale target.
- **Known flaky tests** (not this item's defect, reproduced on the
  untouched base by the WI-4 summary too):
  `gascity-test-agent-detail-follow-log-stderr-goes-with-it` fails
  intermittently in full-gate runs and passes in isolation; the
  final gate run above was green.
- **E2E**: the interactive TRAMP acceptance (bright-lights) is
  WI-11's deliverable, not run here; the derivation's inputs and
  outputs are pinned by the mocked unit tests above.

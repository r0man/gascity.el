---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-9hg3t
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
    - path: beads/ga-uq5pl
      hash: "bead:ga-uq5pl"
      title: "Docs and manual QA: NEWS, manual section, tmux/TRAMP acceptance report"
      ids:
        - AC-5
        - REQ-016
        - REQ-017
    - path: plans/beads-eldoc-prefix/implementation-plan.md
      hash: "sha256:f32df57e032ad86e0ebe98c16f10cbd1c70be716a8ae4fd9f8b456288d42b710"
      title: "Implementation plan, section H item 5 (docs and QA)"
    - path: plans/beads-eldoc-prefix/requirements.md
      hash: "sha256:e27383a7f11d968e0129e6bc870ce7de66da5d48db50f8ae9f48e022c3bff7f4"
      title: "Requirements REQ-016, REQ-017 and acceptance AC-5"
    - path: NEWS.md
      hash: "sha256:2c08fe577315a986aae19097ec1f83a552d021fac4be981f5fcb9045164ef9f0"
      title: "Unreleased entry: per-prefix bead-id resolution and its limits"
    - path: doc/gascity.texi
      hash: "sha256:ab3d42f60c4dbeebe5ff16dfdc5bb6d38b9d9e44ee40cb4276c913c31b89d757"
      title: "\"Bead ids in any buffer\" under Objects at point"
    - path: docs/qa/2026-11-06-beads-eldoc-prefix.md
      hash: "sha256:0f447bf33a2229df9b1f4f7405230b594317a21a961722ed44aeed105d667987"
      title: "Live acceptance report (partial: merge boundary recorded)"
  coverage:
    - id: AC-5
      status: covered
    - id: REQ-016
      status: covered
    - id: REQ-017
      status: covered
---

# Implementation Summary: docs and manual QA for bead-id eldoc (item 5)

| ID | Status |
| --- | --- |
| AC-5 | covered |
| REQ-016 | covered |
| REQ-017 | covered |

## Summary

This item documents the per-prefix bead-id eldoc work and records the live
acceptance pass.  Three deliverables:

- `NEWS.md` (Unreleased) announces that `beads-eldoc-mode` resolves a bead id
  against the store its prefix names — the city's store for `ec-…`, the rig's
  repository for `ga-…`/`be-…` — per id rather than per buffer, in the cockpit,
  lists and detail views, a mayor transcript, a worktree-pinned attach and
  mail.  It names the limits the plan requires: the feature needs
  `beads-eldoc-mode`; a remote city's host must be connected (an offline host
  is silent and the view header already says so); and the first hover in a
  cold buffer may wait for the background prefix read.  It also states the
  cold-buffer guarantee: no id is admitted until the map lands, so a valid id
  never shows another store's "no issues found" and unrelated hyphenated words
  start no lookup.
- `doc/gascity.texi` gains the `Bead ids in any buffer` subsection under
  **Objects at point** (Buffers and Navigation), entered from that section's
  menu.  It covers the city/rig prefix mapping and the per-id rule, the cold
  deny-all start and in-place heal, the refresh sources (live `rig` events,
  rig actions, `gascity-beads-eldoc-map-ttl`, `g` versus
  `M-x gascity-context-clear-cache`), the allowlist's effect on log noise, the
  `C-c b` binding, mouse hover, the no-city no-op, the beads.el limits, and
  the deliberate synchronous `gc` fallback for writes.  `make -C doc` builds
  `gascity.info` with no makeinfo warnings.
- `docs/qa/2026-11-06-beads-eldoc-prefix.md` records the tmux/TRAMP pass
  against `emacs-city` and `/ssh:localhost:~/bright-lights`.

The QA half is **partial by construction**: the four implementation items were
uncommitted sibling worktrees at pass time, so the live checks ran on a
QA-only composite (documented in the report) and the `C-c b` keys, the live
agent transcript and mouse hover are recorded as deferred with reasons.  The
four documented code items must be merged before the final interactive pass;
this item's docs describe the approved behavior and make no claim that the
merge is done.

Module commentary was not duplicated here: the three statements the plan asks
for (single resolution path, cold deny-all rationale, write-path exception)
belong to the module the implementation items add, and this docs worktree does
not contain that module.  The manual carries the operator-facing equivalent of
all three.

## Intended Behavior

- A reader of the manual or NEWS learns, without reading source: which store
  owns an id (its prefix), that resolution is per id in every gascity buffer,
  what a cold buffer does, how the map refreshes, and why an unconnected
  remote host is silent.
- The manual's option references stay valid: the three new options are
  documented by item 1's `@defopt` entries; this section refers to them with
  `@code{}` only, so a docs-only tree (no module) still builds and has no
  dangling definitions.
- The QA report states exactly which acceptance criteria were observed, with
  the ids, buffer names, echo text and connection counts, and which were not,
  with the reason — never a silent skip and never a claim of a merged-tree
  pass.
- `make -C doc` and `scripts/gate.sh` are clean in this worktree, so the docs
  commit is landable on its own.

## Changed Files

- `NEWS.md` — new Unreleased section, `Bead ids resolve by their prefix in
  every gascity buffer` (behavior, refresh, limits, cold-buffer guarantee).
- `doc/gascity.texi` — the `Bead ids in any buffer` node/subsection plus its
  entry in the `Objects at point` menu; new `@cindex bead ids, eldoc`,
  `@cindex cold start, bead ids`, `@kindex C-c b` and
  `@fnindex gascity-bead-show-at-point` entries.
- `docs/qa/2026-11-06-beads-eldoc-prefix.md` — the live acceptance report:
  scope and composite provenance, method, per-AC evidence with exact ids and
  echo text, blocked items and reasons, gate table, verdict.
- `plans/beads-eldoc-prefix/build/implementation-summary-ga-uq5pl.md` — this
  artifact.

## Verification

First verification command — the manual build, the deliverable that can fail
on a dangling node/menu or an unindexed definition:

```
$ make -C doc
...
gascity.texi:966: warning: node `Bead ids in any buffer' unreferenced   # first run
```

Observed **FAIL** on the first run (the new subsection's node was not in a
menu).  Added the `Objects at point` menu entry; the rebuild is clean:

```
$ make -C doc
... -o gascity.info gascity.texi
$ echo $?
0
```

Final proof command — the repository quality gate on the docs tree:

```
$ scripts/gate.sh
>>> gate: make (byte-compile, warnings as errors)
>>> gate: make check (ERT)
Ran 998 tests, 998 results as expected, 0 unexpected
>>> gate: PASS (compile clean + tests green)
```

Observed **PASS**.  `scripts/lint.sh` was also run: checkdoc clean; package-lint
is not installed in this environment and the script skips it (CI installs it).

Live QA (composite tree; full evidence in the report):

- local cockpit `*gascity: emacs-city@/home/roman/emacs-city/*`, prefixes
  `("ec" "be" "ga")`, hover `ga-4hdav` → `ga-4hdav [closed]: do-work`
  (gascity.el store);
- worktree-captured buffer resolves `ec-`/`ga-` after the async fill;
- cold buffer deny-all `("")` then warm in place;
- `post-command` and `zz-` rejected; misspelled `ga-zzzzz` looked up once,
  then served from the negative cache;
- remote `/ssh:localhost:/home/roman/bright-lights`, prefixes `("bl" "hw")`,
  hover `bl-bdj` → `bl-bdj [open]: Formula v2 step targets
  (gc.run-operator) fail to resolve from HQ scope: 'unknown formulas v2
  target'`, TRAMP connections 1 → 1.

## Remaining Risks

- **The QA pass is against a composite, not a merge.**  The `C-c b` binding
  (item 3), the live agent transcript, and mouse hover remain unverified until
  items 1–4 are merged; the report records them as deferred with reasons, and
  the final merged-tree pass must re-run them.
- **Docs describe approved behavior ahead of the merge.**  If an implementation
  item's final review changes the refresh wording (in particular what `g`
  does to the prefix map), the manual paragraph and NEWS entry must be updated
  in the same merge; `g` is documented as re-reading the view, with the map
  following its own invalidation cycle, which matches item 4's implementation.
- **New option references** rely on item 1's `@defopt` block landing together
  with (or before) this section; the section uses `@code{}` so a docs-only
  tree builds, but the reference entries are item 1's.
- **Composite gate failures** (19) are merge-shape mismatches between the four
  unmerged item trees, not attributable to this docs commit; they are recorded
  in the report so the Refinery/merged-tree pass is not confused by them.

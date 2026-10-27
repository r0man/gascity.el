---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-qrnxj
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
    - path: beads/ga-ihy1d
      hash: bead:ga-ihy1d
      title: "B7 source anchor: gascity.el docs, key registry, design note and manual for beads sling"
      ids:
        - REQ-010
    - path: plans/beads-sling-integration/implementation-plan.md
      hash: sha256:9172aff2d78b0a6522bbeb911fc1edd6a4442ba72ad17b67399387dd3253d313
      title: "Approved plan §B7: ownership, key registry, design note and manual"
    - path: docs/cross-repo-ownership.md
      hash: sha256:e613c3254f720e5d01ee49bb316824fd9b4d2ed68c597d167e35f57b06a91f28
      title: "Changed: hotspot 7 update, hotspot 8 and the registration-seam section"
    - path: docs/key-registry.md
      hash: sha256:d0851ed3e0ae6ef4b04863bc56df1202d9e32a2b5e4e3821d2543eb81d0b9b0a
      title: "Changed: delegated beads.el S, [City] group and additive V action"
    - path: docs/DESIGN-write-actions.md
      hash: sha256:cc7e564aa0bb9f76c1205950233caf794c32e0f57f0df0fbb29a27fb52eb8833
      title: "Changed: §10 cross-package line pointing at the delegated S"
    - path: doc/gascity.texi
      hash: sha256:4cdaef1d8541616ee5e55978430cd7d3f2555ba8597c12719797d3a46c9e54cd
      title: "Changed: beads-delegation passage and the new Slinging from beads section"
  coverage:
    - id: REQ-010
      status: covered
---

# Implementation Summary — B7: gascity.el docs, key registry, design note and manual (ga-ihy1d)

## Summary

B7 documents the downstream `gascity-beads-sling` registration added by B1–B6
against its actual code: the six beads.el seams, the qualified target naming,
the three pinned `gc sling` argv shapes, the advisory validators, the `[City]`
dispatch group, the additive action entry, the post-mutation refresh and the
cold-start (F4) limitation.  Four documents change; no Lisp source changes.

- `docs/cross-repo-ownership.md` — hotspot 7 is updated (the `gc sling`
  transient stays in gascity; beads.el owns the bead-view entry point) and
  hotspot 8 is added for the new module.  A new section,
  "What `gascity-beads-sling` registers", lists the six seams, the
  `rig/agent` versus bare-city target naming, the plain/`on`/`formula` argv,
  the `:shape`-drives-`--on`-versus-`--formula` rule, why nothing duplicates
  beads.el rendering, and the cold-start limitation.  The verification section
  names `gascity-beads-sling-test`.
- `docs/key-registry.md` — records that in beads.el's own views `S` is
  `beads-sling-for-issue`; gascity contributes no competing binding, only the
  `[City]` menu group and the additive `V` action.
- `docs/DESIGN-write-actions.md` §10 — one paragraph pointing at the delegated
  `S`, the `[City]` group and the unchanged gascity-side `S`.
- `doc/gascity.texi` — the beads-delegation passage now says the dependency is
  one-way and loading gascity extends beads.el's sling; a new
  `Slinging from beads` section under Sling and Dispatch documents the
  `S` bindings (including the list/agent-list exclusions), the `gc` Who
  targets, the `[City]` group, the `V` action, the refresh, the formula/`--var`
  passthrough, the limits (no new CLI behaviour; beads.el owns the bead UI) and
  the F4 cold-start note (open a gascity view or set `gascity-context-city`).

| ID | Status |
| --- | --- |
| REQ-010 | covered |

## Intended Behavior

- A gascity user reading the ownership record sees every bead-sling seam, the
  target naming scheme and the exact argv shapes, and can tell which side owns
  rendering (beads.el) versus `gc` dispatch (gascity.el).
- A beads.el user reading the key registry knows `S` in a beads view is
  beads.el's issue-seeded transient, that gascity adds no binding there, and
  that the `[City]` group and `V` action are additive.
- A manual reader finds "Slinging from beads" in the Sling and Dispatch
  chapter: how to sling an issue from a beads buffer, what the `gc` targets and
  backend do, how formula variables pass through, and why the Who picker may
  show only local targets in a fresh Emacs.

## Changed Files

| File | Change |
| --- | --- |
| `docs/cross-repo-ownership.md` | Hotspot 7 rewritten, hotspot 8 added, registration-seam section and verification note |
| `docs/key-registry.md` | Delegated beads.el `S`, `[City]` group, additive `V`, gascity-side `S` unchanged |
| `docs/DESIGN-write-actions.md` | §10 paragraph on the delegated `S` and `[City]` group |
| `doc/gascity.texi` | Beads-delegation passage extended; new `Slinging from beads` node and menu entry |

## Verification

| Command | Result |
| --- | --- |
| `scripts/gate.sh` (byte-compile warnings-as-errors + `make check`) | PASS — compile clean, 828/828 ERT |
| `scripts/lint.sh` (CI lint bar) | PASS — no warnings (package-lint not installed locally, as script reports) |
| `make -C doc info` (after `configure --with-beads-dir=$HOME/workspace/beads.el`) | PASS — `doc/gascity.info` rebuilt, makeinfo exit 0 |
| `GC_BEAD_ID=ga-c3al9 .gc/scripts/checks/build-artifact-valid.sh` | PASS — summary validates against `gc.build.implementation-summary.v1` |

The manual build is prose-only in this item and is not part of `scripts/gate.sh`;
it was run explicitly above and passed.  `make -C doc`'s default target builds
`info`, which is what was rebuilt; no HTML/PDF artifact is committed.

## Remaining Risks

- The documents describe the B1–B6 branches' implementation.  This worktree's
  branch (`beads-sling-b7`, based on `beads-sling-b6`) contains that code, but
  the docs commit has no code of its own; if a later B1–B6 review changes the
  seam list, target naming or argv, these four documents must change with it.
- The `[City]` group keys `E J K A Q` are documented as free in
  `beads-dispatch`; a beads.el menu change that takes one of them would need a
  cross-repo update.
- The F4 cold-start limitation is documented rather than fixed: a fresh Emacs
  with no gascity view and no `gascity-context-city` shows only local targets.
  The fix (a provider seam that receives bead/context) is follow-up work in
  beads.el, out of this slice.
- No screenshot was regenerated; the new manual section is prose only and the
  existing sling screenshots still show the gascity-side menu.

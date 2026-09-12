---
schema: gc.build.decomposition.v1
workflow:
  id: ga-c0e
  formula: build-from-requirements
methodology:
  pack: gascity
  name: decomposition-base
producer:
  formula: decomposition-base
  stage: decompose
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan (as revised by plan-review F-1) this decomposition translates into work items"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
        - AC-6
        - AC-7
        - AC-8
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
        - REQ-015
        - REQ-016
        - REQ-017
        - REQ-018
    - path: plans/formula-sling-ui/build/plan-review.md
      hash: sha256:aa5b4e6b891e4d293857d5f6b0579f88e6ea408412adf19aacc5694f286a2a76
      title: "Plan-review verdict consumed by this decomposition (F-1 changes_required, concrete fix specified)"
      ids:
        - F-1
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements the plan traces to (upstream-of-upstream, hash preserved)"
    - path: lisp/gascity-action.el
      hash: git:16c2d7b8a77baea264c762f93caef86d26591941
      title: "The current sling transient the work items rework (gascity-sling-dispatch, gascity-sling--read-vars)"
    - path: lisp/gascity-types.el
      hash: git:d4bd21c84ae09e55e7d9c7a2bf324c50b65b1c76
      title: "gascity-command-sling command class the work items extend with an --on slot"
    - path: docs/DESIGN-write-actions.md
      hash: git:cdae3a365a98f6ebff1ff025be2ff5e39a342317
      title: "Binding design the work items must hold (§5.2 sling, §10 key conventions)"
  coverage:
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
      status: covered
    - id: AC-7
      status: covered
    - id: AC-8
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
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-009
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
    - id: REQ-015
      status: covered
    - id: REQ-016
      status: covered
    - id: REQ-017
      status: covered
    - id: REQ-018
      status: covered
    - id: F-1
      status: covered
---

# Decomposition: Formula-aware sling UI for gascity.el

## Summary

This decomposition translates the approved implementation plan
(`plans/formula-sling-ui/build/implementation-plan.md`) into four
dependency-ordered, runnable implementation work items collected in the
implementation convoy `ga-x8m`. Each work item bead carries its own scope,
expected files, requirement traceability, and verification expectations so the
downstream implementation drain (`do-work` lifecycles, separate drain policy)
can run each unit without re-reading the plan.

**Plan-review disposition.** The plan-review verdict
(`plans/formula-sling-ui/build/plan-review.md`) is `changes_required` with
exactly one finding, F-1: the recipe preview MUST re-run
`gc formula show <name> --json` **with the currently-set `--var` values** and
render gc's substituted payload — no client-side `{{var}}` substitution. The
fix specified by the reviewer is incorporated directly into the work items
rather than deferred: the `gascity-command-formula-show` read class carries a
`:var` list slot (WI-1), and the preview suffix re-runs the read with the
collected infix values (WI-3). Every other plan element was verified sound by
the reviewer and is translated unchanged. Plan decisions D1 (recorded payload
shapes, no shipped `enum`/`pattern` vars, methodology-metadata fallback), D2
(`--formula` vs `--on` shape detection: drain-step metadata or a literal
`{{convoy_id}}` scan), and D3 (session-lifetime caches keyed by city
identity) are binding inputs to WI-1–WI-3.

**Decomposition methodology.** `decomposition-base` as selected by the
workflow (`gc.var.decomposition_formula=decomposition-base`): the plan's four
phases become four beads in dependency order, each independently runnable and
verifiable, with the plan-review fix folded in where it lands.

## Selected Downstream Formulas

- **Drain**: the workflow suffix `build-from-convoy-base` drains this convoy
  with the `do-work` formula, one full lifecycle per member
  (`gc.var.drain_policy=separate`, `implementation_formula=implement`,
  `implementation_item_formula=do-work-item`,
  `implementation_target=gc.implementation-worker`).
- **Implementation target**: `gc.implementation-worker` sessions claim ready
  work items and run them inside the rig `gascity.el` worktree; the item
  formula is `do-work-item` only if the policy changes to same-session.
- **Review**: code review after the drain is owned by the inherited
  `prepare-review` step of `build-from-convoy-base`
  (`gc.var.code_review_formula=review`, `review_mode=agent`); the convoy
  intentionally contains no review or workflow-control beads — only runnable
  implementation work.

## Implementation Convoy

- **Convoy ID: `ga-x8m`** ("formula-sling-ui implementation"), containing
  exactly the four work items below (`ga-dqm`, `ga-wxt`, `ga-udw`, `ga-4ef`)
  with a linear `blocks` chain WI-1 → WI-2 → WI-3 → WI-4.
- Verified **not** the original launch convoy (`ga-hg6`, "input convoy for
  ga-dcu") and not a workflow-control convoy: `ga-x8m` was created fresh by
  `gc convoy create` in this decomposition step and tracks only
  implementation beads.
- Recorded on workflow root `ga-c0e` as `gc.input_convoy_id=ga-x8m` (drain
  contract) and `gc.build.implementation_convoy_id=ga-x8m` (continuation
  reporting).

## Work Items

| ID | Title | Depends on | Requirements | Expected files |
| --- | --- | --- | --- | --- |
| ga-dqm | Formula plumbing: read command classes, formula domain classes, sling `--on` slot | — | REQ-003, REQ-012, REQ-013, REQ-014, REQ-016 | `lisp/gascity-types.el`, `lisp/gascity-domain.el`, `lisp/gascity-action.el`, `lisp/test/gascity-test.el` |
| ga-wxt | `gascity-formula.el` core: caches, catalog access, enum mapping, shape detection, validation, history | ga-dqm | REQ-002, REQ-003, REQ-005, REQ-009, REQ-010, REQ-011, REQ-013, REQ-014, REQ-016 | `lisp/gascity-formula.el` (new), `lisp/gascity.el`, `lisp/test/gascity-test.el` |
| ga-udw | Formula sling transient: picker, generated var infixes, recipe preview, wiring | ga-wxt | REQ-001, REQ-004, REQ-005, REQ-006, REQ-007, REQ-008, REQ-009, REQ-012, REQ-013, REQ-015, REQ-016 | `lisp/gascity-formula.el`, `lisp/gascity-action.el`, `lisp/test/gascity-test.el` |
| ga-4ef | Gate + tmux-Emacs TRAMP e2e acceptance pass + QA report | ga-udw | REQ-017, REQ-018 | `docs/qa/` report |

### Work item details

- **ga-dqm (WI-1, plan Phase 1 "Plumbing").** Read command classes
  `gascity-command-formula-catalog` / `gascity-command-formula-show` (the
  latter with the F-1 `:var` list slot), `gascity-command-sling` `:on` slot
  plus its `--on=...` parse clause, and the `beads-from-json` domain classes
  (`gascity-formula-catalog-entry`, `gascity-formula-var`,
  `gascity-formula`) with `(or null …)` optional slots. Verification: ERT
  decoding + CLI construction tests (`cl-letf` house convention); whole-package
  `eldev compile --warnings-as-errors`.
- **ga-wxt (WI-2, plan Phase 2 + D1/D2/D3).** New `lisp/gascity-formula.el`
  loaded between `gascity-domain` and `command-status`: session-lifetime
  caches keyed `(concat (file-remote-p dir) dir)` with
  `gascity-formula-invalidate`; catalog access with the REQ-002
  clear-empty-catalog message; enum mapping (`vars[].enum` wins, else the
  `metadata.gc.methodology` fallback, else string); shape detection
  (`metadata["gc.kind"]=="drain"` or literal `{{convoy_id}}` scan);
  `gascity-formula--validate-values` (names missing vars, no gc call,
  unparseable pattern degrades); history registry producing
  `gascity-formula-history-<formula>-<var>` ordinary history variables.
  Verification: ERT fixtures per var kind, cache isolation local vs stubbed
  remote, detection prongs, validation messages, distinct history symbols.
- **ga-udw (WI-3, plan Phase 3 as revised by F-1).** The dynamic transient:
  scope plist, annotated formula picker, Children generation from `vars[]`
  (enum choice / boolean toggle / string option with description-as-prompt,
  default-as-initial, "(required)" marks, entry-time pattern validation,
  absent-field degradation), dispatch suffix with pre-dispatch validation
  (missing required vars named, no gc invocation) and both sling shapes
  (targetless `:formula t`, targeted `:on` per D2), recipe preview that
  **re-runs `gc formula show <name> --json` with the current `--var` values**
  and renders gc's substituted recipe through `gascity-view-get-buffer-create`,
  and wiring into `gascity-sling-dispatch` (delete
  `gascity-sling--read-vars`, keep bindings, preserve
  `docs/DESIGN-write-actions.md` §5.2/§10 conventions). Verification: ERT
  children-generation and command-construction tests; whole-package compile.
- **ga-4ef (WI-4, plan Phase 4).** `scripts/gate.sh` green (REQ-017), then
  the AGENTS.md interactive acceptance gate: fresh Emacs inside tmux against
  `/ssh:localhost:/home/roman/bright-lights` — remote catalog pick, generated
  var infixes, substituted recipe preview, real dispatch landing in the
  remote store, both sling shapes including the `--var` + `--on` combination,
  per-variable history and savehist persistence across restart, and
  local/remote cache isolation. Result recorded in a `docs/qa/` report
  before this item closes.

### Verification expectations (all items)

- Every item runs the ERT suite (`eldev test`) and the full-package compile
  gate (`eldev compile --warnings-as-errors`); gc-boundary stubs use
  `cl-letf` on the reader/bang executors per the house convention.
- ga-4ef additionally requires `scripts/gate.sh` exit 0 and the completed
  tmux-Emacs TRAMP acceptance pass recorded under `docs/qa/` — the
  acceptance gate for the whole feature.
- Commits cite the implemented design section (`docs/DESIGN-write-actions.md`
  §5.2/§10 where the sling UI changes).

### Skipped work

None. Every plan phase maps to a work item; no plan element was dropped.

### Blocked work

None. The plan-review's single blocking finding (F-1) was resolved by
incorporation into ga-dqm and ga-udw as specified by the reviewer; no work
item waits on anything outside this convoy.

### Coverage

| ID | Status |
| --- | --- |
| AC-1 | covered |
| AC-2 | covered |
| AC-3 | covered |
| AC-4 | covered |
| AC-5 | covered |
| AC-6 | covered |
| AC-7 | covered |
| AC-8 | covered |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |
| REQ-015 | covered |
| REQ-016 | covered |
| REQ-017 | covered |
| REQ-018 | covered |
| F-1 | covered |
# Sling Command Redesign — Plan Review (implementation readiness)

Review of `plans/sling-command/implementation-plan.md` (workflow root
`ga-eavt`, plan stage attempt 1) for the `build-basic.plan-review`
step (bead `ga-2sac`). Scope: a plan review against the implementation
plan plus a lightweight implementation-readiness pass — requirements
traceability, task boundaries, test commands, and risk — with required
changes treated as blockers for decomposition.

**Verdict: APPROVED for decomposition** (one required change found and
applied to the plan in place during this review; details below).

## Method

The review did not stop at internal consistency of the plan document.
Every load-bearing claim in the plan's Current System and work items
was verified against the actual repository state:

- **Upstream artifact integrity**: the trace hashes were recomputed —
  `requirements.md` (`sha256:0e2a4780…`) ✓, `design.md`
  (`sha256:1a6e42cc…`) ✓, `menu-mockups.md` (`sha256:7aaca5e3…`) ✓ all
  match the recorded front matter; the coverage table matches
  `trace.coverage` exactly (REQ-001…REQ-015, all `covered`).
- **Current System claims**: checked in the source. Confirmed:
  `gascity-sling-dispatch` and its children machinery
  (`gascity-sling--children-specs`, `-setup-children`,
  `-scope-info`, `-parse-transient-args`, `-run`, `-city-dir`,
  `-remembered`) and `gascity-sling--reserved-keys`
  (`f g T A c a n m t s p r x q`) in `lisp/gascity-action.el`; the
  formula machinery in `lisp/gascity-formula.el`
  (`gascity-formula-catalog-cache` / `-list-cache` / `-recipe-cache`
  keyed by `gascity-context-scope-key`, `-choices`,
  `-refresh-async`, `-enum-metadata-keys`, `-needs-convoy`,
  `-validate-values`, `-history-var`,
  `gascity-sling-formula--var-key(s)`, `-dispatch`, `-show-recipe`,
  `-render-recipe`, `-bead-or-convoy-at-point`,
  `-current-values`); the roster in `lisp/gascity-agents.el`
  (`gascity-agents--rows` over `gascity-dashboard--agents`,
  `-state-label`, no completion-facing accessor yet — as claimed);
  `gascity-run-show` in `lisp/gascity-run.el`;
  `gascity-view-get-buffer-create`, `gascity-rigs-cached` /
  `-prefixes`, `gascity-command-act-async`,
  `gascity-action--read-session` / `-async-text-view`,
  `scripts/e2e-harness.sh`, `scripts/gate.sh` — all present as
  described.
- **Test inventory**: the seven `lisp/test/gascity-sling-test.el`
  tests named by the plan exist and are correctly counted; the shared
  suite's sling surface was enumerated exhaustively (see Finding 1).

## Findings

### F1 (required change — applied): WI-10 undercounted the affected
test surface

The plan's WI-10 said to "update the four shared-suite var/reserved
tests in `gascity-test.el` for the new key set", and the Current
System / Verification sections listed only those four. An exhaustive
enumeration shows the layout rewrite touches **~18 layout-coupled
tests** in `gascity-test.el`, not four: the transient-internal tests
(`-unified-wiring`, `-unified-layout`, `-target-set-and-header`,
`-arg-edit-re-setups-in-place`, `-dispatch-target-fallback`,
`-plain-path-unchanged`, `-preview-dry-run-paths`,
`gascity-test-formula-sling-dispatch-shapes`,
`gascity-test-formula-sling-preview-fresh-show`) plus the pinning and
key-set tests (`-city-dir-pins-entered-from-city`,
`-dispatch-prefix-seeds-city-dir`, `-dispatch-pick-pins-city-dir`,
`-children-specs-read-recipe-pinned`, `-dispatch-suffixes-run-pinned`,
`-reserved-keys-complete`). Decomposing WI-10 against "four tests"
would have materially under-sized the unit and left a hidden port
surface mid-implementation.

**Resolution**: the plan was updated in place during this review — the
Current System test bullet, WI-10, the Verification "Updated (WI-10)"
list, and the Risks "Test churn" bullet now enumerate the full set and
explicitly mark the command-line/cache tests
(`-sling-command-line`, `-rich-command-line`,
`-parse-transient-args`, `-on-command-line`, the
`gascity-test-formula-*` cache/enum/history set,
`gascity-test-store-formula-refresh-async-swaps-caches`,
`gascity-test-remote-sling-plan-view`) as expected-pass-unchanged on
the retained plumbing. No requirement, work-item boundary, or
sequencing change was needed.

### F2 (note, no change required): requirements' file-name slip for
the follow target

`requirements.md` REQ-009 says the follow offer reuses
"`gascity-runs.el`"; `gascity-run-show` actually lives in
`lisp/gascity-run.el` (`lisp/gascity-runs.el` is the runs *list*
view). The plan is already correct (Current System and WI-8 both say
`gascity-run-show` / `lisp/gascity-run.el`), so the plan needs no
change; the slip is recorded here so the implementer is not confused
by the upstream artifact. Not a blocker.

### F3 (note): verified-good claims worth keeping pinned in tests

The plan's keyset claims are consistent across artifacts: mockup §10's
key summary (`A f T -- s P r g x q`, `p` freed) matches the plan's new
reserved set `A f T c a n m t s P r g x q` (routing flags stay for the
plain-only group, per REQ-011/F-5), and the current defconst in
`lisp/gascity-action.el` matches the plan's description of what it
replaces. The existing `-reserved-keys-complete` sync test keeps this
honest during the rewrite.

## Implementation readiness pass

- **Requirements traceability** — PASS. Every REQ-001…REQ-015 maps to
  at least one named work item, and every work item cites its REQs;
  the Coverage table, `trace.coverage`, and the Markdown coverage
  table agree. Acceptance criteria 1–13 each trace to requirements
  named by the work items.
- **Task boundaries** — PASS. All twelve work items (WI-1…WI-12) name
  their files, new/changed functions, REQ trace, and tests; each is
  one decomposition unit. Sequencing (six waves, pure foundations
  first, typed vars after the final reserved set, e2e/docs last)
  is coherent and justified.
- **Test commands** — PASS. The plan names the focused proof
  commands: `scripts/gate.sh` (warnings-as-errors compile + full
  ERT), the ERT stubbing conventions
  (`gascity-test-with-store-stubs`, `cl-letf` on the reader boundary,
  non-blocking guard list), `. scripts/e2e-harness.sh` with the
  bright-lights four-scenario protocol, and `make -C doc` for the
  manual.
- **Risk** — PASS. Risky areas are explicit with mitigations: the
  `gc sling --json` root-field unknown (fallback: newest workflow
  root via a store read — never a guess), render-time gc prohibition
  (D9, store caches, pure validation), reserved-key churn
  (deterministic algorithm + sync tests), TRAMP completion latency
  (fail-soft readers, timeout-wrapped harness), ephemeral screenshot
  capture (mockup fallback documented), layout fidelity (mockup walk
  in WI-11), and now the true test-churn surface (F1). No migrations
  or data-format changes; public interface change (transient keys) is
  documented and doc-tracked (WI-12); rollback is per-WI commits on
  `main` per the stated constraint.

## Conclusion

The plan is grounded, accurate against the repository, fully traced,
and implementation-ready. The single blocker-class finding (F1) was
resolved by updating the plan in place; F2/F3 are non-blocking notes
for the implementer. **The plan is approved for decomposition.**

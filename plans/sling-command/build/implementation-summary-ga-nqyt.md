---
schema: gc.build.implementation-summary.v1
workflow: {id: ga-7ly1, formula: do-work}
methodology: {pack: gascity, name: build-basic}
producer: {formula: do-work, stage: implement, attempt: 1}
status: approved
trace:
  upstream:
    - path: beads/ga-3wpi
      hash: bead:ga-3wpi
      ids:
        - REQ-014
    - path: plans/sling-command/implementation-plan.md
      hash: sha256:d29adc3f88d94c1eca70a227fd9355f7f62b15fe5e0dcbcecc4c88050b94ab85
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: lisp/gascity-action.el
      hash: sha256:619c10dc366a3d0d1e5d581db51e94c41f538171bc2949b8e22c533b67481df8
    - path: lisp/gascity-agents.el
      hash: sha256:88b017693c3d5bc16775777cbf19079c5a8f8f7862d5bd0f1922e905fed6be81
    - path: lisp/gascity-formula.el
      hash: sha256:6b6f54a2fdd74b54c1cd1a928bdb1ae30d28da550ab14258a970faa9fa5b07d5
    - path: lisp/test/gascity-agents-test.el
      hash: sha256:277ca0908b004b55f9bf785e4e290fa24dfa870ebec7f6a4d30dba7d6f544c2f
    - path: lisp/test/gascity-sling-test.el
      hash: sha256:113cf32ac36ce67e86d5d530be8c244b0a88e3b123b1124c41934bc5fa21fad5
    - path: docs/qa/2026-09-27-wi11-sling-redesign-e2e.md
      hash: sha256:afcad6e5996d2d5ba634cd8c90a0e54e9625922fd34783e2b067c6ec702dc7f5
  coverage:
    - id: REQ-014
      status: covered
      rationale: >-
        All four design scenarios verified live through
        scripts/e2e-harness.sh from a fresh tmux Emacs over plain-ssh
        TRAMP against /ssh:localhost:/home/roman/bright-lights, every
        gc invocation as `gc --city /home/roman/bright-lights …`
        (probed on gascity-context-city-args): (1) pancakes end to end
        — mockup sentence, launch, the follow offer's F jump to the
        run view, the mayor session working all five steps and the
        root closing; (2) build-basic --on with typed vars — file
        completion against the rig workdir, the plans/<slug>/ seed,
        the numeric refusal, the launch's workflow root (hw-5o1) live
        in the run view; (3) the bl-bdj trap — the footer's §5a
        warning verbatim for a city-scoped target, ✓ Ready for a
        rig-scoped one; (4) plain dispatch — zero-prompt freeform
        landing in the derived target's store (hw-4wz) and the
        zero-prompt bead-at-point dispatch exposed as gc's cross-rig
        refusal, which the footer now warns before the launch.  The
        dogfood report is docs/qa/2026-09-27-wi11-sling-redesign-e2e.md;
        three integration bugs the pass found are fixed with
        regression tests and the gate is green.  Deviations (read
        aborts close the menu, remembered answers lost across reopen,
        TRAMP-prefixed path vars, the HQ rig missing from the rig
        memo, *_target seeds, the formula path never nudging, C-u S
        without a freeform escape) are recorded in the report's
        findings for the fix loop.
---

# Implementation Summary: WI-11 — End-to-end verification (source anchor ga-3wpi)

## Summary

The sling command redesign's e2e acceptance pass (plan WI-11,
REQ-014) ran live against the remote test city bright-lights over
plain-ssh TRAMP, through the hardened harness.  The pass merged the
still-open sibling work items into the item worktree first (WI-5
typed vars `cc5d836`, WI-6 live footer `80c35dd`; WI-8's follow offer
was already in the tree), exercised the four design scenarios in a
fresh tmux Emacs, and found three integration seams where the sibling
items met each other — a nil-recipe crash that blocked every
transient setup, a footer that ignored the Who default it warns
about, and a scope classifier that could not classify config-name
targets against instance-carrying rosters.  All three are fixed in
this item with regression tests; the gate is green (723/723).  The
dogfood report is `docs/qa/2026-09-27-wi11-sling-redesign-e2e.md`.

## Intended Behavior

- The four scenarios of REQ-014 run against the integrated redesign
  as a user would drive it — keystrokes through tmux, reads over
  TRAMP, every gc call `gc --city /home/roman/bright-lights …`:
  pancakes end to end (sentence → launch → follow offer → run view →
  the mayor session works it), build-basic `--on` with typed vars
  (file/dir/agent/numeric classes, seeds, launch), the bl-bdj footer
  trap (⚠ for a city-scoped target, ✓ for a rig-scoped one), and
  plain dispatch (zero prompts with the derived Who default,
  freeform through the read).
- Client-side validation stays advisory in the UI: warnings render in
  the footer before any gc call; gc stays the authority (the pass
  proved both sides — the footer's cross-store warning now predicts
  the exact refusal gc issues at launch).
- The pass leaves the bright-lights city with real evidence in its
  stores: `bl-9jmm` (pancakes, closed by mayor), `hw-5o1`
  (build-basic, live workflow), `hw-4wz` (freeform plain sling,
  worked by a hello-world worker), `bl-4rvq`/`bl-23by` (fixtures).

## Changed Files

- `lisp/gascity-action.el` — `gascity-sling--footer` consults the
  Who default for the §5b/§5c checks (the derivation is a target
  for every check, not only the header sentence).
- `lisp/gascity-agents.el` — `gascity-agents-roster-scope` falls
  back to the target's own slash prefix when no roster row matches
  (pool instances never exact-match a config-name target).
- `lisp/gascity-formula.el` — nil-recipe guards in
  `gascity-sling--missing-required-vars` and
  `gascity-sling-formula--current-values` (the WI-6 footer composes
  both with the recipe nil on every setup).
- `lisp/test/gascity-sling-test.el` — regression tests for the nil
  recipe and the derived-target footer; one canonical
  `gascity-sling-test--recipe` (three colliding definitions from the
  merged work items) plus `gascity-sling-test--vars-recipe`.
- `lisp/test/gascity-agents-test.el` — the classifier's slash-prefix
  fallback pinned.
- `docs/qa/2026-09-27-wi11-sling-redesign-e2e.md` — the dogfood
  report (the four scenarios, the fixes, the findings).

## Verification

First verification command (after merging the sibling items into the
item worktree, before the pass):

```
eldev compile --warnings-as-errors && eldev test
```

Observed: compile clean; 721/721 tests green on the merged tree.

The pass itself (live, over TRAMP through the harness):

```
. scripts/e2e-harness.sh
e2e_kill_emacs && e2e_start_emacs && e2e_emacs_ready
# drive the four scenarios with e2e_send_keys/e2e_eval against
# /ssh:localhost:/home/roman/bright-lights
```

Observed: all four scenarios verified (report §The four scenarios);
two pass-blocking bugs found and fixed (nil-recipe setup crash,
footer vs Who default), one classifier gap fixed.

Final proof command (after the fixes, the item's gate):

```
scripts/gate.sh
```

Observed: `>>> gate: PASS (compile clean + tests green)` — 723/723
tests (721 + the two new regression tests), 2026-09-27 19:46.

## Remaining Risks

- Findings recorded in the report need the review/fix loop: read
  aborts close the whole transient; var answers set after the last
  re-setup are lost across quit+reopen; typed path vars over TRAMP
  answer TRAMP-prefixed names gc cannot consume; the rig memo misses
  the HQ rig in cockpit-only sessions (`gc status` omits it), which
  silences the §5b check until a rig-list read warms it; `*_target`
  var seeds ignore the Who default; the formula path never nudges the
  target (scenario 1 needed a manual nudge for mayor to work the
  workflow); `C-u S` has no freeform escape (WI-4's staged layout has
  not landed — the transient still renders the Formula/Destination
  groups, not the mockup's What/Who/How stages).
- The screenshots for WI-12 were not captured from this session (a
  `-nw` tmux Emacs cannot produce the manual's GUI shots); WI-12
  should run a GUI session or fall back to the mockup renderings per
  the requirements' Open Question.
- The bright-lights city carries live evidence from the pass
  (bl-9jmm closed, hw-5o1 running, hw-4wz in progress, fixture beads
  bl-4rvq/bl-23by open); the follow-up passes should expect them in
  the Work/Runs views.

| ID | Status |
| --- | --- |
| REQ-014 | covered |

---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-9ej
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
    - path: beads/ga-4ef
      hash: bead:ga-4ef
      title: "WI-4: Gate + tmux-Emacs TRAMP e2e acceptance pass + QA report"
      ids:
        - REQ-017
        - REQ-018
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan, Phase 4 (gate + tmux-Emacs TRAMP acceptance) and decision D2"
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (the REQ ids this step covers)"
    - path: lisp/gascity-formula.el
      hash: sha256:df21e425290cb59e730cc437630e87624d3b03218d405ca25f74f069df0446fe
      title: "Two e2e-founded fixes: nil-recipe degradation and unwrapped :info/vector construction in the formula sling transient"
    - path: lisp/test/gascity-test.el
      hash: sha256:b93b275aafd7aa8d26c2c4463bf12447ea61741b9ca5df6b718140a44f78cacf
      title: "Regression test for the nil-formula transient setup degradation"
    - path: docs/qa/formula-sling-ui-e2e.md
      hash: sha256:80667081dd4b8da4c814e9c4c189e80189c65db939c96dcd7c8a1a82ab08c98c
      title: "Live QA report: the tmux-Emacs TRAMP acceptance pass with findings F1-F5"
  coverage:
    - id: REQ-017
      status: covered
    - id: REQ-018
      status: covered
---

# Implementation Summary: WI-4 gate + tmux-Emacs TRAMP e2e acceptance pass + QA report

## Summary

Completed work item WI-4 of the formula-sling-ui plan (source anchor bead
ga-4ef) in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-4ef`, committed as
`90cdc6b9241ce3124e0567498fd5884848071295` ("fix(formula): e2e-founded sling
transient setup fixes + QA report") on the worktree's detached HEAD.

The item ran the acceptance gate, drove the interactive tmux-Emacs TRAMP
pass against the remote test city, and recorded it in
`docs/qa/formula-sling-ui-e2e.md`. The pass founded two real setup defects
in the sling transient that ERT (pure helpers, gc stubs) could not see; both
were fixed in place with a regression test, and the gate re-run green. The
formula-dispatch half of the acceptance is blocked by a gc-side defect in
the bright-lights test city (every v2 pack formula fails instantiation with
`unknown formulas v2 target "gc.run-operator"`, reproduced with plain gc and
no Emacs involved); the live-dispatch acceptance evidence was completed
through the non-formula sling, and the blocker is recorded as follow-up F3
in the QA report.

## Intended Behavior

- **Gate (REQ-017, AC-8).** `scripts/gate.sh` — `eldev compile
  --warnings-as-errors` over the whole package plus `eldev test` — passes
  with zero warnings; the whole package is compiled, never a subset. Ran
  before the fixes (266/266) and again after them (267/267, the new
  regression test included).
- **TRAMP e2e acceptance (REQ-018, AC-7).** A fresh `emacs -nw -Q` inside a
  tmux session (`gce-e2e`), loaded from the item worktree, connected to the
  remote test city and exercised the real flow: remote status dashboard;
  `S` sling dispatch; `-f` formula flow; catalog picker with visible
  annotations from the remote catalog; generated per-var infixes (enum
  radio for `drain_policy`, boolean toggles for `push`/`open_pr`, string
  prompts with defaults and required marks for `subject_path`/`report_path`);
  the F-1 revised recipe preview backed by a fresh server-side substituted
  `gc formula show` read; the D2 client-side refusal of a convoy-requiring
  formula with no bead/convoy at point; the targeted `--on` shape seeded
  from a convoy at point including the `--var` + `--on` combination; a live
  non-formula sling creating and routing a task bead in the remote store;
  `M-p` per-variable history and savehist persistence across an Emacs
  restart; and local/remote cache-key/buffer-name isolation between
  `/home/roman/emacs-city` and `/sshx:localhost:/home/roman/bright-lights`.
- **QA report.** `docs/qa/formula-sling-ui-e2e.md` records what was
  exercised, concrete observations (dispatched bead id, substituted preview
  output, history recall), and the defects/follow-ups found, per AGENTS.md.
- **Defect fixes in place.** Per the item's scope, e2e-surfaced defects were
  fixed in the worktree and re-gated: (F1) the initial transient open before
  any formula pick crashed on the nil recipe — now degrades to no Variables
  section (REQ-016); (F2) the "Formula" column was built with `apply` whose
  last-argument spread spliced the `("q" "Quit" transient-quit-one)` suffix
  and double-nested the `:info` scope line, crashing `transient-setup` in
  every transient version — now built as a vector directly.

## Coverage

| ID | Status |
| --- | --- |
| REQ-017 | covered |
| REQ-018 | covered |

## Changed Files

- `lisp/gascity-formula.el` — nil-recipe guard in
  `gascity-sling-formula--var-infixes`; `gascity-sling-formula--static-children`
  builds the "Formula" column vector directly (unwrapped `:info` line, no
  `apply`), with the founding noted in docstrings.
- `lisp/test/gascity-test.el` — new
  `gascity-test-formula-sling-var-children-nil-formula-degrades` regression
  test pinning the REQ-016 degradation for a nil formula.
- `docs/qa/formula-sling-ui-e2e.md` — the live QA report (new file).

## Verification

- `scripts/gate.sh` (eldev compile `--warnings-as-errors` + `eldev test`) —
  **PASS**, observed `>>> gate: PASS (compile clean + tests green)`,
  267/267 tests after the fixes (266/266 before them).
- Live tmux-Emacs TRAMP acceptance pass against
  `/sshx:localhost:/home/roman/bright-lights` (see the QA report for the
  full protocol and captured observations; the connection uses the `sshx`
  method because the plain `ssh` TRAMP method hangs on this host even in
  bare `emacs -Q --batch` without gascity loaded — QA report F4).
- Final proof command and observed result (the live sling routed a task
  bead in the remote store from the e2e session):

  ```console
  $ ssh localhost "cd /home/roman/bright-lights && gc bd list --json --limit 5"
  …
  bl-c3x open e2e WI-4: verify live sling over TRAMP creates and routes a task bead  gc.routed_to=mayor
  bl-ohb open sling-bl-c3x
  ```

- The formula-dispatch half of the real-sling acceptance is blocked by the
  test city itself: `gc sling mayor review --formula --var …` fails with
  `instantiating formula "review": step review.validate-context: unknown
  formulas v2 target "gc.run-operator"`, reproduced with plain gc over ssh
  (no Emacs), for every catalog formula, after `gc reload` and a full
  `gc restart`, with `gc doctor` green (89 ✓). The transient's dispatch argv
  was verified through gc's own error naming the attach target ("on
  bl-35p"). The porcelain dispatched the right argv and surfaced gc's error
  cleanly; the city-side blocker is recorded as QA report F3.

## Remaining Risks

- **REQ-018's formula-dispatch half remains environment-blocked** (QA F3):
  bright-lights cannot instantiate any v2 pack formula (`unknown formulas v2
  target "gc.run-operator"`); until that city-side issue is resolved, the
  successful-formula-dispatch acceptance evidence rests on the non-formula
  live sling plus the `--on`-shaped dispatch argv reaching gc and being
  rejected by gc itself, not on a successful formula workflow root in the
  remote store.
- **Auto-refresh vs sync-read spin (QA F5):** with the dashboard's
  auto-refresh timer active, the first sync read inside a transient
  busy-spun (C-g recoverable) instead of completing; workaround applied
  during the pass (auto-refresh off). Needs a dedicated fix guarding the
  timer against in-flight synchronous TRAMP roundtrips.
- **TRAMP `ssh` method hangs on this host** (QA F4) — the pass ran over
  `sshx`; the `ssh`-method failure reproduces without gascity and deserves
  its own investigation.
- The sling transient was exercised over TRAMP with transient 0.13.8; the
  package's pinned minimum (Eldev `:version "0.10.1"`) predates this
  session's transient, and the F2 fix removes the only shape that parsed
  differently across versions, but a quick smoke on 0.10.x would close that
  gap.

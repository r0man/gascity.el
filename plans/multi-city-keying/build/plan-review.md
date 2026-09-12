---
schema: gc.build.plan-review.v1
workflow:
  id: ga-rv5
  formula: build-from-requirements
methodology:
  pack: gascity
  name: planning-base
producer:
  formula: build-from-plan-base
  stage: plan-review
  attempt: 1
status: approved
plan_slug: multi-city-keying
phase: plan-review
rig: gascity.el
rig_root: /home/roman/workspace/gascity.el
interaction_mode: interactive
verdict: approved
trace:
  upstream:
    - path: plans/multi-city-keying/build/implementation-plan.md
      hash: sha256:d50f5842db43c7bc75d9884e70028ae6a4bf79920a37a41468d0e8f8601e14c7
      title: "The implementation plan this review approves"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
    - path: plans/multi-city-keying/requirements.md
      hash: sha256:97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43
      title: "Approved requirements the plan was checked against"
      ids:
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
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
---

# Plan Review: Per-city keying — multiple cities in one Emacs

**Verdict: approved.** No blocking findings; three non-blocking advisories
below. Decomposition may proceed.

## What was checked

The plan was reviewed against the approved requirements artifact
(`plans/multi-city-keying/requirements.md`, hash verified
`97a0eec…`) and the current working tree.

### Factual claims verified against the tree

- Upstream hashes recorded in the plan match: requirements.md
  sha256 `97a0eecaf4438c9b22d299dd170523690de1e39c77ce59258855873151984c43`;
  requirements-input.md sha256 `a08cc8c6a87f11f0b6e558f5ac4565498879b3bc65576c9485399ad03d92eae0`;
  `git rev-parse HEAD:lisp/gascity-remote.el` = `3fa83997…`,
  `HEAD:lisp/gascity-context.el` = `cac32df3…`; `git status` shows `lisp/`
  clean, so the `git:` hashes are current.
- `gascity-remote-buffer-name` (`lisp/gascity-remote.el:70`) matches the
  plan's "current key" description: 2-arg `(base &optional dir)`, remote
  prefix spliced before the trailing `*`, local returned unchanged. The
  Step 3 extension keeps the 2-arg contract byte-identical.
- `gascity-context--rigs-key` (`lisp/gascity-context.el:255`) is today the
  remote prefix (`""` local); `gascity-rigs-remember`'s
  prefix-less-never-replaces-prefixed guard compares within one key, so the
  plan's D3 claim (per-city protection for free once the key becomes the
  city root) is correct.
- Terminal attach call site is at `lisp/gascity-terminal.el:626` exactly as
  the plan says, and it is the only direct
  `gascity-remote-buffer-name` caller outside the factory.
- No formula-cache module exists under `lisp/`, so REQ-010 (ship the
  helper, record the integration point) is the right governing clause; D5
  records it in the `gascity-context.el` commentary.
- The named existing tests exist
  (`gascity-test-remote-buffer-name`, `gascity-test-rigs-cached-never-spawns`,
  `gascity-test-agent-attach-passes-rig-store`,
  `gascity-test-remote-localize-path`); the plan extends rather than
  weakens them.
- Load order: `gascity-context.el` is loaded after `gascity-remote.el` and
  already uses it, so D2's placement argument (helper must live in
  `gascity-context.el` to avoid a require cycle) is correct.
- `gascity-context-city-root` honors the single override, is memoized per
  start dir (nil cached), and `gascity-context-clear-cache` whole-table
  clears — supporting D2/D4 as written.

### Requirements coverage

All 16 REQs trace to concrete steps and every AC to them:

- REQ-001/004 → Steps 3–4 (D1 splice; root computed once, reused for pin
  and name). REQ-002/013 → fallback shapes in D1's table. REQ-003 → one
  scheme, commentary updates in both modules, single naming function.
- REQ-005 → D3 records the "city root subsumes remote prefix" reading of
  the requirement's "city root + remote prefix" as the plan is entitled to
  (REQ rows say the key *must* include both; the city root is a
  TRAMP-qualified file name, so the pair cannot collide — accepted, and
  the per-city partition tests are what actually enforce the property).
- REQ-006/007/008 → Step 2 (no code change needed for the guard) plus the
  new tests, including the extended never-spawns tripwire.
- REQ-009/010 → D5. REQ-011/012 → Step 6 override test; single override
  unchanged. REQ-014/015/016 → Steps 6, 7, 8.
- AC-4 is correctly gated on the tmux-Emacs dual-city e2e pass with a
  `docs/qa/` report, not on ERT alone.

### Open questions disposition

All four requirements-stage open questions are resolved in the plan
(D1–D5) with written rationale, which is what the requirements artifact
asks the plan stage to do. `interaction_mode: interactive` is honored: no
step requires interactive input mid-build, and the one place a human
signal could matter (e2e environment unavailable) is explicitly routed to
a QA-report blocker rather than a silent skip.

## Advisories (non-blocking)

1. **Step 4 duplicates `gascity-context-pin-directory` inline.** The
   snippet's `(or root (file-name-as-directory (expand-file-name …)))`
   fallback is behaviorally identical to `gascity-context-pin-directory`,
   but re-derives it. During implementation, prefer reusing
   `gascity-context-pin-directory` (a second memoized lookup is a hash
   hit) or refactoring pin-directory onto the shared root computation, so
   the pinning rule lives in one place. Behavior is identical either way.
2. **Remote-city buffer-name churn.** D1 correctly notes remote *city*
   view names grow the city path. The plan already requires recording
   this in the QA report; keep that promise — it is the only user-visible
   surface change.
3. **`gascity-beads--rig-store-cached` claim.** The plan says it is "fixed
   transitively once the memo is re-keyed" — verified in the tree (it
   reads `gascity-rigs-cached`), but Step 6 has no dedicated test for the
   bead-store path; the existing `gascity-test-agent-attach-passes-rig-store`
   covers the memo route. Acceptable; a one-line assertion per city in the
   memo tests would close it cheaply.

## Verdict

`approved` — proceed to decomposition (`ga-9xy` validate-decompose
continuation inputs). The advisories may be adopted by the implementer at
discretion; none changes scope, order, or the verification strategy.

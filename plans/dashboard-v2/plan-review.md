---
schema: gc.build.review.v1
workflow:
  id: ga-uxhh
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: plan-review
  attempt: 1
status: changes_required
trace:
  upstream:
    - path: plans/dashboard-v2/implementation-plan.md
      hash: sha256:1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f
      ids:
        - ga-uxhh
    - path: plans/dashboard-v2/requirements.md
      hash: sha256:912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07
      ids:
        - ga-7pq7
  coverage:
    - id: ga-uxhh
      status: covered
    - id: ga-7pq7
      status: covered
---

# Plan Review: Dashboard v2 (runs, honest needs-you, activity, mail)

| ID      | Status  |
| ------- | ------- |
| ga-uxhh | covered |
| ga-7pq7 | covered |

## Verdict

**Changes required.** Two blockers must be fixed in the plan (or absorbed as
explicit corrections by decomposition) before task beads are cut: the plan's
S1 step-discrimination rule matches **zero** step beads in the live store
(F-1), and its progress recipe cannot see closed steps at all (F-2). The
plan is otherwise well-grounded: its upstream hashes re-verify against the
live files, it still passes the `gc.build.plan.v1` validator, every step
maps to acceptance criteria, and the honest-degradation posture (no fake
data, dim pointers, zero HTTP) is carried through consistently. All findings
below were verified against the live `emacs-city` CLI on 2026-09-24, run
`ga-uxhh` itself being the test subject.

## Findings

### Blockers (must resolve before decomposition)

- **F-1 (blocker) — S1 step discrimination matches no step beads.** Plan
  S1: "A bead is a **step** when it carries the same root key and
  `gc.ralph_step_id` (or `gc.step_id`)." Live `gc bd list --json` over this
  store (40 rows): exactly **1** bead carries `gc.graphv2_root_key` (the
  run root `ga-uxhh` itself); **0** step beads carry it; **0** carry
  `gc.ralph_step_id`. Step beads (e.g. `ga-ysif`, this step) carry
  `gc.root_bead_id: ga-uxhh` plus `gc.step_ref`, and *not* the root key.
  The rule as written groups the run root but zero steps under it —
  progress `0/0`, empty run detail. **Fix:** discover run roots by
  `gc.graphv2_root_key` (or `gc.kind: workflow`), then group steps by
  `metadata.gc.root_bead_id == <root id>` (falling back to the root's
  `gc.graphv2_root_key` value only if a store variant emits it on steps).
  `gc.logical_bead_id` marks execution clones (5 in this store), not steps
  — do not use it for discrimination.
- **F-2 (blocker) — the progress recipe cannot count closed steps.**
  Requirements §Technical Stories and plan S1 compute progress as
  "closed/total step count from the step graph (`gc bd show <root> --json`
  TRACKS/TRACKED BY relationships or the step beads sharing the root
  key)". Live: the default `gc bd list --json` **excludes closed beads**
  (40 rows; the 5 closed `ga-uxhh`-rooted beads appear only under
  `--status closed`), so "steps sharing the root key" sees only open
  steps; and `gc bd show ga-uxhh --json` lists just **1** `tracks`
  dependency with `dependent_count: 37` and **no** dependents array — the
  count without the rows. Neither recipe can produce `closed/total`.
  **Fix (verified live):** read the step graph from
  `gc bd show <root> --include-dependents --json`, which returns the root
  plus the full dependents array (37 entries, each with `status`;
  `--brief-deps` slims them) and compute progress client-side — or run one
  `gc bd list --all --json` and group (F-3 applies). S2's run-detail read
  should use the same recipe. Also drop the "in dependency order as
  returned by the payload" promise: the dependents array is id-ordered,
  not topological; render in payload order (creation order) or sort
  client-side by `gc.step_ref`.

### Majors

- **F-3 (major) — `bd list` default limit truncates the "full list".**
  Plan S1/S2 read `gascity-reader-read-async '("bd" "list")` reasoning
  "full list; stores are small". The CLI default is `--limit 50`
  (`-n, --limit int (default 50, use 0 for unlimited)`); this store
  happens to have 40 open rows today, but the bright-lights TRAMP target
  (AC-9) and any busier city silently truncate. **Fix:** read
  `("bd" "list" "--all")` (verified: 663 rows vs 40 default) or
  `--limit 0`; state the flag in the plan. `--max-rows` exists if a
  circuit breaker is wanted.
- **F-4 (major) — the reader auto-appends `--json`; `gc events` is about
  to reject that flag.** `gascity-reader-read-async` appends `--json`
  unless present (`lisp/gascity-reader.el` ~line 761). Live:
  `gc events --since 2h --json` works today but prints "Flag --json has
  been deprecated, output is always JSONL; the flag is now a no-op and
  **will be removed in a future release**" on stderr. When it is removed,
  the auto-append turns every events read into a parse failure. S3's
  "JSONL variant next to `gascity-reader-read-async`" must therefore
  bypass the `--json` append for the events read *and* replace the
  sentinel's whole-output `gascity-reader-parse-json` call with line
  accumulation (good/bad split). Spell this plumbing change out in S3;
  otherwise it will be improvised and silently regress.

### Minors

- **F-5 (minor) — events DTO field list is slightly wrong.** Requirements
  promise "one DTO per line: actor, payload, run_id, seq, subject, ts,
  type". Live lines carry `actor, payload, seq, subject, ts, type, ok`;
  `run_id` appears only on some lines and `session_id` on others, and
  chatty-type counts are `bead.updated` 1362 / `order.fired` 953 /
  `order.completed` 953 in 2h (the plan's filter defaults are still the
  right ones). Selectors must tolerate absent `run_id`/`payload.title`
  (the plan already degrades to subject-only — keep it that way, just
  don't treat the DTO as uniform).
- **F-6 (minor) — S2 convoy-join envelope key.** `gc convoy list --json`
  returns `{"convoys":[…]}` (verified); the dashboard already unwraps
  `(alist-get 'convoys data)` for its Convoys group. S2 should name the
  envelope key and the `gc.input_convoy_id` join explicitly so the
  implementer reuses the loaded payload instead of re-reading.

## Verification

- Upstream traceability re-checked: `sha256(plans/dashboard-v2/requirements.md)`
  = `912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07`,
  matching the plan's `trace.upstream[0].hash`;
  `sha256(plans/dashboard-v2/implementation-plan.md)` =
  `1bfc7e2197246d56c347e345290144c9721a520a915a9115fd6b95cb50e4bd9f`
  (recorded above); `lisp/gascity-dashboard.el` is at
  `git:5ae47af99a60b29267eab5d4a034248a44922371`, matching
  `trace.upstream[1].hash`.
- `gc.build.plan.v1` validation of the plan artifact re-run and green:
  `GC_BUILD_SCHEMA_ROOTS=$PWD/.gc/schemas/build python3
  .gc/scripts/validate_build_artifact.py --schema gc.build.plan.v1 --path
  plans/dashboard-v2/implementation-plan.md` → `{"ok": true, …}`.
- Every CLI claim in F-1–F-6 verified live against the `emacs-city` city
  with `gc bd list/show`, `gc events`, `gc convoy list`, `gc mail count`,
  `gc costs --json` on 2026-09-24. Plan claims that re-verified **true**:
  dead `awaiting-input` arm (`pending nil` hardcoded at the call site,
  `lisp/gascity-dashboard.el` ~line 694); Activity pointer stub
  (line ~786); `gc mail count --json` shape (`unread`/`total`);
  `gc costs --json` → `json_unsupported`; `m` already bound to
  `gascity-mail-inbox` in `gascity-mode-map`; test file and gate as
  described.

### Implementation readiness pass

- **Requirements traceability.** Every plan step maps to acceptance
  criteria: S1 → AC-1, AC-8, AC-10; S2 → AC-2, AC-9; S3 → AC-3, AC-8;
  S4 → AC-4, AC-5, AC-6, AC-11; S5 → AC-7, AC-8, AC-9, AC-10, AC-12. The
  requirements' single coverage id (`ga-7pq7`) is carried in the plan's
  trace and table; no criterion is unaccounted for. The three requirements
  "Open Questions" (event window/N, replace-vs-extend Work in flight,
  closed-run display) are each resolved to a concrete default in the plan
  — good; the only *new* open item is the F-1/F-2 discovery recipe.
- **Task boundaries.** S1–S4 are independently mergeable behind a green
  gate with per-step fixture lists; S5 is the acceptance gate. Each maps
  cleanly to one implementation bead, with the F-1/F-2 corrections
  belonging to S1/S2's beads (and the F-4 plumbing to S3's). No boundary
  change needed.
- **Test commands.** The plan names `scripts/gate.sh` (whole-package
  byte-compile `--warnings-as-errors` + full ERT) per step and at S5,
  plus the honesty greps and TRAMP/e2e protocol — matching AGENTS.md's
  quality gate exactly. Sufficient.
- **Risk.** File scope is bounded (`lisp/gascity-dashboard.el`,
  `lisp/gascity-reader.el` JSONL plumbing only, tests, `docs/qa/`,
  artifact root); no migrations; no public-interface change beyond one
  `defcustom`; rollback is trivial (local commits on `main`, `push=true`
  per root vars — note the plan's Non-Goals say "work lands as local
  commits on `main`", which is consistent). Riskiest surface is the
  reader's async JSONL change (shared plumbing, TRAMP-sensitive — the
  docstring warns about stderr/direct-async pitfalls); S3 must preserve
  the stderr-separation wrapper unchanged, which the plan's "JSONL
  variant next to the existing function" phrasing supports.

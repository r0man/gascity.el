---
schema: gc.build.review.v1
workflow:
  id: ga-2ea1
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: review
  stage: synthesize-review
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/tramp-history-flood/acceptance-review.md
      hash: sha256:e18d620aefffc3dd97dcd7f2722a152d9c6ccf1ab1da32debcf7fc16eab694f1
    - path: plans/tramp-history-flood/test-evidence-review.md
      hash: sha256:177b0dd693628962d4faee57e02e07b3dcca60560297b7f07cc778d11603fed2
    - path: plans/tramp-history-flood/review-simplicity.md
      hash: sha256:6ecf370e7413a4773b389435bf4923c29b5827055c42ee60d1fa47de1e4e650d
    - path: plans/tramp-history-flood/starter-review-context.md
      hash: sha256:32befeec5f983dfa53c9f4185c00c84b286d2b5c51062adc759edf8f3a9c1721
    - path: plans/tramp-history-flood/implementation-summary.md
      hash: sha256:75cddc09ec077f474704df67fb75439ee636f15cc6621342c88472e6750c080c
  coverage:
    - id: ga-o98t
      status: covered
    - id: ga-sfnj
      status: covered
    - id: ga-5b9m
      status: covered
    - id: ga-x4j3
      status: covered
    - id: ga-ldrg
      status: covered
    - id: AC-6
      status: out_of_scope
      rationale: publish-stage REQ→change traceability is owned by the final-report stage, not the review lanes
---

### Trace Coverage

| ID | Status |
| --- | --- |
| ga-o98t | covered |
| ga-sfnj | covered |
| ga-5b9m | covered |
| ga-x4j3 | covered |
| ga-ldrg | covered |
| AC-6 | out_of_scope |

# Starter review synthesis: build-basic starter factory (workflow ga-2ea1)

This synthesis merges the three review lanes — **acceptance**
(`acceptance-review.md`, verdict **approve**), **test evidence**
(`test-evidence-review.md`, verdict **approve**), and **simplicity**
(`review-simplicity.md`, verdict **approve**) — into one deduplicated
finding list for the fix lane. Every finding keeps its source lane(s)
and is resolved against the implementation worktree recorded in
`starter-review-context.md` § Implementation Worktrees (never the
launcher checkout at `/home/roman/workspace/gascity.el`).

## Verdict

**approve** — all three lanes approved independently; zero required
fixes, zero missing proof blocks. Two findings are *missing evidence*
(both low, procedural) and four are *residual risks* (observations and
optional polish). The fix lane may act on any of them, but none blocks
the publish stage.

## Findings

### Required fixes

**None.** All three lanes approved with no blocking findings. Every
gate re-run matched the recorded outcomes (compile clean; 322/323 tests
green per worktree, the ±1 delta being the per-branch doc-only vs
one-new-test difference; the two new ERTs pass 1/1; `make -C doc`
clean; live TRAMP re-runs inside the AC-2 bound).

### Missing evidence

**ME-1 — W1's pooling experiment script is ephemeral** *(source lane:
test evidence, observation 1; W1, anchor ga-o98t)*

- Class: missing evidence, low.
- Anchor: `/tmp/w1-pooling-experiment.el` — cited as W1's first
  verification command in `plans/tramp-history-flood/implementation-summary-ga-o98t.md`,
  but not preserved under the artifact tree, so the measurement is not
  byte-for-byte reproducible from the artifacts alone.
- Mitigation already in place: W5's ERT
  (`gascity-test-remote-async-reads-pool-connections`, in
  `/home/roman/workspace/gascity.el/worktrees/ga-ldrg/lisp/test/gascity-test.el`)
  and the README live procedure cover the same regression class, and
  W1's results are fully recorded with before/after values.
- Suggested action (optional, for future runs): copy experiment scripts
  into `plans/<workflow>/` next to the summary that cites them.

**ME-2 — Stale doc artifacts can make the W4 `make -C doc` proof a
no-op** *(source lane: test evidence, observation 2; W4, anchor
ga-5b9m, worktree `/home/roman/workspace/gascity.el/worktrees/ga-5b9m`)*

- Class: missing evidence, low.
- Anchor: `make -C doc` in
  `/home/roman/workspace/gascity.el/worktrees/ga-5b9m` — in the
  evidence lane's re-run the recorded command completed without
  rebuilding (stale `doc/gascity.info` / `gascity.html`); a forced
  fresh build passed clean.
- Suggested action (optional, for future runs): record the proof as
  `make -C doc clean all` (or remove generated files first) so the
  command cannot pass vacuously.

### Residual risks

**RR-1 — W3's history override is connection-granular, not
buffer-granular** *(source lane: acceptance, observation 1; W3, anchor
ga-sfnj, worktree `/home/roman/workspace/gascity.el/worktrees/ga-sfnj`,
commit `3e3fc20`)*

- Anchor: `lisp/gascity-remote.el` (history hygiene section) and
  `lisp/gascity-context.el` (`gascity-view-get-buffer-create`), both
  relative to `/home/roman/workspace/gascity.el/worktrees/ga-sfnj`.
- The buffer-local `tramp-remote-process-environment` append satisfies
  AC-4 exactly (ERT
  `gascity-test-remote-connection-local-histfile-override` asserts it),
  but TRAMP exports the environment once, at connection setup. Two
  boundary nuances: (a) if a *non-gascity* buffer opens the connection
  first, the override never reaches the connection shell — this timing
  applies to the async `make-process` path as well, not only the sync
  path named in the W3 summary's risks; (b) once exported,
  `HISTFILE=/dev/null` is visible to the whole shared connection, so
  other non-gascity buffers on that connection also get it (the
  docstring's "user's other TRAMP usage keeps the untouched global
  value" is true of the variable, not strictly of the connection
  shell).
- Assessment: benign for the target behavior (silencing history) and
  the plan's W3 scoping intent is honored (read at gascity's own
  invocation sites). No code change required. Suggested action
  (optional): note the connection-granular nuance in the *TRAMP shell
  history hygiene* section of
  `/home/roman/workspace/gascity.el/worktrees/ga-sfnj/doc/gascity.texi`.

**RR-2 — AC-2's live connection bound is looser than observed and
environment-dependent** *(source lanes: acceptance, observation 2 +
test evidence, observation 3 — deduplicated, they are the same
observation; W2/W5, anchors ga-x4j3 / ga-ldrg, worktrees
`/home/roman/workspace/gascity.el/worktrees/ga-x4j3` and
`/home/roman/workspace/gascity.el/worktrees/ga-ldrg`)*

- Anchor: `lisp/test/gascity-test-remote-async-reads-pool-connections`
  and the README "Connection-count verification (live city)" bullet,
  relative to `/home/roman/workspace/gascity.el/worktrees/ga-ldrg`.
- The at-most-2 bound is the requirements' own bound; observed deltas
  across W1/W2/W5 and both lanes' re-runs were 0 or 1 (the burst's own
  pooled-connection establishment). The live count is also host-noise
  sensitive (the user's Emacs daemon keeps its own ssh connections).
- Assessment: consistent with the diagnosis (one login per new
  connection, zero per read); no action. Keep the loose bound for
  stability on slow environments.

**RR-3 — The pooling conclusion is stated in full in three places and
must drift together** *(source lane: simplicity, finding S1; W2,
anchor ga-x4j3, worktree
`/home/roman/workspace/gascity.el/worktrees/ga-x4j3`, commit
`15b33b7`)*

- Anchors (all relative to
  `/home/roman/workspace/gascity.el/worktrees/ga-x4j3`):
  `lisp/gascity-remote.el` file commentary ("Connection reuse"
  bullet), `lisp/gascity-reader.el` `gascity-reader-read-async`
  docstring, and `README.md` "Remote cities (TRAMP)" section.
- A future Emacs/TRAMP default change requires editing all three in
  step. No correctness problem today, but the drift risk is the
  highest-value of the optional items.
- Suggested action (one-commit-sized): keep
  `lisp/gascity-remote.el`'s commentary as the full authority; trim
  the docstring and README bullets to one sentence plus a
  cross-reference ("see `gascity-remote.el`'s commentary"). No
  behavior change.

**RR-4 — Cosmetic and readability polish in user-facing prose**
*(source lane: simplicity, findings S2 + S3 — two independent items,
kept separate below)*

- **RR-4a (S2)** — internal workflow IDs in user-facing README: line
  ~158 of `/home/roman/workspace/gascity.el/worktrees/ga-x4j3/README.md`
  reads "Measured on a live `/ssh:localhost:` city (W1, REQ-002)".
  External readers cannot resolve "W1"/"REQ-002". Suggested action:
  drop the parenthetical (the sentence stands without it), or point at
  `plans/tramp-history-flood/` if that directory ships with the repo.
  Internal workflow IDs in Lisp comments/docstrings are fine (repo
  convention).
- **RR-4b (S3)** — cosmetic `\n` escape mid-docstring: line ~153 of
  `/home/roman/workspace/gascity.el/worktrees/ga-sfnj/lisp/gascity-remote.el`
  ("…inner shells spawned for the\n`make-process
  :file-handler' reads…") embeds a literal `\n` escape where every
  neighboring line uses a real newline. Renders correctly in
  `describe-function`; source inconsistency only. Suggested action:
  break the line normally.

Items explicitly *not* carried forward (reviewed and left as-is by the
simplicity lane, recorded here so the fix lane does not re-litigate
them): the optional BUFFER argument of
`gascity-remote-silence-shell-history`; the W5 test's
`done`/`pending` counter overlap; the W4 recipe appearing in both
`doc/gascity.texi` and the `docs/qa/` dogfood note.

## Verification

This is a synthesis artifact: it adds no new measurements. Its
inputs are the three lane reports (hashes in front matter), each
already carrying its own verification section, and the worktree table
in `starter-review-context.md` § Implementation Worktrees. The
synthesis re-checked, per finding, that:

- the source lane attribution matches the cited report text;
- every relative filename is resolved against the owning
  implementation worktree (RR-1/RR-4b → `worktrees/ga-sfnj`;
  RR-3/RR-4a → `worktrees/ga-x4j3`; ME-1 → W1's diagnosis-only anchor
  `ga-o98t` at `9fb54c5`; ME-2 → `worktrees/ga-5b9m`), never the
  launcher checkout;
- the deduplication did not merge findings from different mechanics
  (RR-2 is the only merge: acceptance observation 2 and test-evidence
  observation 3 state the same bound-vs-observed fact);
- no finding contradicts a lane verdict (all three lanes approved;
  this synthesis preserves that verdict and classifies nothing as a
  required fix).

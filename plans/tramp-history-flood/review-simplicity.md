# Starter review — simplicity and maintainability (bead ga-qgyl)

schema: gc.build.review-lane.v0 (starter factory simplicity lane)
workflow: ga-2ea1 (build-basic, plans/tramp-history-flood)
reviewer: gc.design-implementation-reviewer (starter simplicity lane)
scope: the four implementation worktrees listed in
`starter-review-context.md` § Implementation Worktrees (W2 ga-x4j3,
W3 ga-sfnj, W4 ga-5b9m, W5 ga-ldrg; W1 ga-o98t changed no files).
All diffs were read against base `9fb54c5` with `git diff 9fb54c5..HEAD`
in each worktree; `pwd -P` verified per worktree.

## Verdict: approve

No required fixes. The implementation is small, well-bounded, and easy to
follow: one scoped code change (W3, three small named helpers with a
documented append-only contract), one test per change, and the rest is
docs. Nothing hides a second behavior behind an abstraction, and no
worktree reached beyond its declared files.

## What reads well (kept beginner-friendly on purpose)

- **W3's three-function split is justified, not ceremonial.**
  `gascity-remote-history-silencer` (the literal entry),
  `gascity-remote-history-environment` (pure, idempotent append), and
  `gascity-remote-silence-shell-history` (buffer-local application) each
  have one job, and the pure middle function is what the ERT asserts
  directly. A new reader can trace the whole feature in one screenful.
- **The scoping decision is explained where a reader would ask.** The
  docstrings and the W3 summary record *why* a criteria-registered
  connection-local profile was rejected (it would leak into every remote
  buffer on the host). That is exactly the kind of comment that prevents
  a well-meaning future "simplification" back into the leaky design.
- **No accidental broad changes.** Each worktree's diff touches only its
  declared files; W2 is comments/docstrings/docs only; W4 is docs only;
  W5 is one test plus one README bullet. Nothing re-architected the
  read path or the buffer factory.
- **The W5 test states its proxy honestly.** Its docstring says it counts
  live TRAMP connection processes over the mock-remote boundary and names
  the README procedure as the real-transport half — a maintainer is not
  left guessing what the assertion proves.

## Findings (suggested, none required)

Each is a small, concrete improvement; none blocks approval. Listed in
descending order of maintainer value.

### S1 — One authority for the pooling conclusion (ga-x4j3, W2)

The same measured conclusion ("default tramp-sh handler pools all async
reads on one ssh connection; direct-async spawns a fresh ssh per read;
gascity never enables direct-async") is stated in full in **three**
places:

- `lisp/gascity-remote.el` file commentary ("Connection reuse" bullet),
- `lisp/gascity-reader.el` `gascity-reader-read-async` docstring,
- `README.md` "Remote cities (TRAMP)" section.

All three cite the same W1 measurement, so they must drift together when
a future Emacs/TRAMP changes the default handler. Smallest useful fix:
keep `gascity-remote.el`'s commentary as the full authority and trim the
docstring and README bullets to one sentence + a cross-reference
("see `gascity-remote.el`'s commentary"). No behavior change.

### S2 — Internal workflow IDs in user-facing README (ga-x4j3, W2)

`README.md` line ~158 now reads "Measured on a live `/ssh:localhost:`
city (W1, REQ-002)" — the first time internal workflow IDs (work-item
"W1", requirement "REQ-002") appear in the user-facing README. A reader
who is not part of this factory run cannot resolve them. Smallest useful
fix: drop the parenthetical (the sentence stands without it), or point at
`plans/tramp-history-flood/` if the plan directory ships with the repo.
The same IDs are fine in Lisp comments/docstrings — that is established
repo convention.

### S3 — Cosmetic `\n` escape mid-docstring (ga-sfnj, W3)

`lisp/gascity-remote.el` line ~153: `...spawned for the\n\`make-process
:file-handler' reads...` — the docstring uses real newlines everywhere
else but one embedded `\n` escape here. It renders correctly in
`describe-function`; it is only an inconsistency in the source. Smallest
fix: break the line normally like the surrounding lines.

### Observations, no change needed

- `gascity-remote-silence-shell-history`'s optional BUFFER argument is
  redundant with its only caller (`gascity-view-get-buffer-create` is
  already inside `with-current-buffer buf`), but the explicit argument
  makes the helper self-contained and keeps the call site readable;
  leave it.
- The W5 test's `done`/`pending` counters overlap (pending decrements on
  both callbacks, done counts successes), but the pair of final
  assertions ("all 10 completed, 0 errors") reads clearly; leave it.
- The W4 recipe appears in both `doc/gascity.texi` and
  `docs/qa/2026-09-21-bashrc-guard-recipe.md`; the QA note is a dogfood
  report per repo convention, not a competing authority. Leave it.

## Bottom line

Approve. If the synthesis/apply step picks up S1–S3, they are each
one-commit-sized; if it ships without them, nothing here will rot into a
correctness problem.

# F9 decision — formula-launch nudge

- Bead: `ga-ls1hw` (follow-up to `ga-x4nt`, WI-11 post-approval lane)
- Status: decided
- Finding: `docs/qa/2026-09-27-wi11-sling-redesign-e2e.md` §Findings F9
  (restated in `docs/qa/2026-09-30-sling-post-approval-findings.md`
  §Remaining)
- Design: `design.md` (this directory), REQ-011 / F-5

## The finding

The sling redesign renders the Routing flags group only on the settled
plain shape (design F-5); the formula shape exposes no routing flag and
`gascity-sling-formula--command` never threads one
(`gascity-sling--run`'s formula branch ignores
`gascity-sling--parse-transient-args`).  A formula launch to an idle
agent therefore sits until someone nudges it by hand — the WI-11 e2e
pass had to nudge the mayor before the pancakes workflow moved.

## What gc actually allows

`gc sling --help` lists `-n, --nudge` as a flag of the same command for
every shape ("nudge target after routing"); nothing in gc restricts it
to the plain route.  `-t, --title` is even documented "(with --formula
or --on)".  F-5 is a *gascity UI* decision — the redesign chose not to
surface the flag group on the formula shape — not a gc constraint.

## Decision

**Expose `--nudge` as an opt-in routing flag on the formula shape; do
not nudge automatically.**

The formula shape gains one `-n Nudge target after routing` switch when a
target is set, and the flag is threaded through the formula command.
The plain shape is unchanged.  The remaining suggested remedy — making
the wait visible — is already satisfied: the run view surfaces the idle
run in the cockpit's Needs-you, so no new "wait" affordance is designed
here.

## Rationale

- **Nudging another agent is a user decision, not a launch side effect.**
  The plain path has always offered `--nudge` as opt-in; the daemon
  nudges routed work only when told to.  An unconditional formula nudge
  would be the one place gascity silently wakes an agent the caller did
  not ask to wake — surprising for a pool, a cross-rig target, or an
  agent the caller deliberately left idle.
- **Opt-in removes the friction F9 reports** without changing any
  default: a user who knows the target is asleep flips `-n` before `s`
  instead of nudging from another buffer afterwards.  Users who want the
  old behavior get it by leaving the switch off.
- **It reuses the existing affordance.**  `--nudge` is already parsed by
  `gascity-sling--parse-transient-args` and named by the plain shape's
  switch; the formula path just stops discarding it.  No new gc surface,
  no new setting.
- **It keeps F-5's spirit.**  The full plain-only flag group (`-c`, `-a`,
  `-m`, `-t`) stays off the formula shape; only the one flag F9 needs is
  carved out.

## Implementation sketch (follow-up bead)

Small, single-purpose change:

- `lisp/gascity-action.el`, `gascity-sling--children-specs`: render the
  `-n/--nudge` switch on the formula shape (and keep the existing plain
  group unchanged).
- `lisp/gascity-action.el`, `gascity-sling--run`: in the formula branch,
  parse the transient args with `gascity-sling--parse-transient-args` and
  pass `:nudge` into `gascity-sling-formula--command` /
  `gascity-sling-formula--dispatch`.
- `lisp/gascity-formula.el`, `gascity-sling-formula--command`: add the
  `:nudge` initarg to the built `gascity-command-sling` for both the
  `--formula` and `--on` shapes.
- `lisp/test/gascity-sling-test.el`: a unit test that the formula command
  carries `--nudge` when the switch is on (and not when off), plus a
  children-specs test that the switch renders on the formula shape.

Review is a design-implementation-reviewer and a design-test-risk-reviewer
pass — the change is short but the reviewer should confirm the flag is
threaded to `--on` as well as `--formula`, and that the default (off) is
untouched.

## Adjacent gap, not part of this decision

`gc sling -t/--title` is documented for `--formula`/`--on`, yet the
formula shape exposes no title field either.  That is a separate design
question (the formula path's root title currently comes from gc) and is
deliberately left out of this bead's scope.
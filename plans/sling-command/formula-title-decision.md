# Formula-shape `--title` decision — wisp root title vs `artifact_root` slug

- Bead: `ga-ybtm3` (F9-adjacent gap filed off
  `f9-formula-nudge-decision.md` §"Adjacent gap, not part of this
  decision")
- Status: decided
- Design: `design.md` (this directory), REQ-011 / F-5, as amended by
  F9 (`f9-formula-nudge-decision.md`)

## The finding

`gc sling --help` documents `-t, --title string — wisp root bead title
(with --formula or --on)`, and the gascity command layer already models
it: `gascity-command-sling` has a `:title` slot
(`--title`, string).  The plain shape renders
`("-t" "Wisp root title" "--title=")` and
`gascity-sling--parse-transient-args` threads it into the built command
(`lisp/gascity-action.el`).  The formula shape renders only the
F9-carved `-n`, and `gascity-sling-formula--command` never takes a
`:title`.  So the flag is documented and modelled but unreachable from
the formula shape — the same "documented but not carved out" class as
F9.

The design question is the collision of two title-ish concepts:

- **`--title`** is gc's *wisp root bead* title (what the routed root
  bead is called); with `--formula` it overrides the recipe-derived
  root title, with `--on` it names the attached wisp's root.
- **`artifact_root`** is a *formula variable* naming a
  `plans/<slug>/` directory, seeded by `gascity-sling--title-slug`
  from the work bead's title (then freeform work text, then the
  formula name) — never from gc's root title (`REQ-006`,
  `design.md` §Menu mockups / `artifact_root` slug source).

## What gc actually allows

Nothing in gc restricts `--title` to the plain route; the help text
names `--formula` and `--on` explicitly.  F-5 is a *gascity UI*
decision — the redesign chose not to surface the flag group on the
formula shape — not a gc constraint.  F9 already established the
carve-out precedent: one flag the gap needs, `-n`, is surfaced on the
formula shape while `-c`/`-a`/`-m` stay plain-only.

## Decision

**Expose `-t/--title` as an opt-in routing flag on the formula shape;
do not re-seed `artifact_root` from it.**

The formula shape's "Routing flags" group gains
`-t Wisp root title --title=` next to the F9 `-n` switch, and the flag
is threaded through the formula command for both `--formula` and
`--on`.  It is off by default: unset, gc's recipe-derived root title
stands, exactly as today.  The `artifact_root` seed is untouched — it
continues to derive from the work bead's title / freeform work text /
formula name, never from `--title`.

## Rationale

- **It completes the documented surface.**  `gc` documents `--title`
  for `--formula`/`--on` and the slot is already modelled; the formula
  shape just stops discarding it.  No new gc surface, no new setting.
- **Opt-in changes no default.**  A user who wants gc's recipe title
  leaves the field empty; `-t` only appears in the built command when
  a non-blank title is entered.  The fixture commands stay identical.
- **The two concepts stay distinct.**  They have different consumers:
  `--title` names the routed root bead, `artifact_root` names a
  directory under `plans/`.  Deriving the slug from `--title` would let
  a change that only renames the root bead silently move the plans
  directory, and would break `REQ-006`'s rule that the slug is
  human-recognizable work-title text (never a bare id).  Keeping them
  decoupled means `-t` can be added without touching the seeded slug,
  and the formula author keeps `artifact_root` editable like any other
  variable.
- **It keeps F-5's spirit.**  Only the one flag the gap needs is carved
  out; the rest of the plain flag group (`-c`, `-a`, `-m`) stays
  plain-only.
- **It is the F9 shape again.**  Same rendering rule (the carved-out
  group appears once a formula and a target are known), same threading
  path (the plain parser, then the formula command builder), same
  tests.

## Interaction, spelled out

| Question | Answer |
|----------|--------|
| Does `--title` override gc's recipe root title? | Yes — that is gc's documented semantics; gascity only forwards the flag. |
| Does `--title` re-seed `artifact_root`? | No.  The slug keeps deriving from the work bead title → freeform work → formula name. |
| Is the flag on by default? | No.  Unset emits no `--title`; gc's default root title stands. |
| What does an empty `--title=` do? | Nothing — the builder emits the flag only for a non-blank title, so the default command is byte-identical. |
| Does it apply to `--on`? | Yes — same as `--formula`, matching the gc help text. |

## Implementation sketch (follow-up bead `ga-5i33u`)

Filed as `ga-5i33u`, routed to
`gascity.el/gc.implementation-worker`.  Small, single-purpose change
mirroring the F9 commit (`ga-iwukj`, `86a577b`):

- `lisp/gascity-action.el`
  - `gascity-sling--children-specs`: add
    `'("-t" "Wisp root title" "--title=")` to the formula "Routing
    flags" vector (the F9 group), and leave the plain group unchanged.
  - `gascity-sling--run`: in the formula branch, read `:title` from
    `(gascity-sling--parse-transient-args args)` and thread it into
    `gascity-sling-formula--dispatch` alongside `:nudge`.
  - `gascity-sling--full-preview`: read `:title` and thread it into
    both the dry-run `gascity-sling-formula--command` and the launch
    `gascity-sling-formula--dispatch`, so `P` previews exactly what
    `s` slings.
- `lisp/gascity-formula.el`
  - `gascity-sling-formula--command`: add an optional `title`
    parameter after `nudge`; in both the `--formula` and `--on`
    builds append `(when (gascity-formula--nonblank title)
    (list :title title))`.
  - `gascity-sling-formula--dispatch`: add the `title` parameter and
    pass it through.
- `lisp/test/gascity-sling-test.el`
  - `gascity-test-sling-formula-command-carries-title`: `--formula`
    and `--on`, off then on; and assert no `--title` for a blank
    value.
  - `gascity-test-sling-run-threads-formula-title`: the formula
    branch parses `--title=` and passes it on.
  - `gascity-test-sling-full-preview-formula-carries-title`: dry run
    and launch both carry it.
  - Extend a children-specs test to assert `-t`/`--title=` renders on
    the formula group when a target is known and the plain group is
    unchanged.
  - No change to the slug tests: `gascity-sling--title-slug` is not
    touched, and an added assertion that it ignores a wisp `--title`
    is optional (the function takes no such argument).
- `doc/gascity.texi`
  - `Routing flags` table and the formula-shape sentence: note `-t`
    is carved out for the formula shape alongside `-n`.
  - `Typed variables` / `artifact_root`: state that the slug derives
    from the work title and is independent of `--title`.
- `plans/sling-command/design.md`
  - Amend the F-5/F9 bullet to name `-t` as the second carved-out
    formula flag.

Review is a design-implementation-reviewer and a design-test-risk-reviewer
pass — short change, but the reviewer should confirm `--title` reaches
`--on` as well as `--formula`, that the blank-title guard keeps the
default command byte-identical, and that the `artifact_root` seed is
untouched.

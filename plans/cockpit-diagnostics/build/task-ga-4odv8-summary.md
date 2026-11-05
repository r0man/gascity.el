---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-pgmo0
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
    - path: beads/ga-4odv8
      hash: bead:ga-4odv8
      ids:
        - REQ-004
    - path: plans/cockpit-diagnostics/build/requirements.md
      hash: sha256:f1264856fbd255221baec68edccf8d18a4da7c29c09ea2067277d83f15a5451c
    - path: plans/cockpit-diagnostics/build/implementation-plan.md
      hash: sha256:f7772bfc777b26b0a7c8f7a6630c78ebc8df37fef522eda1cfb377d483dd28f8
    - path: plans/cockpit-diagnostics/build/plan-review.md
      hash: sha256:efa486caeb4db8aff2bf5bbac54d2c3ff6a0873cbab2ba3a8b456616ab803327
    - path: lisp/gascity-event.el
      hash: sha256:9ed4965fa7efa5e5cdd0b3a18e6eb489c0f4a40edfd323b44587e89bf736d068
    - path: lisp/test/gascity-comms-test.el
      hash: sha256:7d241aab9e8df3e965ad5203f43552c09405c3b82853d6007f0f84ec8f4f974e
  coverage:
    - id: REQ-004
      status: covered
---

# Implementation summary — Events detail: bead `close_reason` and `gc.failure_class` (ga-4odv8)

## Summary

Work item W5 of the cockpit-diagnostics batch is implemented in worktree
`worktrees/ga-4odv8` (source anchor `ga-4odv8`, drain member of input convoy
`ga-58ird`), commit `bf470e9` ("fix(events): bead close reason and failure
class in the event drawer (ga-4odv8)"), on top of `origin/main` `4ed9d40`.

`gascity-event-fields` now keeps the one-line payload-bead summary
(`bead  <id> <title> (<status>)`) and, at the bead's position in the field
order, adds two more `key value` lines when the payload bead carries them:

- `close_reason  <bead close_reason>` when it is a non-empty string;
- `gc.failure_class  <bead metadata gc.failure_class>` when it is a non-empty
  string.

Nothing else in the payload order moves; the existing dedupe (event-level key
wins, each key once) and the 12-line drawer cap are unchanged, and the new
pairs sit at the bead's position so they are not the first thing the cap drops.
Empty/nil values emit no line at all - never an empty value column.

Values are still rendered by `gascity-event--value`, which now takes an
optional WIDTH (default 60) and truncates through `gascity-ui-truncate`
instead of `truncate-string-to-width`. A cut value therefore keeps its full
text in `help-echo` (the old code silently dropped it), including the bead
summary line, which was truncated before this change too.

The value budget is the cockpit drawer's inner width minus the key column and
the two-space separator: `(max 20 (min 60 (- drawer-inner 2 key-width)))`.
`drawer-inner` is `gascity-dashboard--drawer-width` when that helper is
present (the fitting primitive of W1, which has not landed on `origin/main`
yet), else `gascity-dashboard--width` minus the 4-column `  │ ' drawer prefix,
else the measured 74. Both dashboard symbols are `defvar`-declared here, so
there is no load-order cycle and the budget becomes W1's number once W1
merges: at a 16-column key column (`gc.failure_class`), the budget is
74 - 2 - 16 = 56, so a rendered `key  value` line is exactly 74 inner columns
- 78 columns with the drawer prefix, i.e. the cockpit's full width. This is
the F5 defect from `plan-review.md` fixed: the planned fixed 60-column value
would have produced an 82-column cockpit line for `gc.failure_class`. Where
the drawer budget is wider than 60 (short key columns), the 60-column cap
still applies, so no value grows beyond its old width.

## Intended Behavior

Per REQ-004/AC-4 of
`plans/cockpit-diagnostics/build/requirements.md` and
`implementation-plan.md` §5 ("Events detail fields (REQ-004)"):

- An operator inspecting a `bead.closed` or `bead.updated` event sees why the
  run ended - `close_reason` and the failure class - in the same Events detail
  drawer that already shows `session_id` and `step_id`, without opening the
  bead view or a raw log (US-5).
- Both lines appear only when the payload bead actually carries a non-empty
  value; an event without them renders no extra, empty or blank line.
- A key already present at the event level is not duplicated: the payload
  bead's copy is dropped by the existing first-key-wins dedupe, and its value
  is not displayed twice.
- Long values are cut with `…` to fit the cockpit's 78-column drawer and carry
  the untruncated text in `help-echo` on the cut value, so hovering/echoing the
  line shows the whole reason.
- Rendering stays pure over the event alist already in hand: no new `gc`
  invocation, no store/reader/scheduler change (dashboard-v3 D9, TS-6).

Coverage matrix (matches `trace.coverage`):

| ID | Status |
| --- | --- |
| REQ-004 | covered |

## Changed Files

- `lisp/gascity-event.el`
  - `gascity-event--drawer-value-width` (new): the per-key value budget from
    the cockpit drawer width, with the `gascity-dashboard--drawer-width` /
    `gascity-dashboard--width` fallback chain documented above.
  - `gascity-event--value`: optional WIDTH, `gascity-ui-truncate` for the cut
    (full value in `help-echo`).
  - `gascity-event--bead-why-fields` (new): the `(close_reason . …)` /
    `(gc.failure_class . …)` pairs of a payload bead, non-empty strings only.
  - `gascity-event-fields`: payload bead summary followed by those pairs; the
    final `key value` renderer passes the drawer budget; docstring updated.
- `lisp/test/gascity-comms-test.el`
  - `gascity-comms-test--closed-bead-event` inline payload plus three small
    lookup helpers (the captured fixtures carry neither field - plan-review
    R5, so the payload is built inline rather than claimed as fixture cover).
  - `gascity-test-comms-event-drawer-close-reason-and-failure-class` (AC-4):
    both lines present after the bead summary, visible text cut with `…`, the
    full `close_reason`/`gc.failure_class` in `help-echo`, and every rendered
    cockpit drawer line (`gascity-dashboard--drawer`) within the 78-column
    view.
  - `gascity-test-comms-event-drawer-no-why-lines-when-absent` (AC-4):
    a bead without the two fields adds no line, no empty value, no blank line.
  - `gascity-test-comms-event-drawer-why-key-once` (AC-4): an event-level
    `close_reason` wins and appears exactly once with its own value.
- `plans/cockpit-diagnostics/build/task-ga-4odv8-summary.md` (this artifact).

No other file changed: the Events detail buffer (`*gascity-detail*`) and the
cockpit both consume `gascity-event-fields` as before, so no dashboard,
events-view, doc or NEWS edit was needed for this item (the manual and NEWS
edits belong to W6).

## Verification

First verification command (TDD red, before the implementation), from the
worktree root:

```bash
make check
```

Observed: `Ran 964 tests, 963 results as expected, 1 unexpected` -
`FAILED gascity-test-comms-event-drawer-close-reason-and-failure-class`, i.e.
the new drawer lines were missing, as expected.

Final proof command, from the worktree root:

```bash
scripts/gate.sh
```

Observed: `>>> gate: make (byte-compile, warnings as errors)` clean, then
`Ran 964 tests, 964 results as expected, 0 unexpected` and
`>>> gate: PASS (compile clean + tests green)`.

Lint (the CI lint job's exact command):

```bash
scripts/lint.sh
```

Observed: clean - checkdoc reported no warnings for `lisp/*.el`; package-lint
is not installed locally, as its own message states (CI installs it).

Rendered sanity check of the inline AC-4 payload through
`gascity-dashboard--drawer` (batch Emacs, `-L ./lisp`):

```text
inner 74 | bead              ga-4odv8 Events detail: bead close_reason and gc.failur…
inner 74 | close_reason      environment repair required: the rig still has no git r…
inner 74 | gc.failure_class  control_dispatch_error: the controller could not reach …
drawer 78 |   │ close_reason      environment repair required: the rig still has no git r…
```

and `help-echo` on the cut values equals the full
`"environment repair required: … dispatch its workflow"` and
`"control_dispatch_error: … three dispatch attempts"` respectively.

## Remaining Risks

- **W1 integration.** `gascity-dashboard--drawer-width` (W1's fitting
  primitive) is not on `origin/main` yet, so this commit computes the same
  number from `gascity-dashboard--width` minus the 4-column prefix. Once W1
  lands, the `boundp` branch picks up `gascity-dashboard--drawer-width`
  automatically; if W1 lands defining it as a function rather than a variable
  the fallback (74) still renders correctly, and the merge should then swap
  the call for the function. Whichever branch merges second, the AC-4 width
  assertion (78 columns) holds for both.
- **`*gascity-detail*` width.** The plan says the standalone detail buffer
  "keeps the 60-column cap"; it does keep the cap (the budget never exceeds
  60), but for events with a key column wider than 12 characters the budget is
  now a few columns narrower than 60 (56 at `gc.failure_class`). That is the
  price of one shared renderer and stays within REQ-004 ("truncated at the
  drawer width"), and cut values now gain `help-echo` they did not have; a
  full-width detail window still shows the same visible text as before for
  narrow-key events. No test asserted 60 exactly.
- **Fixture drift.** The captured event fixtures carry no bead-level
  `close_reason` and no `gc.failure_class`, so AC-4 is covered by an inline
  payload (plan-review R5). If a future fixture captures these fields, the
  inline event can be dropped in favour of it.
- **Live acceptance.** The tmux/TRAMP acceptance pass named by AC-7 is the
  batch-level gate; this render-only change was verified by ERT plus the
  batch render above, not against a live city in this step.

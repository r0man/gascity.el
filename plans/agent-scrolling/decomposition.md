---
schema: gc.build.decomposition.v1
workflow:
  id: ga-jwtp
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: decompose
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/agent-scrolling/requirements.md
      hash: sha256:f06b0f208f018008eb80c7f9123d84d508da9464ab2c37ce4e322488efba1fd4
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
    - path: plans/agent-scrolling/implementation-plan.md
      hash: sha256:4f92f8d9fb9268c8685e0405814a330b34e3997c6555bb10f5a428601a8be923
      ids:
        - REQ-001
        - REQ-002
        - REQ-003
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-010
        - REQ-011
        - REQ-012
        - REQ-013
        - REQ-014
    - path: docs/DESIGN-agent-scrolling.md
      hash: sha256:f099424db8379e20daf6d23fd7399db65fd25c3c2d7e7dea6fb8f92f984c0870
    - path: docs/qa/2026-09-29-agent-scroll-mouse-experiments.md
      hash: sha256:d77552fa7a3f40807b11ffb2a71b79663e7e979c1673196f7c4b25e1fc9dbe1a
  coverage:
    - id: REQ-001
      status: covered
    - id: REQ-002
      status: covered
    - id: REQ-003
      status: covered
    - id: REQ-004
      status: covered
    - id: REQ-005
      status: covered
    - id: REQ-006
      status: covered
    - id: REQ-007
      status: covered
    - id: REQ-008
      status: covered
    - id: REQ-009
      status: covered
    - id: REQ-010
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-014
      status: covered
---

# Decomposition — Agent buffers: transparent mouse + Emacs scrolling

## Summary

The approved plan (phases P0–P3) decomposes into **four runnable
implementation work items** on a single dependency chain: the tmux-side
mouse ensure + bottom-cancel binding (WI-1), the
`gascity-terminal-scroll-mode` keyboard layer with its translation table
and per-backend adapters (WI-2), wheel translation for backends that do
not report mouse (WI-3), and documentation plus the live TRAMP e2e
acceptance pass and gate (WI-4). The order follows the plan's phase
sequencing (P0 and P1 independent, P2 builds on P1's map, P3 closes);
each item owns the tests for its slice per the house convention (ERT
stubs the process boundary with `cl-letf`; no live processes in unit
tests). All changes stay in `lisp/gascity-terminal.el`, its test files,
`doc/gascity.texi`, and `docs/qa/`; no dashboard, list, or session-detail
view is touched.

## Selected Downstream Formulas

The drain policy on the workflow root is `separate`, so the
implementation convoy drains through the following formulas (workflow
root `ga-jwtp` metadata `gc.var.*`):

- **Implementation drain:** `do-work` (formula `implement`,
  `drain_policy == separate`) — one implementation session per convoy
  bead, running under `gc.implementation-worker`.
- **Per-item fallback:** `do-work-item` (`gc.var.implementation_item_formula`)
  is the single-lane item formula for a `same-session` drain; it is not
  active under the recorded `separate` policy but each bead satisfies
  its contract anyway (self-contained work item with its own
  verification).
- **Code review:** `review` (`gc.var.code_review_formula`).
- **Review fix loop:** `fix-loop-base` (`gc.var.review_fix_formula`).

Each work item below carries its own expected files, verification
expectations, and requirement/plan traceability so any implementation
formula can drain it without knowing the planning methodology.

## Implementation Convoy

A **new** implementation convoy was created for this continuation — it
reuses neither the original launch convoy (`ga-9269`, "input convoy for
ga-ym98", recorded as `gc.var.convoy_id`) nor any planning or
workflow-control convoy, as the decompose step contract requires:

- **Convoy ID: `ga-dta4`** — title "agent-scrolling-implementation".
- Members and drain order (dependency DAG; a bead is ready when its
  dependencies close):

| WI | Bead | Title | Depends on |
|----|------|-------|------------|
| WI-1 | `ga-7xhp` | tmux mouse ensure + bottom-cancel binding (plan P0) | — |
| WI-2 | `ga-lk9y` | `gascity-terminal-scroll-mode` + translation table (plan P1) | WI-1 |
| WI-3 | `ga-lb0b` | wheel translation for non-reporting backends (plan P2) | WI-1, WI-2 |
| WI-4 | `ga-q3vr` | docs, live TRAMP e2e pass, gate (plan P3) | WI-1, WI-2, WI-3 |

The convoy identity is recorded on the workflow root bead (`ga-jwtp`) as
`gc.input_convoy_id=ga-dta4` (drain contract) and
`gc.build.implementation_convoy_id=ga-dta4` (continuation reporting);
the recorded convoy is verified distinct from the original launch convoy
`ga-9269` (`gc.var.convoy_id`) and from every workflow-control bead.

### Requirement and plan traceability

Every requirement (REQ-001…REQ-014) and plan phase maps to at least one
owning work item; each bead description restates its slice:

| Plan phase | Requirements | Work item |
|------------|--------------|-----------|
| P0 (mouse ensure + WheelDownPane binding + teardown restore, steps 1–4) | REQ-001, REQ-005, REQ-012, REQ-013 | WI-1 |
| P1 (scroll sub-mode, translation table, adapters, toggle semantics, `[scroll]` marker, steps 5–11) | REQ-002, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010 | WI-2 |
| P2 (wheel translation on vterm/term, first-notch entry bytes, step 12–13) | REQ-003, REQ-004, REQ-011 | WI-3 |
| P3 (texi + commentary docs, live TRAMP e2e pass, QA report, gate, commit, steps 14–16) | REQ-014 (+ e2e halves of REQ-001, REQ-002, REQ-008, REQ-012, REQ-013) | WI-4 |

The plan's two open questions are carried, not dropped: the `M->`
bottom-jump mechanism (requirements Open Question 1) is locked
empirically inside WI-2's translation table; the wheel notch line count
(Open Question 2) is a single adjustable constant owned by WI-3. The
plan-review (P2) verdict advisories, if any, are adopted at the owning
item during implementation.

## Work Items

### WI-1 — `ga-7xhp`: tmux mouse ensure + bottom-cancel binding (plan P0)

- **Requirements:** REQ-001, REQ-005, REQ-012, REQ-013.
- **Expected files:** `lisp/gascity-terminal.el` (custom
  `gascity-terminal-ensure-mouse`; `gascity-terminal--attach-script`
  gains the `set-option -t <SESSION> mouse on` fragment and the D3
  `bind -T copy-mode WheelDownPane select-pane \; if -F
  '#{==:#{scroll_position},0}' 'send -X cancel' 'send -X -N 5
  scroll-down'` fragment on the existing single
  `gascity-terminal--run-async` round trip; `gascity-terminal--status-teardown`
  gains `set-option -u mouse` and `unbind -T copy-mode WheelDownPane`,
  gated by the same custom);
  `lisp/test/` (script-fragment string assertions with the option t and
  nil, in the existing attach-script test style).
- **Formula assets:** none — this is a code work item drained by the
  implementation formula.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new attach-script/teardown fragment tests; existing terminal ERT
  suite green. Accept (from the plan): wheel scrolls a bright-lights
  transcript; wheeling to the bottom returns to the live tail; after
  buffer kill an external `tmux attach` sees default bindings.
- **Dependencies:** none (first item).

### WI-2 — `ga-lk9y`: `gascity-terminal-scroll-mode` + translation table (plan P1)

- **Requirements:** REQ-002, REQ-006, REQ-007, REQ-008, REQ-009, REQ-010.
- **Expected files:** `lisp/gascity-terminal.el`
  (`gascity-terminal-scroll-mode` + `gascity-terminal-scroll-mode-map`,
  `C-c s` toggle in `gascity-terminal-attach-map` — no §10 collision;
  pure `gascity-terminal--scroll-sequence` implementing the D1 byte
  table, with the `M->` bottom-jump mechanism locked empirically;
  per-backend raw-key adapter `gascity-terminal--send-raw` — vterm →
  `vterm-send-string`, term/ansi-term → `term-send-raw-string`, eat →
  `eat-self-input`, ghostel → `ghostel-send-key`/`ghostel-send-string`
  split, unknown backend → deactivate with an echo-area message, never
  error; optimistic + self-healing toggle: entry sends `C-b` `[`,
  re-toggle sends `q` first; `gascity-terminal--status-string` appends
  `[scroll]` while active);
  `lisp/test/` (table-driven sequence cases, adapter dispatch per
  backend major mode, toggle idempotence/self-healing, marker
  presence).
- **Formula assets:** none.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new table-driven/dispatch/toggle/marker ERT tests; existing suite
  green. The agent receives no keys while the mode is active (E9).
- **Dependencies:** depends on WI-1 (builds on the attach pre-step
  fragments it asserts against).

### WI-3 — `ga-lb0b`: wheel translation for non-reporting backends (plan P2)

- **Requirements:** REQ-003, REQ-004, REQ-011.
- **Expected files:** `lisp/gascity-terminal.el` (pure predicate
  `gascity-terminal--backend-reports-mouse-p` on the backend class;
  `<mouse-4>`/`<mouse-5>` bindings in `gascity-terminal-scroll-mode-map`
  for non-reporting backends only — first notch sends `C-b` `[` then
  3 × C-Up (≈10 lines/notch, adjustable constant per requirements Open
  Question 2), subsequent notches send only C-Up/C-Down; ghostel/eat
  native passthrough never intercepted);
  `lisp/test/` (wheel-sequence construction first notch vs subsequent;
  no-interference assertion — the map is empty of wheel bindings when
  the backend reports mouse).
- **Formula assets:** none.
- **Verification:** whole-package `eldev compile --warnings-as-errors`;
  new wheel-sequence and predicate ERT tests; existing suite green.
- **Dependencies:** depends on WI-1 and WI-2 (uses the P1 scroll-mode
  map and toggle state).

### WI-4 — `ga-q3vr`: docs, live TRAMP e2e pass, gate (plan P3)

- **Requirements:** REQ-014 (+ the e2e halves of REQ-001, REQ-002,
  REQ-008, REQ-012, REQ-013).
- **Expected files / formula assets:** `doc/gascity.texi` (scroll
  sub-mode `C-c s`, per-backend mouse behaviour,
  `gascity-terminal-ensure-mouse`); attach buffer commentary in
  `lisp/gascity-terminal.el`; new QA report under `docs/qa/`
  (suggested `docs/qa/2026-09-29-agent-scrolling-e2e.md`) recording the
  tmux-Emacs run — a bright-lights outage is recorded as a blocker in
  the QA report, never silently skipped; residual fixes only if the e2e
  pass exposes a gap.
- **Verification:** `scripts/gate.sh` green; the live e2e acceptance
  gate through `scripts/e2e-harness.sh` — fresh Emacs in tmux connected
  to `/ssh:localhost:/home/roman/bright-lights`, attach a bright-lights
  agent, drive `C-c s`, translated keys, and wheel events, assert
  host-side `pane_in_mode`/`scroll_position` after each step (E4–E8
  probes), teardown leaves default bindings for an external `tmux
  attach`; commit subject shape `feat(terminal): …` citing
  DESIGN-agent-scrolling.md and DESIGN-write-actions.md §10 where keys
  are added.
- **Dependencies:** depends on WI-1, WI-2, WI-3 (all code landed
  first).

### Skipped work

- **Async `pane_in_mode` resync of scroll-mode state** — optional
  refinement in the design, explicitly a non-goal for v1 in the
  requirements and plan; no work item carries it.
- **Emacs-buffer scrolling of attach buffers, per-notch side-channel
  `tmux send-keys` processes, non-alt-screen re-attach, backend library
  feature work (ghostel scrollback, eat mouse configuration), changes to
  dashboards/lists/session detail/status-mirror mechanics beyond the
  `[scroll]` marker** — out of scope by the requirements artifact and
  plan Non-Goals; no work item carries them.
- **New store/async verbs** — none are needed; the non-blocking verb
  guard in `lisp/test/gascity-store-test.el` requires no additions
  (REQ-014, tracked in WI-2/WI-3 verification).

### Blocked work

None at decomposition time. Every work item is runnable once its
dependencies close, and WI-1 has no upstream blocker. The only
conditional risk is the WI-4 e2e environment: if
`/ssh:localhost:/home/roman/bright-lights` is unreachable at e2e time,
WI-4 records it as a blocker in the QA report rather than skipping;
that is a runtime contingency recorded in the bead, not a blocked work
item.

## Verification

- Each work item carries its own verification expectations (above) and
  its bead description repeats them; every item ends with
  whole-package `eldev compile --warnings-as-errors` and the relevant
  ERT run.
- WI-2/WI-3 run the targeted ERT slices; WI-4 runs the full ERT suite
  via `scripts/gate.sh` and the interactive tmux-Emacs TRAMP pass —
  the acceptance gate for REQ-001/REQ-002/REQ-008/REQ-012/REQ-013
  end-to-end.
- Coverage disposition for every upstream ID:

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-002 | covered |
| REQ-003 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-010 | covered |
| REQ-011 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-014 | covered |

REQ-001 → WI-1 (tmux mouse) + WI-4 (e2e); REQ-002 → WI-2 (sub-mode +
byte table) + WI-4 (e2e); REQ-003 → WI-3 (wheel translation); REQ-004 →
WI-3 (passthrough untouched); REQ-005 → WI-1 (mouse on fragment);
REQ-006 → WI-2 (per-backend adapters); REQ-007 → WI-2 (unknown backend
fallback); REQ-008 → WI-2 (toggle semantics) + WI-4 (e2e re-sync);
REQ-009 → WI-2 (no agent-visible keys); REQ-010 → WI-2 (`[scroll]`
marker); REQ-011 → WI-3 (notch constants); REQ-012 → WI-1 (bottom
cancel) + WI-4 (e2e); REQ-013 → WI-1 (teardown restore) + WI-4 (e2e
external client); REQ-014 → WI-4 (docs + gate).

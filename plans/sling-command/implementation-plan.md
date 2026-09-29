---
schema: gc.build.plan.v1
workflow:
  id: ga-eavt
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: plan
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/sling-command/requirements.md
      hash: sha256:0e2a47803550e2b94e7205e906528df276c3689ad21166877e5861253c6f4c11
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
        - REQ-015
    - path: plans/sling-command/design.md
      hash: sha256:1a6e42cc9f27ad3f26b51c15c57f8a527dd6c871090ff55b6ea40530016328e1
    - path: plans/sling-command/menu-mockups.md
      hash: sha256:7aaca5e3f4c3fe174b7eb71ac64773536eda1cb94308d4d6ac4311e8701de935
    - path: beads/ga-emog
      hash: bead:ga-emog
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
    - id: REQ-015
      status: covered
---

# Sling Command Redesign — Implementation Plan

Implementation plan for the `build-basic` workflow rooted at bead
`ga-eavt`, producing the unified adaptive sling transient specified by
the approved design (`plans/sling-command/design.md`, approved with the
user 2026-09-27) and the signed-off menu mockups
(`plans/sling-command/menu-mockups.md`), against the verified
requirements (`plans/sling-command/requirements.md`, REQ-001…REQ-015).
The plan names the affected areas, the sequenced work items, the
risks, the test strategy, and the handoff criteria; every requirement
is covered by at least one work item (see the Coverage table).

## Summary

The current `gascity-sling-dispatch` transient works but asks questions
whose answers are derivable, exposes the dispatch shape through flags
instead of inferring it, offers untyped string entry for formula vars,
and gives no pre-launch confidence signal. This plan replaces its
layout with the mockups' staged adaptive form — **What** (`A` work, `f`
formula), **Who** (`T` agent target), **How** (typed var infixes),
**Actions** (`s P r g x q`) — with a one-sentence shape header, a live
validation footer, a full preview buffer (`P`), and a post-launch
follow offer. The `gascity-formula.el` catalog/recipe/cache machinery,
the deterministic var-key assignment, per-(formula,var) history, and
the async refresh are **retained**; the additions are shape inference,
typed-var readers, the agent roster view, client-side validation (the
bl-bdj trap, cross-store routes), and the follow offer reusing
`gascity-run-show`. Work lands in six waves on `main`, gated by
`scripts/gate.sh`, with the four-scenario end-to-end pass and the
documentation chapter produced from the same live bright-lights
session. Twelve work items (WI-1…WI-12) cover REQ-001 through REQ-015;
each is sized as one decomposition unit.

## Current System

What exists today, by area:

- **Entry and layout** (`lisp/gascity-action.el`, the `;;; Sling`
  section): `S` opens `gascity-sling-dispatch` (a `beads-define-prefix`
  whose children are generated per setup by
  `gascity-sling--children-specs` → `gascity-sling--setup-children`).
  The scope plist is `(:city :formula :target :arg)`; the header info
  line is `gascity-sling--scope-info` ("Arg: … · Formula: … ·
  Target: …"). Groups stack vertically: Formula (`-f` pick via
  `gascity-sling-dispatch-pick`, `g` refresh), Destination (`-T`
  target session read, `A` arg edit), Routing flags (`-c -a -n -m -t`),
  Actions (`s` run, `p` dry-run preview, `r` recipe preview, `x`
  reset, `q` quit), plus the picked formula's generated Variables group
  last. Single-letter reserved bindings are collected in
  `gascity-sling--reserved-keys` (`f g T A c a n m t s p r x q`).
- **Plain path**: `gascity-sling--run` reads the arg on demand
  (`read-string` seeded from the bead/convoy at point via
  `gascity-sling-formula--bead-or-convoy-at-point`) and the target via
  `gascity-action--read-session` (session completion), parses routing
  flags with `gascity-sling--parse-transient-args`, and dispatches
  through `gascity-command-act-async` (async, D9). Preview (`p`) is
  the `--dry-run` text view `gascity-sling--show-plan` on
  `gascity-action--async-text-view`.
- **Formula machinery** (`lisp/gascity-formula.el`): per-scope-key
  caches for the catalog, `gc formula list` and compiled recipes
  (`gascity-formula-catalog-cache` / `-list-cache` / `-recipe-cache`,
  keyed by `gascity-context-scope-key`); the union picker
  `gascity-formula-choices` / `gascity-sling-formula--read-formula`
  (S-1: catalog ∪ list); async refresh `gascity-formula-refresh-async`
  through the store; the enum mapping `gascity-formula--enum-metadata-keys`
  (var name → `metadata.gc.methodology` key, decision D1); shape
  detection `gascity-formula--needs-convoy` (gc's documented sling
  rule: a drain step or a `{{convoy_id}}` reference, decision D2);
  client-side validation `gascity-formula--validate-values` (required
  vars, patterns); per-(formula,var) history
  `gascity-formula--history-var`; the deterministic var-key assignment
  `gascity-sling-formula--var-key` / `--var-keys` avoiding the reserved
  set; the generated infix classes (enum / bool / string options) with
  slots carrying each var's payload; dispatch
  `gascity-sling-formula--dispatch` (validates, picks the shape by
  `needs-convoy`, `--on` requires a bead, runs async, supports dry
  run); the server-side substituted recipe preview
  `gascity-sling-formula--show-recipe` rendering steps/deps into a
  host-qualified view buffer.
- **State**: `gascity-sling--remembered` (per-city scope + infix
  values, restored at entry, cleared by `x` and a real sling — S-2);
  city pinning `gascity-sling--city-dir` with every catalog/recipe
  read pinned to the entered-from city (ga-4ia4).
- **Agent roster** (`lisp/gascity-agents.el`): the Agents view already
  builds agent rows from `gc status` + `gc session list` + `gc agent
  list` through the store (`gascity-agents--rows` over
  `gascity-dashboard--agents`), each plist carrying `:name`
  (rig-qualified, e.g. `hello-world/gc.implementation-worker`), `:rig`
  (nil ⇒ city), `:state` (`stalled/running/idle/stopped/suspended`),
  `:provider`, `:object`. No completion-facing accessor exists yet.
- **Runs view** (`lisp/gascity-run.el`): `gascity-run-show` shows the
  workflow run whose root bead id is given — the follow target.
- **Tests** (`lisp/test/gascity-sling-test.el`, seven tests):
  `gascity-test-sling-choices-union`,
  `gascity-test-sling-picker-offers-city-formulas`,
  `gascity-test-sling-picker-nothing-to-offer`,
  `gascity-test-sling-entry-prefetches-formulas`,
  `gascity-test-sling-preview-keeps-state-and-s-slings-it`,
  `gascity-test-sling-preview-is-transient`,
  `gascity-test-sling-reentry-restores-and-x-resets`. The shared suite
  (`lisp/test/gascity-test.el`) additionally pins the var machinery
  against the reserved set:
  `gascity-test-formula-sling-var-children-shapes`,
  `gascity-test-formula-sling-var-children-nil-formula-degrades`,
  `gascity-test-sling-var-key-deterministic`,
  `gascity-test-sling-var-keys-stable-and-unique`, and carries the
  layout-coupled transient tests the rewrite must port
  (`gascity-test-sling-unified-wiring`, `-unified-layout`,
  `-target-set-and-header`, `-arg-edit-re-setups-in-place`,
  `-dispatch-target-fallback`, `-plain-path-unchanged`,
  `-preview-dry-run-paths`, `gascity-test-formula-sling-dispatch-shapes`,
  `gascity-test-formula-sling-preview-fresh-show`, the city-pinning set
  `-city-dir-pins-entered-from-city`, `-dispatch-prefix-seeds-city-dir`,
  `-dispatch-pick-pins-city-dir`, `-children-specs-read-recipe-pinned`,
  `-dispatch-suffixes-run-pinned`, `-reserved-keys-complete`),
  while the command-line/cache tests
  (`-sling-command-line`, `-rich-command-line`, `-parse-transient-args`,
  `-on-command-line`, the `gascity-test-formula-*` cache/enum/history
  set, `gascity-test-store-formula-refresh-async-swaps-caches`,
  `gascity-test-remote-sling-plan-view`) exercise the retained plumbing.
- **Docs**: `doc/gascity.texi` carries a four-line Sling item under
  "Dispatch and lifecycle"; `docs/DESIGN-write-actions.md` §10
  documents the current unified transient (which this redesign
  supersedes).

Gaps against the requirements: the plain path prompts for derivable
answers (REQ-001/005); the shape is invisible until dispatch decides
it (REQ-002); the work picker is a plain `read-string` (REQ-003);
`--formula`/`--on` selection is implicit in dispatch, not displayed
(REQ-004); Who is session completion, not agent-centric, with no
derived default (REQ-005); vars are enum/bool/string only — no file,
directory, agent or numeric readers (REQ-006); there is no live footer
(REQ-007), no client-side preview buffer (REQ-008), no follow offer
(REQ-009), and no pre-launch validation of the known gc failure modes
(REQ-010). The layout does not match the signed-off mockups (REQ-011).

## Proposed Implementation

### Affected areas

| Area | Change | Work |
| --- | --- | --- |
| `lisp/gascity-formula.el` | shape inference + header sentence; typed var infix subclasses and heuristics; bl-bdj / cross-store / missing-piece predicates; title-slug helper | WI-1, WI-2, WI-5 |
| `lisp/gascity-agents.el` | completion-facing roster accessor: agents grouped city-first then per rig, annotated with scope and live state; scope classification | WI-2 |
| `lisp/gascity-action.el` | adaptive staged layout per the mockups; smart work picker `A`; agent-centric Who `T`; derived default; live footer; `P` preview buffer; follow offer; new reserved-key set | WI-3, WI-4, WI-6, WI-7, WI-8, WI-9 |
| `lisp/test/gascity-sling-test.el` | the seven tests ported; new tests for inference, heuristics, defaults, warnings, follow | WI-10 |
| `lisp/test/gascity-test.el` | var/reserved-key tests updated for the new key set | WI-10 |
| `doc/gascity.texi`, `doc/screenshots/`, `docs/DESIGN-write-actions.md` | full sling chapter, screenshots, §10 update | WI-12 |
| `docs/qa/` | e2e dogfood report of the four scenarios | WI-11 |

### Work items

**WI-1 — Shape inference and the one-sentence header** (REQ-001,
REQ-002). Pure functions in `gascity-formula.el`: a
`gascity-sling--shape` over (work, formula) returning `plain` /
`formula` / `on` (formula nil ⇒ plain; formula + work ⇒ `--on`;
formula without work ⇒ `--formula`), and a header-sentence renderer
with the mockups §1–§4 wording ("Sling bead bl-5ja to mayor", "Run
pancakes (formula) on mayor", "Run build-basic against bead bl-5ja,
drained by …"). The sentence's "drained by" clause consults
`gascity-formula--needs-convoy` on the cached recipe. Display only:
dispatch keeps `gascity-formula--needs-convoy` as the authoritative
shape rule, and a convoy-requiring formula with no work becomes a
footer warning (mockup §5c) rather than a new blocking prompt.
`gascity-sling--scope-info` is replaced by the sentence. Unit tests
pin every shape × work-presence combination and the exact mockup
sentences.

**WI-2 — Roster accessor and the client-side validators** (REQ-005,
REQ-010). In `gascity-agents.el`: a completion-facing accessor over
the existing loaders producing `(name . annotation)` candidates
city-first then per rig, annotated `<rig|city> · <state>` with
`gascity-agents--state-label`, plus a scope classifier (`city` or the
rig name — roster `:rig`, or the name's slash prefix; a cold roster
never dead-ends: free entry works, scope-dependent checks degrade).
In `gascity-formula.el`, pure predicates over cached data:
`gascity-sling--binding-targets-p` (any step of the cached recipe
carries a binding-qualified `metadata["gc.run_target"]` — a value
containing `.` and no `/`; verified against bright-lights: build-basic
exposes 24 such steps, e.g. `gc.run-operator`);
`gascity-sling--v2-trap-p` (binding-qualified run targets **and** a
city-scoped target ⇒ the bl-bdj warning, mockup §5a wording — the
trap fires at instantiation, dry run does not exercise it, so the
client warns); `gascity-sling--cross-store-p` (the work bead's store,
from its id prefix against the rig memo `gascity-rigs-cached` /
`gascity-rigs-cached-prefixes` — the same prefix-routing the bd verbs
use — vs the target's store: a rig-scoped agent names its rig, a city
agent the city store ⇒ warning, mockup §5b); plus the §5c
missing-pieces checks (no work for a drain formula, missing required
vars, no target). All are pure and unit-tested with fixture payloads.

**WI-3 — Derived Who default** (REQ-005). A
`gascity-sling--derive-target` over (scope, roster, memory), in the
design's order: (1) the work bead's rig `default_sling_target` /
`default_sling_targets` when resolvable from rig data gascity already
reads (fail-soft skip otherwise — recorded under Open Implementation
Details); (2) per-(city, formula) target memory — a new
`gascity-sling--target-memory` alist recorded on launch; (3) the
implementation-worker convention: the roster's exactly one rig-scoped
`gc.implementation-worker` when unambiguous. The derived target
carries a `derived` tag in the header and is the `T` picker's initial
input; `s` uses it without prompting. Tests pin the precedence order,
the exactly-one ambiguity rule, and memory hits/misses.

**WI-4 — Adaptive layout and the three pickers** (REQ-001, REQ-003,
REQ-004, REQ-011). Rewrite `gascity-sling--children-specs` in
`gascity-action.el` to the mockup layout: first group the city title +
one-sentence header + live footer (WI-6); `What` with `A` (completing
read over the city's open/in-progress/blocked beads plus convoys
through the store, annotated `title · status · store`; `C-u A` goes
straight to freeform; empty RET falls through to `Bead id or task
text:`; point pre-seeds as today) and `f` (the existing union picker,
annotations kept); `Who` with `T` (WI-2 candidates, derived default as
initial input); `How` — the picked formula's typed infixes (WI-5),
titled `How — <formula> vars`, full width, absent without a formula;
the routing-flags group rendered **only** on the plain shape (F-5);
`Actions` `s P r g x q`. An answered stage is its one line with the
answer visible and the binding still live; unanswered shows its pick
hint. The scope plist grows `:work` (bead/convoy id or freeform text,
generalizing `:arg`). `gascity-sling--reserved-keys` becomes
`A f T c a n m t s P r g x q` (`p` freed, `P` added). Tests assert the
children-specs shape per mockup state and the reserved-set sync.

**WI-5 — Typed How vars** (REQ-006). In `gascity-formula.el`, new
infix subclasses beside the existing enum/bool/string ones: a file
option (`read-file-name` relative to the target rig's workdir, pinned
`default-directory`, TRAMP-safe), a directory option
(`read-directory-name`), an agent option (the `T` roster completion),
and a numeric option (digit validation refusing `Var %s must be
numeric (got %s)` before any gc call). A `gascity-sling-formula--var-class`
heuristic picks the class: an overridable `gascity-sling-var-readers`
alist (var name → reader function) first, then naming conventions
(`context_path` / `*_path` → file; `artifact_root` → directory;
`*_target` → agent; `rig_name` → a string auto-derived from the
chosen target's rig, editable; numeric by all-digit declared default
or the `max_*`/`*_iterations` convention), and anything unrecognized
fails soft to the string option. A `gascity-sling--title-slug`
derives the `artifact_root` seed `plans/<slug>/` from the work bead's
**title** (repo practice `plans/dashboard-v3/`: downcase, non-alphanumeric
runs → `-`), falling back to freeform text or the formula name —
never the bare bead id. `gascity-sling-formula--current-values` and
the deterministic key assignment are unchanged. Tests: class
selection, numeric refusal, slug derivation and fallbacks, pinned
default-directory on the file/dir readers, override-alist precedence.

**WI-6 — Live footer** (REQ-007, REQ-010). A pure
`gascity-sling--footer` over (scope, roster, recipe): the one-sentence
launch summary — `✓ Ready — <shape> · target <name> (<scope>) · N of M
vars set` — or `⚠ <reason>`, per mockup §1–§5. The footer renders as
part of every transient setup, so it recomputes as each answer
changes, from cached data only (no gc on the render path). Full
warning detail lives in the `P` buffer; the footer never blocks `s`.
Tests recompute the footer across scope changes and pin the warning
wordings.

**WI-7 — `P` full preview buffer** (REQ-008). A
`gascity-sling-dispatch-full-preview` building its buffer through
`gascity-view-get-buffer-create` (host-qualified, city-pinned):
the header sentence; a **Validation** section (all WI-2 checks with
full text); a **Recipe — <formula> (steps → needs)** section from the
cached recipe (the step/deps data `gascity-sling-formula--render-recipe`
already renders); and a **Routing plan** section filled in when the
`--dry-run` async call answers (the `gascity-sling--show-plan` /
`gascity-action--async-text-view` pattern, rendered into the preview
buffer) — first paint is client-side and never blocks on the dry run.
`s` launches directly from the buffer; `q` quits. `r` keeps the
server-substituted recipe preview. Preview is never a gate: `s` in the
menu works anytime. Tests render the buffer with the store stubbed
and assert the sections, the async fill, and the launch binding.

**WI-8 — Launch and follow offer** (REQ-009). `s` dispatches exactly
as today (`gascity-sling-formula--dispatch` / the plain path via
`gascity-command-act-async`). On a formula-path success, the sling
result's created workflow root bead id (from the `gc sling --json`
payload in the act's `:on-success` — field confirmed in the e2e pass;
see Open Implementation Details) is echoed as `Launched workflow
<id> (<formula> on <work>) — F: run view`, and a momentary follow map
(`set-transient-map`) binds `F` to `gascity-run-show` on that root id;
any other key dismisses; the user stays put. Plain-route launches
keep the plain echo and no offer. Tests stub the result payload and
assert the map, the `F` jump, and the plain path's absence of both.

**WI-9 — State and memory preserved** (REQ-012). `gascity-sling--remembered`
keeps its per-city scope+values contract; the new layout renders from
the scope, so a remembered state reopens the collapsed stages with
their answers; `x` clears work/formula/target/values and forgets; `s`
still forgets after a real launch (S-2). Per-(formula,var) history is
untouched. The per-(city,formula) target memory (WI-3) is recorded on
launch. City pinning (`gascity-sling--city-dir`, ga-4ia4) extends to
every new reader (work picker, agent picker, file/dir completion),
and the entry prefetch plus `g` refresh machinery are unchanged. The
S-2 tests are ported alongside.

**WI-10 — ERT consolidation** (REQ-013). Port the seven
`gascity-sling-test.el` tests to the new layout (`p`→`P` preview
semantics, `A`/`T` pickers, scope `:work`), and update every
layout-coupled sling test in the shared suite `gascity-test.el`: the
var/reserved four (`gascity-test-formula-sling-var-children-shapes`,
`gascity-test-formula-sling-var-children-nil-formula-degrades`,
`gascity-test-sling-var-key-deterministic`,
`gascity-test-sling-var-keys-stable-and-unique`) against the new key
set and typed classes, plus the transient tests the rewrite of
`gascity-sling--children-specs` / `gascity-sling--run` touches:
`gascity-test-sling-reserved-keys-complete`,
`-city-dir-pins-entered-from-city`, `-dispatch-prefix-seeds-city-dir`,
`-dispatch-pick-pins-city-dir`, `-children-specs-read-recipe-pinned`,
`-dispatch-suffixes-run-pinned`, `-unified-wiring`, `-unified-layout`,
`-target-set-and-header`, `-arg-edit-re-setups-in-place`,
`-dispatch-target-fallback`, `-plain-path-unchanged`,
`-preview-dry-run-paths`, and
`gascity-test-formula-sling-dispatch-shapes` /
`gascity-test-formula-sling-preview-fresh-show`. The command-line and
cache tests (`-sling-command-line`, `-rich-command-line`,
`-parse-transient-args`, `-on-command-line`, the
`gascity-test-formula-*` cache/enum/history set,
`gascity-test-store-formula-refresh-async-swaps-caches`,
`gascity-test-remote-sling-plan-view`) exercise the retained plumbing
and are expected to pass unchanged. New tests: shape inference; header sentence; typed-var
heuristics; Who default derivation; the bl-bdj trap warning; the
cross-store warning; the follow offer; footer recompute; reserved-set
sync. Everything stubs the gc boundary (`gascity-test-with-store-stubs`,
`cl-letf` on the reader functions) so the suite stays offline and
fast; the non-blocking guard list in `lisp/test/gascity-store-test.el`
gains any new input-free verb. `scripts/gate.sh` (byte-compile
warnings-as-errors + full ERT) must be green.

**WI-11 — End-to-end verification** (REQ-014). Through
`. scripts/e2e-harness.sh` (timeout-wrapped emacs/emacsclient/tmux,
hard iteration caps): a fresh Emacs inside tmux connected to
`/ssh:localhost:/home/roman/bright-lights`, every gc invocation as
`gc --city /home/roman/bright-lights …`. The four design scenarios:
(1) pancake formula end to end — header sentence, launch, the mayor
session works it, the follow offer jumps to the run view; (2)
build-basic `--on` with typed vars — `context_path` file completion,
`artifact_root` defaulting to `plans/<slug>/`, `rig_name` and
`implementation_target` derived from the target; (3) the bl-bdj trap —
a city-scoped target shows the footer warning before launch, a
rig-scoped target shows ✓; (4) plain dispatch — bead at point, `S`
then `s` with zero prompts, freeform text via the prefix arg. The
dogfood report lands under `docs/qa/` and the screenshots (WI-12) are
captured from this same session.

**WI-12 — Documentation** (REQ-015). A complete Texinfo chapter for
the sling command in `doc/gascity.texi` at the PostgreSQL-documentation
quality bar: the unified flow (What → Who → How → Preview → Launch →
Follow), every shape, the three pickers, the typed readers, the
validation warnings, the `P` preview buffer, the follow offer, and
the key summary (mockup §10). The four-line Sling item in "Dispatch
and lifecycle" becomes a pointer; `docs/DESIGN-write-actions.md` §10's
unified-sling subsection is updated to the redesign (the design
supersedes it). `make -C doc` builds with the existing toolchain
(`doc/Makefile`, `manual.css`); real screenshots of the transient's
states live under `doc/screenshots/` wired like the existing images,
captured from the WI-11 session; momentary states that cannot be
captured faithfully fall back to mockup renderings (requirements Open
Question), noted in the QA report.

### Sequencing

Six waves, each ending with `scripts/gate.sh` green and one commit per
work item (`type(scope): summary (bead-id)`, e.g.
`feat(sling): …`):

1. **WI-1, WI-2** — pure foundations (inference, roster accessor,
   validators), fully testable offline before any UI churn.
2. **WI-3, WI-4** — the adaptive transient lands: new layout, pickers,
   derived default, reserved-key set change.
3. **WI-5** — typed vars, generating the How group against the final
   reserved set.
4. **WI-6, WI-7, WI-8** — footer, preview buffer, follow offer.
5. **WI-9, WI-10** — state/memory adaptation and the full ERT pass
   (port + new) with the gate green.
6. **WI-11, WI-12** — the live verification pass and the
   documentation chapter + screenshots from that session.

Rationale: inference-first keeps the layout rework test-driven; typed
vars come after the layout so generated keys are computed once against
the final reserved set; e2e and docs are last because the screenshots
must come from the verified live session. The order follows the
design's implementation sequence (shape → pickers/Who → vars →
footer/preview → follow → e2e).

### Risks and mitigations

- **Sling result payload** — the created-workflow root bead id needed
  by the follow offer must come out of `gc sling --json`. Confirmed
  in the e2e pass (WI-8/WI-11); fallback: resolve the newest workflow
  root via a store `bd list` read before showing the offer; never a
  guess. See Open Implementation Details.
- **Render-time gc** — the footer/preview must never spawn a
  synchronous gc (D9). Roster/recipe/catalog read through the store
  caches; validation is pure over cached payloads; a cold roster skips
  scope-dependent checks (free entry still works).
- **Reserved-key churn** (`p` freed, `P` added): the deterministic
  var-key algorithm already avoids the reserved set; the sync tests
  in `gascity-test.el` pin it; a var that previously took `p` now gets
  another key — acceptable (keys are per-formula deterministic, not
  user-stable).
- **TRAMP completion latency** on file/dir readers against a remote
  rig workdir: completion can be slow — the readers fail soft to
  typed text, the e2e harness wraps every call in `timeout(1)`, and
  the bright-lights pass exercises it.
- **Ephemeral screenshot states** (follow offer, footer variants):
  capture feasibility is left to the verification pass, with mockup
  renderings as the documented fallback (requirements Open Question).
- **Layout fidelity** to the mockups: acceptance walks each mockup
  state §1–§10 during WI-11; deviations are recorded in the QA report.
- **Test churn from the scope change** (`:arg` → `:work`): the seven
  ported `gascity-sling-test.el` tests **and** the ~18 layout-coupled
  `gascity-test.el` tests (enumerated in WI-10) are updated with the
  layout work (WI-4/WI-10 together) to avoid porting twice.

## Non-Goals

Per the approved design's explicit non-goals and the requirements'
Out Of Scope:

- **Named presets / repeat-last dispatches** — rejected;
  per-(formula,var) history and per-(city,formula) target memory
  already cover reuse.
- **Abort/pause affordance for running workflows** — out of scope
  (surfaced by the ga-kqo0 stop incident; revisit after the redesign
  lands, possibly upstream in gc).
- **A separate quick-sling command** — rejected; plain dispatches
  flow through the same unified transient.
- **Upstream PRs** — the polecat contract allows local commits to
  `main` only.
- **Touching the unrelated stopped worktree `worktrees/ga-tbte`**, or
  committing the pre-existing uncommitted deletions under
  `plans/dashboard-v2/`.
- **gc-side changes** (e.g. teaching gc about the bl-bdj trap) — the
  client warns; gc stays the authority.
- **Blocking validation** — warnings are unmissable but never block
  `s`.
- **Sessions as the Who** — Who is agent-centric; free text entry
  stays available.

## Verification

### Test strategy

All new logic is pure or stubbed at the gc boundary; the suite stays
offline and fast (repo conventions: `cl-letf` on
`gascity-reader-read*` / the action verb, `gascity-test-with-store-stubs`,
fresh store per test in `gascity-test-helpers.el`).

- Ported (WI-10): the seven `gascity-sling-test.el` tests above.
- Updated (WI-10): the var/reserved four
  (`gascity-test-formula-sling-var-children-shapes`,
  `gascity-test-formula-sling-var-children-nil-formula-degrades`,
  `gascity-test-sling-var-key-deterministic`,
  `gascity-test-sling-var-keys-stable-and-unique`) against the new
  reserved set, plus the layout-coupled transient tests enumerated in
  WI-10 (`-unified-wiring`, `-unified-layout`, `-target-set-and-header`,
  `-arg-edit-re-setups-in-place`, `-dispatch-target-fallback`,
  `-plain-path-unchanged`, `-preview-dry-run-paths`,
  `gascity-test-formula-sling-dispatch-shapes`,
  `gascity-test-formula-sling-preview-fresh-show`, the city-pinning and
  children-specs set, `-reserved-keys-complete`).
- New: shape inference (REQ-002), header sentence (REQ-001/002), work
  picker fallbacks (REQ-003), shape flip on formula pick (REQ-004),
  Who default derivation order (REQ-005), typed-var heuristics and the
  numeric guard (REQ-006), footer recompute (REQ-007), preview buffer
  sections and async fill (REQ-008), follow offer (REQ-009), bl-bdj
  trap warning (REQ-010), cross-store warning (REQ-010), layout
  states + reserved sync (REQ-011), remembered-state reopen
  (REQ-012).
- Gate: `scripts/gate.sh` (`eldev compile --warnings-as-errors` + the
  full ERT suite) green — acceptance criterion 11.

### End-to-end verification

The four scenarios of REQ-014 (pancake formula e2e; build-basic `--on`
with typed vars; the bl-bdj trap with city- vs rig-scoped targets;
plain dispatch with point pre-seed and freeform escape), run from a
fresh Emacs inside tmux over TRAMP against
`/ssh:localhost:/home/roman/bright-lights` through
`. scripts/e2e-harness.sh`, every gc call as
`gc --city /home/roman/bright-lights …`. The pass is recorded as a
dogfood report under `docs/qa/`; the same session produces the
screenshots for the manual. Documentation builds with
`make -C doc`; screenshots are wired under `doc/screenshots/` like the
existing images (acceptance criteria 12–13).

### Handoff criteria

- **To the decomposition stage**: each work item above is sized as one
  decomposition unit — it names its files, its new/changed functions,
  its REQ trace, and its tests; nothing here requires another
  planning pass.
- **To plan review**: traceability is the Coverage table below (every
  REQ-001…REQ-015 covered by named work items); feasibility risks are
  listed with mitigations; edge cases (warnings never block, cold
  roster, remote completion, missing dry-run) are carried by the
  requirements' acceptance criteria.
- **Definition of done**: the 13 acceptance criteria of
  `requirements.md` §Acceptance Criteria all hold, `scripts/gate.sh`
  is green, the e2e report and screenshots are committed, and the
  manual chapter builds.

## Open Implementation Details

Recorded here instead of asking (the run is autonomous/headless);
none is blocking — each has a decided default:

- **`gc sling --json` root field for the follow offer** (WI-8): the
  payload field naming the created workflow root is confirmed in the
  e2e pass; if it differs, the fallback (newest workflow root via a
  store `bd list` read, before the offer is shown) applies.
- **Rig `default_sling_target` client-side source** (WI-3): if the
  rig data gascity already reads does not expose the rig's sling
  defaults, derivation rule 1 is skipped fail-soft and rules 2–3
  drive the default; behavior is documented in the manual.
- **Var-key overflow rendering** (REQ-006): if a formula's var set
  cannot avoid all collisions, the mockups' `…` grouped-overflow
  fallback applies — an implementation detail, not a design change.

## Coverage

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
| REQ-015 | covered |

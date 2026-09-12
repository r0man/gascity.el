---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-nck
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
    - path: beads/ga-udw
      hash: bead:ga-udw
      title: "WI-3: Formula sling transient — picker, generated var infixes, recipe preview, wiring"
      ids:
        - REQ-001
        - REQ-004
        - REQ-005
        - REQ-006
        - REQ-007
        - REQ-008
        - REQ-009
        - REQ-012
        - REQ-013
        - REQ-015
        - REQ-016
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Approved implementation plan, Phase 3 (formula sling transient) and decisions D1/D2/D3"
    - path: plans/formula-sling-ui/requirements.md
      hash: sha256:15f20fdbd56f4b1d56c0fcb432b7623abe6026ea0c87ebc15a077528e2a2da31
      title: "Approved requirements (the REQ ids this step covers)"
    - path: lisp/gascity-formula.el
      hash: git:46c3706
      title: "The formula sling transient, picker, generated infixes and recipe preview as committed"
    - path: lisp/gascity-action.el
      hash: git:46c3706
      title: "Sling dispatch rewiring: -f enters the formula flow; gascity-sling--read-vars deleted"
    - path: lisp/test/gascity-test.el
      hash: git:46c3706
      title: "ERT coverage for children generation, key degeneration, pattern reads, value collection, dispatch shapes, fresh preview and wiring"
    - path: lisp/gascity-types.el
      hash: git:a940623
      title: "Formula read command classes with NAME! bang executors (WI-1), the single gc call site the transient reads through"
    - path: lisp/gascity-domain.el
      hash: git:a940623
      title: "Typed formula payload classes (WI-1) the transient decodes recipes into"
  coverage:
    - id: REQ-001
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
    - id: REQ-012
      status: covered
    - id: REQ-013
      status: covered
    - id: REQ-015
      status: covered
    - id: REQ-016
      status: covered
---

# Implementation Summary: WI-3 formula sling transient (gascity-formula.el + gascity-action.el)

## Summary

Implemented work item WI-3 of the formula-sling-ui plan (source anchor
bead ga-udw) in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-udw`, committed as
`46c3706cc78a5c316abcb90f7126e8a790662bbf` ("feat(formula):
formula-aware sling transient with generated var infixes") on the
worktree's detached HEAD.

The step builds the formula-aware sling transient
(`gascity-sling-formula-dispatch`) on the WI-2 metadata module and wires
it into `gascity-sling-dispatch`: a catalog picker, one generated infix
per declared `vars[]` entry (enum / boolean / string), a dispatch suffix
that validates client-side before any gc call, and a recipe preview that
re-runs `gc formula show` with the currently-set values so gc
substitutes server-side. gascity never reimplements gc logic — every
read and write stays on the single gc call site's bang executors.

A prior attempt at this bead was interrupted mid-edit and left
`lisp/gascity-formula.el` truncated (unbalanced parens, one missing
forward declaration); this attempt repaired the file, completed the
implementation and added the pinned ERT coverage.

## Intended Behavior

- **Scope and entry (REQ-013 seeding half).**
  `gascity-sling-formula-dispatch` keeps a scope plist
  `(formula target arg)` set at entry: `gascity-sling-formula` (reached
  directly and as `gascity-sling-dispatch`'s `-f` binding) seeds `arg`
  from the bead-id string or typed `gascity-convoy` at point via
  `gascity-object-at-point`, and reads the sling target once with
  `gascity-action--read-session`. A header info line shows the current
  formula, arg and target.
- **Pure children generation (REQ-004..009, REQ-016).** The Variables
  section is a pure function of the scoped formula's cached recipe:
  one infix per declared var, class per shape — an enum var (explicit
  `vars[].enum` or the WI-2 metadata mapping) becomes a
  fixed-`choices` option read with `completing-read` `require-match`,
  so illegal values are unrepresentable (REQ-005); a var defaulted
  `"true"`/`"false"` becomes a boolean toggle infix serializing to
  `name=true`/`name=false` (REQ-006); everything else is a string
  option whose prompt is the var's `description`, whose initial value
  is its `default`, and whose infix description carries description,
  default and a "(required)" mark (REQ-007/008). Missing
  description/default degrade to a generic prompt and empty initial
  (REQ-016). `pattern` vars validate in the infix reader with
  `string-match`, failing fast with a message naming the var and the
  pattern; an unparseable pattern degrades to no validation (REQ-009).
  String/enum reads use the per-(formula, var) history variables from
  WI-2 (REQ-010/011). A formula with no vars renders no Variables
  section (REQ-004). Generated keys avoid the static suffix keys and
  degenerate from name letters to digits. Picking a different formula
  re-runs `transient-setup`, rebuilding the section while carrying
  already-set values.
- **Picker (REQ-001).** `gascity-sling-formula-pick` reads a formula
  name from the cached catalog with `completing-read` and an
  `:annotation-function` supplying each entry's `description`, then
  replaces the scope's formula and re-runs `transient-setup`.
- **Recipe preview (REQ-012 as revised by F-1).**
  `gascity-sling-formula-preview` re-runs `gc formula show <name>
  --json` with the currently-set values via
  `gascity-command-formula-show!` with repeated `--var k=v` flags, and
  renders gc's substituted compiled recipe — steps (substituted titles,
  ids, `gc.kind` step metadata) and dependency edges — into a
  host-qualified read-only `view-mode` buffer created through
  `gascity-view-get-buffer-create` (REQ-014), so a local and a remote
  preview coexist. No client-side `{{var}}` substitution anywhere. A gc
  failure surfaces as a clean `user-error` carrying gc's stderr. The
  existing `--dry-run` routing-plan preview suffix in
  `gascity-sling-dispatch` is untouched.
- **Dispatch (REQ-008, REQ-013).** `gascity-sling-formula-run`
  validates first via `gascity-formula--validate-values`: a missing
  required var produces a `user-error` naming the missing vars with no
  gc invocation. Values set for a formula the user has since re-picked
  never leak (the collector keeps only the scoped formula's vars; blank
  values count as unset). The shape follows WI-2's
  `gascity-formula--needs-convoy`: targetless → `gascity-command-sling
  :formula t :arg <formula>`; targeted → `:arg <bead-id> :on <formula>`;
  both carry the collected `:var` list. A convoy-requiring formula with
  no bead/convoy at point refuses with a `user-error` naming the
  condition instead of dispatching a sling gc would reject. On success
  the sling acts through `gascity-command-act` and refreshes the
  originating view.
- **Wiring (REQ-015).** `gascity-sling-dispatch` keeps its bindings and
  non-formula flag infixes; its `-f` toggle now leaves for
  `gascity-sling-formula`, and the old minibuffer var reader
  `gascity-sling--read-vars` is deleted — var values flow through the
  generated infixes into the same `--var k=v` accumulation. View
  bindings in `gascity.el`, `gascity-rig.el`, `gascity-session.el` and
  `gascity-status.el` are unchanged.

## Changed Files

All changes are committed in the item worktree (commit `46c3706`,
detached HEAD of `/home/roman/workspace/gascity.el/worktrees/ga-udw`):

| File | Change |
| --- | --- |
| `lisp/gascity-formula.el` | The formula sling transient: scope helpers, generated infix classes (enum/bool/string), pure children generation, catalog picker, dispatch suffix with client-side validation, fresh server-side recipe preview, the prefix and entry function. |
| `lisp/gascity-action.el` | `-f` binding of `gascity-sling-dispatch` now enters `gascity-sling-formula`; `gascity-sling--read-vars` and the `--formula` prompt path deleted; commentary updated. |
| `lisp/test/gascity-test.el` | New ERT section for the transient (see Verification). |

Coverage matrix:

| ID | Status |
| --- | --- |
| REQ-001 | covered |
| REQ-004 | covered |
| REQ-005 | covered |
| REQ-006 | covered |
| REQ-007 | covered |
| REQ-008 | covered |
| REQ-009 | covered |
| REQ-012 | covered |
| REQ-013 | covered |
| REQ-015 | covered |
| REQ-016 | covered |

## Verification

1. First verification command — the byte-compile gate over the whole
   package, never a subset (a missing forward `declare-function` only
   shows under full-package compile):
   `eldev compile --warnings-as-errors` (run from
   `/home/roman/workspace/gascity.el/worktrees/ga-udw`) — **pass**,
   zero warnings. It caught and drove out two real defects of the
   interrupted prior attempt: the truncated
   `lisp/gascity-formula.el` (end of file during parsing) and one
   missing `declare-function` (`gascity-view-get-buffer-create`).
2. ERT (mocked, house convention — `cl-letf` stubs on the bang
   executors and action verbs, no live city needed):
   `eldev test gascity-test-formula` — **pass**, 15/15, including the
   seven new WI-3 tests:
   - `gascity-test-formula-sling-var-children-shapes` — the pure
     children generation matches `vars[]`: one infix per var with
     unique keys avoiding the static suffix keys, enum vars restricted
     to declared choices with the right `--var name=` argument,
     boolean toggles for true/false defaults, and the string infix
     carrying the required mark, description and default; a varless
     formula renders no Variables section;
   - `gascity-test-formula-sling-var-key-degenerates` — name-letter
     keys skip used characters and degenerate to digits;
   - `gascity-test-formula-sling-check-pattern` — a mismatch is a
     `user-error` naming var and pattern; a matching value and a
     non-compiling pattern pass silently;
   - `gascity-test-formula-sling-current-values` — parses the
     transient's `--var name=value` args keeping only the scoped
     formula's vars, dropping blanks and unknown names;
   - `gascity-test-formula-sling-dispatch-shapes` — the targetless
     command line is `gc sling t do-work --formula --var …`, the
     targeted one `gc sling t gce-abc --on do-work --var …`; a missing
     required var is a `user-error` naming the var with no gc call; a
     convoy-requiring formula with no arg refuses; acting refreshes;
   - `gascity-test-formula-sling-preview-fresh-show` — the preview
     re-runs `gascity-command-formula-show!` with repeated `--var
     k=v` flags, renders gc's substituted step title and dependency
     edge into the host-qualified `*gc-formula: …*` buffer, and a gc
     failure surfaces as a `user-error` carrying gc's stderr;
   - `gascity-test-formula-sling-wiring` — `gascity-sling-dispatch`'s
     `-f` binding now runs `gascity-sling-formula`, and
     `gascity-sling--read-vars` is gone.
3. Final proof command — the standard quality gate: `scripts/gate.sh`
   equivalent halves run separately from the worktree —
   `eldev compile --warnings-as-errors` (**pass**) and `eldev test`
   (**pass**: 266 tests, 266 results as expected, 0 unexpected).

## Remaining Risks

- The end-to-end sling dispatch against the live TRAMP city
  (`bright-lights`) is the Phase 4 tmux-Emacs acceptance pass, not this
  step; the transient's interactive setup path (real
  `transient-setup`/re-pick cycles) is exercised only via its pure
  generation functions and wiring checks until then.
- The boolean toggle's cycle order (true → false → true from the
  declared default) is a UI convention, not gc-declared behavior; if gc
  ever documents a different canonical cycle it is a one-method change.
- Transient 0.13's normalized suffix objects (plain
  `(transient-suffix :key … :command …)` lists, not eieio instances)
  are pinned by the wiring test only for this `-f` entry; deeper
  introspection of generated infix objects at runtime is untested by
  design (the pure spec layer is the contract).
- Cache freshness stays session-lifetime by design (D3, WI-2): the
  picker and constraints read the cached recipe; only the preview reads
  fresh. A formula edited on disk mid-session is invisible to the
  infixes until `gascity-formula-invalidate`.

---
schema: gc.build.plan-review.v1
workflow:
  id: ga-c0e
  formula: build-from-plan-base
methodology:
  pack: gascity
  name: review-synthesizer
producer:
  formula: build-from-plan-base
  stage: plan-review
  attempt: 1
status: complete
interaction_mode: interactive
trace:
  upstream:
    - path: plans/formula-sling-ui/build/implementation-plan.md
      hash: sha256:91882d794fd32ce2ba2bd555017f39ae97d360468a6fb3a7776b1ae93b13681a
      title: "Draft implementation plan under review"
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
        - REQ-016
        - REQ-017
        - REQ-018
        - AC-1
        - AC-2
        - AC-3
        - AC-4
        - AC-5
        - AC-6
        - AC-7
        - AC-8
---

# Plan Review: formula-aware sling UI (implementation-plan.md)

**Verdict: `changes_required`** — one binding-requirement violation (REQ-012),
concrete fix specified below. Everything else in the plan verified sound
against the codebase and the live gc.

## What was verified (not taken on faith)

Every load-bearing factual claim in the plan was checked against the repo and
the live local city (`/home/roman/emacs-city`, 2026-09-10):

- **Code claims all match.** `gascity-command-sling`
  (`lisp/gascity-types.el:286`) has no `on` slot and carries `--formula`
  boolean, repeated `--var` (`:option-type :list`), `--merge`/`--title`
  string options — exactly as the plan states. `gascity-sling--read-vars`,
  `gascity-sling--parse-transient-args` (which would need only a
  `"--on=..."` clause), `gascity-sling--show-plan`,
  `gascity-action--read-session`, `gascity-reader-read`,
  `gascity-view-get-buffer-create`, and the load order in `lisp/gascity.el`
  (slot for a new module between `gascity-domain` and
  `gascity-command-status`) are all as the plan describes.
- **D1 payload shapes verified live.** `gc formula catalog --json` returns
  `{schema_version, ok, formulas: [{name, description}], summary: {count}}`
  (13 formulas, name+description only). `gc formula show build-from-convoy
  --json` returns the recorded shape including `vars[]` entries with
  `name`/`description`/`default`/optional `required`, `steps[]` with
  per-step `metadata`, and `deps[]`.
- **D1's "no shipped formula declares `enum`/`pattern`" claim verified.**
  Enum-like sets do live in `metadata.gc.methodology.*`
  (`allowed_drain_policies`, `interaction_modes`, `review_modes` on
  `build-from-convoy`), so the fallback mapping design is grounded.
- **D2 heuristic verified against gc's own rule text.** `gc sling --help`
  states verbatim: "A v2 formula that references `{{convoy_id}}` or
  contains a drain step requires a target convoy: route it with
  `gc sling <target> <bead> --on <formula>`". The compiled
  `build-from-convoy` recipe contains a step (`…implement`) with
  `metadata.gc.kind == "drain"`, so both detection prongs are real signals.
- **D3 savehist mechanism claim verified.** savehist.el's
  `savehist-minibuffer-hook` tracks whatever variable was bound as
  `minibuffer-history-variable` during the read, so dynamically named
  `gascity-formula-history-<formula>-<var>` symbols used in minibuffer
  prompts are persisted without extra plumbing. The claim is correct.
- **House conventions hold.** All gc reads through `gascity-reader` bang
  executors; caches keyed by `(concat (file-remote-p dir) dir)`; no
  redisplay-time gc; view bindings untouched (REQ-015); test plan uses the
  `cl-letf` house convention; the tmux-Emacs TRAMP acceptance pass per
  AGENTS.md is an explicit phase-4 gate.

## Findings

### F-1 (changes_required) — Preview must re-run `gc formula show` with `--var`, not approximate client-side (REQ-012)

REQ-012 is a **MUST** row: "A preview suffix MUST re-run
`gc formula show <name> --json` **with the currently-set `--var` values**
and display the compiled recipe (steps, dependency edges, substituted
titles)". The plan's preview instead renders the **cached** recipe and does
"client-side approximation of gc's server-side substitution" of `{{var}}`
occurrences. Verified live: `gc formula show` supports exactly this —
`--var stringArray` ("Use --var to substitute variables and preview the
resolved output").

Why this matters beyond the letter of the requirement:

1. The plan silently overrides a binding MUST. The requirements allow
   overriding *SHOULD* rows "in writing"; MUST rows are the contract. The
   coverage table still marks REQ-012 `covered`, which the text contradicts.
2. The approximation is objectively worse: it would not apply `default`s
   for unset vars (gc's preview does), and it reimplements a slice of gc's
   substitution logic — against the package's core rule that gascity
   renders gc state and never reimplements gc logic.
3. The fix costs nothing the plan isn't already paying: a preview is a
   user-initiated suffix (TS-3/TS-4 concerns don't apply — nothing runs at
   redisplay time), and `formula show` goes through the same reader/city
   directory as every other read.

**Required change.** Phase 3's preview suffix becomes: collect the current
infix values, run `gascity-command-formula-show!` with repeated `--var
k=v` flags (a `:var` list slot on the read class, mirroring
`gascity-command-sling`), and render gc's substituted payload. The
recipe *cache* (D3) stays for the picker/constraints/shape-detection
path; the preview reads fresh. Update the Verification section
(ERT: preview command construction includes repeated `--var`; e2e:
preview shows substituted titles) and drop the "client-side
approximation" language. D1's recorded recipe shape is unaffected.

### F-2 (note, no change required) — Trace hash recorded verbatim

The upstream hash for `plans/formula-sling-ui/build/implementation-plan.md`
was re-computed during review (`sha256:91882d79…`) and recorded in this
artifact's trace. No action needed.

## Disposition

| Requirement | Status | Note |
| --- | --- | --- |
| REQ-001 | ok | Picker + `:annotation-function` design sound |
| REQ-002 | ok | Read-or-error catalog access with explicit messaging |
| REQ-003 | ok | Bang executor + per-city cache (D3) verified against reader/context code |
| REQ-004 | ok | Scope + `transient-setup` rebuild; var-less formulas |
| REQ-005 | ok | Contractual `vars[].enum` support + metadata fallback (D1) |
| REQ-006 | ok | Boolean toggle infix for `true`/`false` defaults |
| REQ-007 | ok | Description-as-prompt, default-as-initial, self-documenting infix |
| REQ-008 | ok | Pre-dispatch validation, names vars, no gc call |
| REQ-009 | ok | Entry-time `string-match` validation, unparseable-pattern degradation |
| REQ-010 | ok | Per-`(formula,var)` history symbols |
| REQ-011 | ok | savehist mechanism claim verified in savehist.el source |
| REQ-012 | **changes_required** | F-1: preview must re-run `formula show --var`; no client-side substitution |
| REQ-013 | ok | D2 heuristic matches gc's documented rule; `--on` slot added |
| REQ-014 | ok | City-keyed caches, host-qualified preview buffers, no new TRAMP traffic |
| REQ-015 | ok | Bindings unchanged; §5.2/§10 conventions hold |
| REQ-016 | ok | Absent-field degradation specified per infix kind and in tests |
| REQ-017 | ok | ERT plan follows house `cl-letf` convention; gate in phase 4 |
| REQ-018 | ok | tmux-Emacs bright-lights pass explicit in phase 4 + acceptance gate |

**Answer to the reviewer's open point on `interaction_mode`:** this review
was performed with the findings recorded for the plan author to act on
(F-1 is a concrete, mechanical change), which is the interactive contract:
a blocking finding with a specified fix rather than a silent approval or an
unexplained rejection. No questions remain open.

## Next step

Revise the plan per F-1 (small, localized: the preview suffix, one read-class
`--var` slot, and the corresponding Verification bullets), then proceed to
decomposition. F-2 requires no action.

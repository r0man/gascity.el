# Formula sling UI — tmux-Emacs TRAMP e2e acceptance pass (WI-4)

- Date: 2026-09-12
- Item: WI-4 of the formula-sling-ui decomposition (bead ga-4ef; worktree
  `worktrees/ga-4ef`, HEAD at the sling-UI feature commits plus this item's fixes)
- Environment: fresh `emacs -nw -Q` inside tmux (`gce-e2e`), package loaded from
  the item worktree with the sibling beads.el checkout and transient 0.13.8 on
  the load path; `savehist-mode` on (as a real user config would run).
- City: remote test city `/sshx:localhost:/home/roman/bright-lights`
  (see "TRAMP method" below for why the connection is `sshx`, not `ssh`), plus
  the local city `/home/roman/emacs-city` for the cache-isolation check.

## What was exercised and observed

All steps below ran in the live terminal Emacs over TRAMP; quotes are captured
screen text.

1. **Remote dashboard.** `M-x cd /sshx:localhost:/home/roman/bright-lights`,
   `M-x gascity-status` → `*gascity-status@/sshx:localhost:*` rendering
   "Gas City: bright-lights /home/roman/bright-lights", rigs (bright-lights,
   hello-world), pools (bd.dog scaled 0..2), store health (127.8 MB · 5649 live
   rows). All vui sections populated over the async reads.

2. **Sling dispatch → formula flow.** `S` in the dashboard opened
   `gascity-sling-dispatch` (routing flags + Sling column); `-f` left for
   `gascity-sling-formula`; target read offered the remote session
   completion (`mayor`, sole completion via TAB). The formula transient then
   rendered the scope header:

   ```
   Formula
      Formula: (none — pick one) · Arg: (none — point at a bead or convoy) · Target: mayor
    -f Pick formula…
    s Sling…
    r Preview recipe…
    q Quit
   ```

3. **Catalog picker with annotations.** `-f` in the formula transient read with
   `completing-read` over the *remote* catalog; TAB with an empty input listed
   all 13 formulas, each annotated with its description, e.g.
   `review  Write an implementation review report for a diff, branch, or
   artifact set.` (captured from `*Completions*`). Picks use
   `require-match`; history `gascity-sling-formula-picker-history`.

4. **Generated variable infixes (REQ-004..009).** Picking `review` rebuilt the
   transient with one infix per declared var, shaped per the declared payload:

   ```
   Formula                                              Variables
      Formula: review · Arg: (none — …) · Target: mayor   c context_path — Optional context bundle path. (--var context_path=)
    -f Pick formula…                                      i interaction_mode — Review interaction posture: … [default: autonomous] (--var interaction_mode=autonomous)
    s Sling…                                              e report_path (required) — Path to write the review report. (--var report_path)
    r Preview recipe…                                     v review_mode — Review authority: report, agent, or interactive. [default: report] (--var review_mode=report)
    q Quit                                                u subject_path (required) — Diff, summary, … (--var subject_path)
   ```

   Picking `implement` regenerated the Variables section for its six vars:
   enum `drain_policy` [default: separate], bool toggles `push`/`open_pr`
   [default: false], strings `context_path`/`implementation_target`/`summary_path`.
   Boolean toggles cycled on keypress (`open_pr=false` → `open_pr=true`,
   observed in both transients). Required vars carry the `(required)` mark.

5. **Recipe preview, server-side substitution (REQ-012/F-1).** `r` re-ran
   `gc formula show review --var subject_path=… --var report_path=…` over TRAMP
   and rendered the substituted launch inputs in the host-qualified read-only
   buffer `*gc-formula: review@/sshx:localhost:*`:

   ```
   Launch inputs:
   - subject_path: /home/roman/workspace/gascity.el/plans/formula-sling-ui/build/implementation-summary-ga-udw.md
   - report_path: /home/roman/bright-lights/plans/formula-sling-ui/build/review-report-ga-udw.md
   - interaction_mode: autonomous
   - review_mode: report
   ```

   No client-side `{{var}}` text remains. The `implement` preview correctly
   kept `input_convoy: {{convoy_id}}` — a reserved runtime var substituted at
   routing time, not a `--var`. Preview and transient stay side by side; the
   transient menu stays open (preview is `:transient t`).

6. **D2 refusal, client-side, no gc call.** From the status dashboard (no bead
   at point) with `implement` picked, `s` refused before any gc invocation:

   `Formula implement requires a target convoy — point at a bead or convoy and try again`

7. **Targeted `--on` shape from a convoy at point.** In the remote convoy list
   (`*gascity-convoys@/sshx:localhost:*`, point on `bl-35p`), `M-x
   gascity-sling-formula` pre-seeded the scope — header showed
   `Arg: bl-35p · Target: mayor`. Picking `implement`, toggling `open_pr` and
   dispatching sent the `--var` + `--on` combination to gc
   (`gc sling mayor bl-35p --on implement --var open_pr=true …` — gc's error
   message names the attach: "instantiating formula \"implement\" on
   bl-35p"). The dispatch argv shape is verified; the outcome is gc-side, see
   "Findings — F3".

8. **Live non-formula sling over TRAMP (REQ-013/015).** `S` → `s` from the
   dashboard with task text routed for real:
   `gc sling mayor "e2e WI-4: verify live sling over TRAMP creates and routes a
   task bead"` succeeded over TRAMP. Confirmed in the remote store:
   `bl-c3x` "e2e WI-4: …" `open`, `gc.routed_to=mayor`, plus auto-convoy
   `bl-ohb` "sling-bl-c3x". The originating view refreshed in place.

9. **History (REQ-010/011).** `M-p` in the `subject_path` string prompt
   recalled the previously entered value in-session
   (`gascity-formula-history-review-subject_path`). **Across an Emacs
   restart** (kill Emacs, relaunch with the same `savehist-mode 1` config,
   reopen the same transient), `M-p` recalled
   `/home/roman/workspace/gascity.el/plans/formula-sling-ui/build/implementation-summary-ga-udw.md`
   — savehist persisted the per-(formula, var) history exactly as designed.

10. **Local/remote cache separation (REQ-003/014).** The local city
    `/home/roman/emacs-city` was opened in the same Emacs (`M-x cd` +
    `M-x gascity-status`): a second dashboard rendered the local city
    ("Gas City: emacs-city", rigs beads.el/gascity.el, health ok) in
    parallel with the remote one. The formula catalog cache is keyed by the
    remote-qualified directory — live eval of `gascity-formula-catalog-cache`
    showed the remote key `/sshx:localhost:…/bright-lights`; both cities'
    pickers read their own `gc` (the remote picker listed the bright-lights
    catalog). Preview buffers are host-qualified
    (`*gc-formula: review@/sshx:localhost:*`), so a local and a remote
    preview cannot collide. Cache keys are the directory identity; the
    two-key isolation itself is pinned by ERT
    (`gascity-test-formula-cache-*`).

## Findings

- **F1 (fixed in this item):** opening the formula transient before picking a
  formula crashed — `gascity-sling-formula--var-infixes` passed the nil recipe
  to `gascity-formula-vars` ("No applicable method: gascity-formula-vars,
  nil"). Fixed with a nil guard (REQ-016 degradation) + regression test
  `gascity-test-formula-sling-var-children-nil-formula-degrades`.
- **F2 (fixed in this item):** `gascity-sling-formula--static-children` built
  the "Formula" column with `(apply #'vector …)`; `apply` spreads its *last*
  argument, which spliced the quoted `("q" "Quit" transient-quit-one)` suffix
  into three separate children, and the info line was double-nested
  (`((:info …))`), parsing as an argument spec with key `:info` — transient
  setup crashed in every version ("sequencep, :info", then "Not a transient
  prefix command or group definition: transient-quit-one"). Fixed by
  constructing the vector directly. Only ERT-mocked helpers had covered this
  code before; nothing had exercised `transient-setup` — exactly the gap the
  acceptance pass exists for.
- **F3 (environment/gc-side, follow-up):** the *real formula dispatch* (both
  shapes) is blocked in the bright-lights test city by gc itself:
  `gc sling mayor review --formula --var …` fails with
  `instantiating formula "review": step review.validate-context: unknown
  formulas v2 target "gc.run-operator"`. Reproduced with plain gc over ssh
  (no Emacs involved), for every catalog formula, from the city root and the
  hello-world rig, after `gc reload` and a full `gc restart`; `gc doctor`
  passes (89 ✓) and the agent/pack import lists are identical to the local
  city emacs-city, where the same formulas instantiate fine. The porcelain is
  behaving correctly — it dispatched the right argv and surfaced gc's error as
  a clean `user-error` — but the acceptance requirement "dispatch the real
  sling and confirm the workflow root appears in the remote store" could only
  be completed through the non-formula sling (item 8). Recommended follow-up:
  investigate why bright-lights cannot resolve pack-role v2 run targets
  (e.g. re-add/reimport the gascity roles pack, or compare the controller's
  projected agent state with emacs-city).
- **F4 (environment, worked around):** TRAMP's plain `ssh` method hangs on
  this host (reproduces in `emacs -Q --batch` with no gascity loaded: a bare
  `file-exists-p` on `/ssh:localhost:…` never returns; concurrent Emacsen
  contend on the default TRAMP ControlPath). The pass therefore ran over the
  `sshx` method (`/sshx:localhost:/home/roman/bright-lights`) with a private
  ControlPath; every view behaves identically. Follow-up worth a doctor
  check: TRAMP `ssh` hang on this host.
- **F5 (defect, follow-up):** with the status dashboard's auto-refresh timer
  active (default on, 5 s), the first synchronous read inside a transient
  (`-f`'s session-list read) entered a busy-spin (~60–90% CPU, zero-timeout
  poll loop, C-g recoverable) instead of completing. Toggling auto-refresh
  off (`G`) made every subsequent sync read complete promptly; the pass ran
  with auto-refresh off. Hypothesis: the timer's connection-lock guard
  (`gascity-remote-connection-locked-p`) does not cover the window while a
  sync `process-file` roundtrip is in flight on the shared channel, so the
  tick interleaves with it; needs a dedicated investigation (repro: remote
  dashboard, auto-refresh on, `S` `-f` right after the dashboard's async
  loads settle).

## Verification

- `scripts/gate.sh` (eldev compile `--warnings-as-errors` over the whole
  package + `eldev test`) — **PASS**: 267/267 tests, compile clean, first
  verification command of this item; run before and after the fixes.
- Live tmux-Emacs TRAMP pass per the protocol above; final proof command and
  observed result for the live store effect:

  ```console
  $ ssh localhost "cd /home/roman/bright-lights && gc bd list --json --limit 5"
  …
  bl-c3x open e2e WI-4: verify live sling over TRAMP creates and routes a task bead  gc.routed_to=mayor
  bl-ohb open sling-bl-c3x
  ```

  (slung from the Emacs e2e session over `/sshx:localhost:…`; the routed task
  bead and its auto-convoy appeared in the remote store).

## Follow-ups

- F3: make bright-lights able to instantiate v2 pack formulas (blocked the
  formula-dispatch acceptance half).
- F4: investigate the TRAMP `ssh`-method hang on this host.
- F5: guard the auto-refresh tick against in-flight *synchronous* TRAMP reads
  (the busy-spin repro above).

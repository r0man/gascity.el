# Unified sling transient v2 — tmux-Emacs TRAMP e2e acceptance pass

- Date: 2026-09-15
- Item: WI-1 of the sling-transient-v2 decomposition (bead ga-uzva;
  worktree `worktrees/ga-uzva`, HEAD at `feat(sling): unify formula sling
  into one transient prefix`)
- Environment: fresh `emacs -nw -Q` inside tmux (`gce-e2e`), package loaded
  from the item worktree with the sibling beads.el checkout and transient
  0.13.8 on the load path; eldoc disabled (it only ever tangled with the
  minibuffer relay).  Driven with tmux keystrokes plus `emacsclient --eval`
  probes against a private `server-name` socket.
- City: remote test city `/sshx:localhost:/home/roman/bright-lights`
  (the `sshx` method with its own TRAMP connection, per the known
  plain-`ssh` ControlPath contention on this host — prior e2e F4).

## What was exercised and observed

1. **Remote dashboard.** `cd` to `/sshx:localhost:/home/roman/bright-lights`
   and `gascity-status` → `*gascity-status@/sshx:localhost:/home/roman/
   bright-lights/*` rendering "Gas City: bright-lights", controller
   supervisor (PID 14600), pools (bd.dog 0..2), store health
   (108–153 MB).  All vui sections populated over async TRAMP reads.

2. **One unified menu, no up-front target (AC-1, REQ-A/B).** `S` on the
   dashboard opened `gascity-sling-dispatch` — a single transient with
   stacked full-width sections and no target prompt:

   ```
   Sling — bright-lights
      Arg: (none — point at a bead or convoy) · Formula: (none — -f to pick) · Target: (none)
   Formula
    -f Pick formula…
    g Refresh catalog
   Destination
    -T Target session…
   Routing flags
    -c Skip auto-convoy (--no-convoy) … -t Wisp root title (--title)
   Actions
    s Sling…  p Preview (dry-run)…  r Preview recipe…  q Quit
   ```

   The old second prefix (`gascity-sling-formula-dispatch`) and the
   up-front `Sling to target:` prompt are gone.

3. **`-f` picks in place (AC-1).** Pressing `-f` read the formula once
   (`completing-read` with `require-match` over the *remote* catalog, all
   13 formulas annotated with their descriptions), then re-rendered THE
   SAME transient — header now `Formula: review` — with the generated
   section appended, still one menu, one `-f` press:

   ```
   Variables — review
    on context_path — Optional context bundle path. (--var context_path=)
    i  interaction_mode — Review interaction posture: … [default: autonomous] (--var interaction_mode=autonomous)
    ep report_path (required) — Path to write the review report. (--var report_path)
    ev review_mode — Review authority: … [default: report] (--var review_mode=report)
    ub subject_path (required) — Diff, summary, branch note, or artifact path to review. (--var subject_path)
   ```

4. **Full-width sections (AC-2).** The Variables section renders below
   Formula/Destination/Routing/Actions, full width; long descriptions
   (`subject_path`'s one-liner) fit on one line — the old
   side-by-side-columns cramping is gone.

5. **Deterministic collision-free keys (AC-4).** `review`'s live var keys
   were `on`, `i`, `ep`, `ev`, `ub` — none collides with a static binding
   (`s p r q f g T c a n m t`), and the two-letter combos deliberately
   avoid the bound first letters (`report_path`/`review_mode` do NOT sit
   under the bound `r`; `context_path` does not sit under `c`).  Same
   keys on every rebuild (pure assignment).

6. **Var shaping and value carry-over.** `interaction_mode` is an enum
   (methodology mapping) — a `completing-read` over its declared values;
   setting it to `headless` and then re-picking/re-setupping the menu
   kept the value (`--var interaction_mode=headless`).

7. **`-T` target set and visible (AC-3).** `-T` offered session
   completion over the remote sessions; picking `mayor` re-rendered the
   menu with `Target: mayor` in the header.  Never prompted up front.

8. **Client-side validation refusal.** With `review` picked and the
   required vars unset, `s` refused before any gc invocation:
   `Missing required formula vars: report_path, subject_path`.

9. **Dry-run preview over TRAMP.** With required vars set (`ub`
   → `/tmp/e2e-subj.md`, `ep` → `/tmp/e2e-report.md`) and target `mayor`,
   `p` ran the real `gc sling mayor review --formula --var … --dry-run`
   over TRAMP and rendered gc's routing plan in the host-qualified
   `*gc-sling: dry-run@/sshx:localhost:…*`:

   ```
   Dry run: gc sling mayor review --formula
   Target:
     Session config: mayor (min=0 max=unlimited)
     Sling query: bd update {} --set-metadata gc.routed_to=mayor …
   ```

   (Notably gc accepted the formula sling for the plan — the bright-lights
   gc-side "unknown formulas v2 target" blocker from the prior e2e's F3
   did not reproduce on the dry-run path.)

10. **Recipe preview, server-side substitution.** `r` re-ran
    `gc formula show review --var interaction_mode=headless` over TRAMP
    and rendered the substituted recipe in the host-qualified read-only
    buffer `*gc-formula: review@/sshx:localhost:…*`:
    `interaction_mode: headless` substituted by gc, unset vars left as
    `{{subject_path}}` / `{{report_path}}` — never client-side
    substitution.  The menu stayed open (`:transient t`).

11. **Plain sling unchanged, live (AC-7/REQ-G).** A fresh transient with
    no formula picked: `s` prompted bead/text (shipped order) then
    target; typing task text and `mayor` routed for real — confirmed in
    the remote store: `bl-5ja` "e2e sling-v2: verify unified plain sling
    over TRAMP", `open`, `gc.routed_to=mayor`.

## Findings

- **F1 (fixed in this item):** the TRAMP `sshx` pty prepends the ssh
  client's xauth warning ("Warning: No xauth data; …") to gc's stdout,
  which made `gascity-reader-parse-json` fail on the first sync catalog
  read with a raw `gascity-json-parse-error`.  Fixed in
  `gascity-reader.el`: the parser now skips leading non-JSON transport
  chatter and parses from the first `{`/`[` (regression test
  `gascity-test-parse-json-skips-transport-chatter`).  This is exactly
  the gap the acceptance pass exists for — nothing exercised the first
  sync read over this connection before.
- **F2 (fixed in this item):** transient binds suffix keys with `kbd`,
  so a two-letter var key whose first character is itself a bound key
  (e.g. `re` under the statically bound `r`) is an unrepresentable
  prefix chain — the first live `-f` pick crashed transient setup
  ("Key sequence r e starts with non-prefix key r" /
  `wrong-type-argument command`).  Fixed in
  `gascity-sling-formula--var-key`: combos and positional keys must
  start with a *free* first character, and single-character candidates
  must not be the prefix of an assigned key (regression tests in
  `gascity-test-sling-var-key-deterministic`).  UX note: review's keys
  `on`/`ep`/`ev`/`ub` are two-key chords (press `e`, then `p`) —
  workable, and a faithful consequence of the approved REQ-D fallback
  design; single-char keys (`i`) remain the common case.
- **F3 (environment, worked around; pre-existing):** the F5-class
  busy-spin from the prior e2e recurred — a sync read inside the
  transient while the status dashboard's auto-refresh timer runs
  interleaves with the shared TRAMP channel and spins (~85% CPU until
  `C-g`).  This pass disabled the auto-refresh before the transient
  work; the "no sync-read/refresh interleave" guard remains a
  recommended follow-up (unchanged from the prior report).
- **F4 (environment):** TRAMP's plain `ssh` method still hangs on this
  host under concurrent Emacsen (prior e2e F4); the pass ran over
  `sshx` with its own connection.  Unchanged follow-up.

## Verdict

AC-1..AC-7 verified against the remote bright-lights city (AC-6 e2e
protocol per AGENTS.md).  The unified transient is the single sling
surface, over TRAMP and locally, with the plain path unchanged.

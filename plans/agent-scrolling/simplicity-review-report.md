# Simplicity and maintainability review — build-basic ga-jwtp (agent-scrolling)

Lane: starter factory simplicity review (bead ga-zxf6).
Authority for code under review: the Implementation Worktrees section of
`plans/agent-scrolling/review-context.md`; reviewed the aggregate chain
36e4f6e..b088d2c in `worktrees/ga-q3vr` (HEAD b088d2c, clean; byte-identical
code at `worktrees/ga-lk9y` b884d9c). Changed files:
`lisp/gascity-custom.el`, `lisp/gascity-terminal.el`,
`lisp/test/gascity-test.el`, `doc/gascity.texi`, plus the WI summary and QA
artifacts.

## Verdict: approve

No required fixes. The change is a tight, well-factored addition to one
module plus its tests; boundaries are readable and the abstractions earn
their keep.

## What reads well

- **One file, one section.** All of the feature lives in
  `lisp/gascity-terminal.el` under two clearly delimited `;;;` sections
  (Emacs-keys scroll sub-mode, wheel translation), with the single Custom
  toggle in `gascity-custom.el` where the other terminal options live. A
  newcomer can find the whole thing from `C-c s` in one file.
- **Pure core, tested table.** `gascity-terminal--scroll-sequence` is a
  single pcase table and the tests are table-driven against it — the
  smallest possible testable boundary for a byte-translation feature.
- **Reuse over new machinery.** The mouse ensure/teardown ride the
  *existing* attach pre-step round trip and the *existing*
  kill-buffer teardown (`--status-teardown` → `--teardown-script`), rather
  than adding new timers, processes, or hooks. The mirror-optional
  refactor of `--status-install` keeps the teardown always installed,
  which the `no-mirror-installs-teardown` test locks explicitly.
- **No accidental broad changes.** `gascity-custom.el` gains one defcustom;
  `doc/gascity.texi` gains one section; no file outside the terminal area
  was touched. The mode-line segment gained the `[scroll]` marker inside
  the existing segment function instead of a second segment — good.
- Docs (`texi` + file header commentary) match the code's actual
  behaviour, including the empirically-locked M-</M-> decision and its
  rationale.

## Minor, non-blocking notes (smallest useful fix, none required now)

1. **Duplicated escape bytes** — the C-Up/C-Down sequences `"\e[1;5A"` /
   `"\e[1;5B"` appear both in `gascity-terminal--scroll-sequence` and
   inline in `gascity-terminal-scroll-wheel`. If they ever change (e.g. a
   tmux version quirk), two places must move together. Smallest fix: hoist
   them into two `defconst`s next to `gascity-terminal--copy-mode-entry`
   and use them in both spots.
2. **Function names slightly behind their duty** —
   `gascity-terminal--status-install` / `--status-teardown` now also
   install/restore the mouse ensure, not just the status mirror. The
   docstrings say so plainly, so this is cosmetic only; a future rename to
   something like `--attach-overrides-install` would make the call site in
   `gascity-terminal-run` self-describing.
3. **Style nit** — a doubled blank line separates
   `gascity-terminal--scroll-wheel-first` from
   `gascity-terminal-scroll-toggle`; the file otherwise uses single blank
   lines between definitions.

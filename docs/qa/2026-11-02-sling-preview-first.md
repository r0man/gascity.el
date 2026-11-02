# Sling preview-first — tmux acceptance pass

- Date: 2026-11-02
- Item: ga-51s4b — "Sling: launch should always open the full preview first"
- Environment: fresh `emacs -nw -Q` inside tmux (`sling-accept`, 160x50),
  package loaded from this worktree (`lisp/` on `load-path`, sibling
  beads.el + vui on `EMACSLOADPATH`), `load-prefer-newer` t.
- City: `/home/roman/bright-lights` (the local checkout of the remote test
  city; the pass exercises UI/keystroke behavior, not TRAMP path handling).

## What was exercised and observed

1. **Menu Actions.** `M-x gascity`, then `S`, showed the sling menu with
   `s Preview & launch…` in the Actions group and no `P` row:

   ```
   Actions
    s Preview & launch…
    r Preview recipe…
    g Refresh catalog
    x Reset (clear work, formula, target)
    q Quit
   ```

2. **Freeform work.** `A` → empty `RET` → freeform text
   `acceptance preview test`; the header sentence and the live footer
   updated (`✓ Ready — plain route · target rig-scoped · no vars`).

3. **`s` opens the full preview, not a launch.** Pressing `s` left the
   menu and opened `*gc-sling: preview@/home/roman/bright-lights/*` titled
   `Sling preview — bright-lights  (s or C-c C-c launch · q abort)` with
   the header sentence, `Validation`, the `Recipe` section (plain: none
   picked) and the `Routing plan (gc sling … --dry-run)` section filled
   with gc's dry-run output (`Session config: hello-world/gc.implementation-worker`,
   `No side effects executed (--dry-run).`).  No dispatch happened.

4. **`q` aborts.** Pressing `q` buries the preview and dispatches nothing;
   the *Messages* buffer stayed empty and no error/echo appeared.

5. **`C-c C-c` launches exactly what was previewed.** In a second pass the
   target was set with `T` to a nonexistent agent (`no-such/agent`) to keep
   the launch side-effect free.  `s` opened the preview again, and
   `C-c C-c` launched: the buffer closed and the echo area reported gc's
   own refusal —

   ```
   gc sling no-such/agent acceptance launch path --json failed: {… "code":"target_resolve_failed",
   "message":"gc sling: agent \"no-such/agent\" not found in city.toml; available agents: …"}
   ```

   This confirms the launch path, the JSON echo/error reporting and the
   buffer quit behavior, with no bead or run created.

## Result

Pass.  The menu's `s` is preview-first for the plain shape; the preview
buffer's `s` and `C-c C-c` launch and `q` aborts.  The `on` and
`--formula` shapes share the same transient key path and are covered by
the ERT suite (`gascity-test-sling-preview-then-launch-formula-on`,
`-formula-only`, `-plain`, `gascity-test-sling-preview-aborts-with-q`).
beads.el's delegated sling is preview-first in the sibling bead's change;
gascity's registered `gc` backend only sees the launch and needed no
change.

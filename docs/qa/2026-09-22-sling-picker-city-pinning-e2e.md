# Sling formula picker city pinning — tmux-Emacs TRAMP e2e acceptance pass

- Date: 2026-09-22
- Item: bead `ga-4ia4` — "[BUG] gascity sling-transient formula picker served
  wrong-city catalog (completing-read minibuffer loses pinned
  default-directory; memoized under empty scope-key)"
- Fix under test: `gascity-sling-dispatch` seeds the `default-directory` of
  the buffer it was invoked from into the scope (`:city`); every
  gc-touching suffix (pick, refresh, target read, recipe preview, run) and
  the menu's own `:setup-children` recipe read executes inside
  `(let ((default-directory (gascity-sling--city-dir))) …)`
  (`lisp/gascity-action.el`).
- Environment: live `emacs -nw -Q` 30.2 in tmux (`gce-e2e`, harness
  `scripts/e2e-harness.sh`), package loaded from the worktree `lisp/` with
  `~/workspace/beads.el/lisp` and Guix `emacs-vui-1.3.0` on the load path.
- City: `/sshx:localhost:/home/roman/bright-lights` (bright-lights, 13
  formulas), with the local `emacs-city` catalog as the foreign-city foil.

## What was exercised and observed

1. **Dashboard over TRAMP.** `gascity-status` at
   `/sshx:localhost:/home/roman/bright-lights/` rendered
   `*gascity-status@/sshx:localhost:/home/roman/bright-lights/*` ("Gas City:
   bright-lights", controller supervisor, pools, agent rows).

2. **The bug's mechanism, re-derived.** `S` opened the unified transient;
   the pick suffix and the menu setup can run with a foreign current-buffer
   directory (transient's menu buffer, or the reused minibuffer a
   `completing-read` inherits — the dogfood report §5 finding). The formula
   catalog/recipe caches key off `gascity-context-scope-key` of whatever
   directory is current at call time, so an unpinned read both queried
   another city and memoized it under the wrong (possibly empty) scope key.

3. **The pick serves the entered-from city (the fix).** `-f` from the
   bright-lights dashboard completed over the *remote* catalog; picking
   `review` re-rendered the same menu in place — `Sling — bright-lights` ·
   `Formula: review` — no `[No match]`, and the header's city name is the
   entered-from city even though menu setup runs in the menu buffer.

4. **Cache keying is per city root, not empty (the discriminating check).**
   The local `emacs-city` and bright-lights catalogs are currently
   identical (same 13 formula names), so catalog *content* cannot
   discriminate; the scope keys can. In the live session: a read warmed
   with `default-directory` = `/home/roman/emacs-city/` memoized under
   `("/home/roman/emacs-city/")`; the subsequent bright-lights pick added
   its own entry — `gascity-formula-catalog-cache` keys were
   `("/sshx:localhost:/home/roman/bright-lights/"
   "/home/roman/emacs-city/")` — 13 entries under the bright-lights key,
   no entry under the empty key (`(assoc "" …)` → nil), and the warm
   foreign entry did not shadow the remote pick. The recipe cache likewise
   keyed `("/sshx:localhost:/home/roman/bright-lights/")`.

5. **Dispatch-path sanity.** `p` (dry-run preview) on the picked formula
   read the target over remote session completion (`Sling to target:`),
   then the client-side required-var validation refused (`review` declares
   required vars) before any gc invocation — the documented validation-first
   behavior, and the menu exited as designed. The pinned execution of the
   dispatch itself is covered by the ERT suite
   (`gascity-test-sling-dispatch-suffixes-run-pinned`, which asserts the
   run/refresh/target/recipe suffixes execute with the pinned directory).

## Result

The formula picker no longer serves a foreign city's catalog: the transient
pins the city it was entered from and every catalog/recipe read, catalog
completion, invalidation and dispatch runs against that directory, and the
caches memoize under the entered-from city's scope key. Cross-city
isolation holds with warm foreign entries. ERT gate green (compile clean +
329 tests).

## Limitations

- Both cities ship identical formula catalogs today, so the live pass
  discriminates via cache keys rather than catalog content; the mock-based
  ERT coverage exercises the content-level discrimination.
- The full dispatch-with-vars flow (workflow root creation) was not
  re-exercised in this pass — it is unchanged code covered by the earlier
  sling e2e passes and by ERT; the refused required-var path was confirmed
  live.
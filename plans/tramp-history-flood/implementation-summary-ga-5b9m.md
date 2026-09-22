---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-elny
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
    - path: beads/ga-5b9m
      hash: bead:ga-5b9m
      ids:
        - ga-5b9m
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-003
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
    - path: doc/gascity.texi
      hash: git:0ff545428f0fda9b91e0a528eddd218d4edf2659
    - path: docs/qa/2026-09-21-bashrc-guard-recipe.md
      hash: git:0ff545428f0fda9b91e0a528eddd218d4edf2659
  coverage:
    - id: ga-5b9m
      status: covered
    - id: REQ-003
      status: covered
    - id: AC-3
      status: covered
---

# Implementation Summary: W4 — Host-side `.bashrc` guard recipe (docs only)

### Trace Coverage

| ID      | Status  |
| ------- | ------- |
| ga-5b9m | covered |
| REQ-003 | covered |
| AC-3    | covered |

## Summary

Implemented plan section W4 (`plans/tramp-history-flood/implementation-plan.md`,
"Host-side `.bashrc` guard recipe", REQ-003 / AC-3) as a documentation-only
change, committed in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-5b9m` at commit `0ff5454`:

1. `doc/gascity.texi` — new section *Host-side shell history guard* under the
   *Customization* chapter (next to the TRAMP-adjacent *Context overrides*
   material). It explains why every TRAMP connection and one-shot ssh command
   grows `~/.bash_history` when the rc file sets a multi-window
   `PROMPT_COMMAND` history trick, and gives the copy-paste guard:

   ```bash
   if [[ $- != *i* && -n $SSH_CONNECTION ]]; then
       unset HISTFILE
       return 2>/dev/null || exit
   fi
   ```

   to be placed at the very top of `~/.bashrc`, before profile sourcing and
   before the `PROMPT_COMMAND` history block (line 69 in the user's actual
   file). The section walks through each part of the guard (`$- != *i*`,
   `unset HISTFILE`, `return 2>/dev/null || exit`), notes interactive shells
   are unaffected, documents a gascity.el-independent verification procedure
   (`ssh localhost true` a few times, then check `~/.bash_history` stopped
   growing), and states that truncating the already bloated `~/.tramp_history`
   is a user-run command the workflow never executes.

2. `docs/qa/2026-09-21-bashrc-guard-recipe.md` — dogfood/QA note restating the
   recipe, the evidence behind it, and the hard non-goal: the workflow never
   edits `~/.bashrc`, `~/.bash_history`, or `~/.tramp_history` on the user's
   host.

## Intended Behavior

REQ-003: a host-side neutralization recipe, working regardless of gascity.el,
documented in the rig docs — not applied to the user's dotfiles. After a user
applies the guard, non-interactive sshd-spawned shells (one-shot ssh commands,
TRAMP's remote process execution, remote cron) record no history at all and
skip the interactive `PROMPT_COMMAND` history trick entirely, so per-refresh
ssh churn stops polluting `~/.bash_history`. AC-3: the recipe exists in the rig
docs with an exact copy-paste snippet, and this workflow's `git status` shows no
modification to the user's dotfiles (only `doc/gascity.texi` and the
`docs/qa/` note changed).

## Changed Files

| File | Change |
| --- | --- |
| `doc/gascity.texi` | New `@section Host-side shell history guard` in the *Customization* chapter (+~90 lines, no existing prose touched). |
| `docs/qa/2026-09-21-bashrc-guard-recipe.md` | New QA note with the copy-paste recipe, evidence, and non-goal statement. |

Committed as `0ff545428f0fda9b91e0a528eddd218d4edf2659`
(`docs(customization): host-side .bashrc history guard recipe (ga-5b9m)`).

## Verification

First verification command — Texinfo manual build from the worktree:

```
cd /home/roman/workspace/gascity.el/worktrees/ga-5b9m && make -C doc
```

Observed: **pass** — `makeinfo` (info) and `makeinfo --html` both completed
without warnings or errors; the new section renders in the info/HTML output.

Final proof command — full quality gate from the worktree:

```
cd /home/roman/workspace/gascity.el/worktrees/ga-5b9m && scripts/gate.sh
```

Observed: **pass** — byte-compile clean with `--warnings-as-errors`, and the
ERT suite ran `322 tests, 322 results as expected, 0 unexpected`
(`>>> gate: PASS (compile clean + tests green)`).

Non-modification proof (AC-3): `git status` in the worktree after the commit
lists only the two documented files; no command in this workflow wrote to
`~/.bashrc`, `~/.bash_history`, or `~/.tramp_history` on the user's host.

## Remaining Risks

- The guard only covers **non-interactive** sshd-spawned shells. TRAMP's
  interactive inner shell (`/bin/sh -i` with `TERM=dumb`, writing
  `HISTFILE=~/.tramp_history`) is out of this item's boundary; it is handled
  by the `HISTFILE=/dev/null` recommendation via
  `tramp-remote-process-environment` (REQ-004, plan section W3, separate item).
- Existing `~/.tramp_history` bloat (655 KB) is not truncated by the guard;
  truncation stays a documented, user-run, consent-required command (REQ-004).
- The suspicious non-TRAMP `cd emacs-city/` history write (REQ-006) is not
  attributed here; it is a separate item's boundary.
- The recipe's `[[ ... ]]` syntax assumes the remote login shell is bash (the
  target host's shell here); POSIX-only rc files would need a `case $- in *i*`
  formulation, noted in the manual section prose.

# Host-side `.bashrc` guard recipe — W4 note (bead ga-5b9m, REQ-003, AC-3)

## What this is

A copy-paste guard for `~/.bashrc` that keeps **non-interactive sshd-spawned
shells** from recording command history. It is documented in the Texinfo
manual, node *Customization*, section *Host-side shell history guard*
(`doc/gascity.texi`).

## Why

The TRAMP-history investigation (requirements `plans/tramp-history-flood/requirements.md`)
verified host-side that:

- even plain `ssh localhost true` grows `~/.bash_history` with the login
  command line, one per TRAMP connection;
- `~/.bashrc` (line 69) sets the multi-window `PROMPT_COMMAND` history trick
  (`shopt -s histappend` + `history -a; history -c; history -r`), which every
  sourced shell inherits;
- gascity.el's auto-refreshing remote views drive connection *volume*, so
  history pollution scales with refresh ticks.

## The recipe (copy-paste)

Place at the **very top** of `~/.bashrc`, before profile sourcing and before
the `PROMPT_COMMAND` history block:

```bash
# Non-interactive shells spawned over ssh (one-shot ssh commands,
# Emacs/TRAMP plumbing, remote cron, ...): record no history.
if [[ $- != *i* && -n $SSH_CONNECTION ]]; then
    unset HISTFILE
    return 2>/dev/null || exit
fi
```

- `$- != *i*` — matches non-interactive shells (sshd runs one-shot commands
  and remote process execution through these; they still source `~/.bashrc`).
- `unset HISTFILE` — the shell records nothing to any history file on exit.
- `return 2>/dev/null || exit` — skip the rest of `.bashrc`, including the
  interactive `PROMPT_COMMAND` trick; `exit` covers direct execution.
- Interactive shells (`$-` contains `i`) are unaffected.

## Hard non-goal

**The workflow never edits `~/.bashrc`, `~/.bash_history`, or
`~/.tramp_history` on the user's host.** The recipe is shipped as
documentation only; applying it is a user action. Truncating the already
bloated `~/.tramp_history` (655 KB at investigation time) is likewise a
user-run command, documented but never executed by the workflow.

## Verification

- `make -C doc` from the worktree root: Texinfo manual builds clean with the
  new section (makeinfo + texi2html pass).
- `scripts/gate.sh` from the worktree root: byte-compile with
  `--warnings-as-errors` and the ERT suite stay green (the change is
  documentation-only; no Elisp touched).
- `git status` in this repository shows no modification to any dotfile; the
  only changed files are `doc/gascity.texi` and this note.

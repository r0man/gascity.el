# Control-dispatcher epoch timestamps render as unknown (ga-4mvlw.1)

Dogfood source: 2026-10-16 bright-lights (ro), session `ec-wisp-z0b7po`.

## Finding

Control-dispatcher sessions carried gw's zero-value timestamps
(`1970-01-01T00:04:56Z`) and no `session_key`.  The Agents list showed
`1970-01-01` in Active, the agent detail header showed
`last active 1970-01-01` and `created 1970-01-01`, and the status tree
read the epoch as an enormous age, labelling a live session idle.

The gc-side missing `session_key`/ambiguous workdir also leaves the
Transcript section's `gc session logs` read failing; that half is a gc
CLI defect and is not fixable in the porcelain.  The UI fallback is the
behaviour this change owns.

## Change

`gascity-ui-epoch-time-p` treats any timestamp before 2000-01-01 as
gc's placeholder.  Relative times, `gascity-ui-time`/`-ago`, the
transcript clock and `gascity-tabulated--format-timestamp` now render
such a value as `—` instead of a 1970 date.  The status tree ignores the
placeholder when computing idleness, so a live control dispatcher stays
`active`.

## Acceptance

Non-graphical Emacs in tmux, loading the changed tree
(`/tmp/ga-4mvlw.1/lisp`), fed the exact dogfood shape:

```
AGENTS ACTIVE: —
TABULATED: —
AGO: —
```

Quality gates on the isolated worktree:

- `scripts/gate.sh` — 877/877 tests pass, byte-compile clean
- `scripts/lint.sh` — clean (package-lint not installed locally)

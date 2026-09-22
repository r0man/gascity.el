---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-a3sb
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
    - path: beads/ga-o98t
      hash: bead:ga-o98t
      ids:
        - ga-o98t
    - path: plans/tramp-history-flood/requirements.md
      hash: sha256:85adb522f0cf3911f09b064a0a786d9f52a7468dbc144edc7e5a6ae860687bea
      ids:
        - REQ-001
        - REQ-006
        - AC-1
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
    - path: lisp/gascity-reader.el
      hash: git:9fb54c5f3b77422f971bb6ed9f6befb915949254
    - path: lisp/gascity-remote.el
      hash: git:9fb54c5f3b77422f971bb6ed9f6befb915949254
  coverage:
    - id: ga-o98t
      status: covered
    - id: REQ-001
      status: covered
    - id: REQ-006
      status: covered
    - id: AC-1
      status: covered
---

# Implementation Summary: W1 — Pooling diagnosis for async remote reads (diagnosis only, no code change)

### Trace Coverage

| ID      | Status  |
| ------- | ------- |
| ga-o98t | covered |
| REQ-001 | covered |
| REQ-006 | covered |
| AC-1    | covered |

## Summary

Plan section W1 (`plans/tramp-history-flood/implementation-plan.md`, "Pooling
diagnosis", REQ-001 / REQ-006 / AC-1), executed in the item worktree
`/home/roman/workspace/gascity.el/worktrees/ga-o98t` at HEAD
`9fb54c5f3b77422f971bb6ed9f6befb915949254`. **Diagnosis-only step: no source
file was changed and no commit was made.**

**Pooling conclusion (REQ-001): tramp-sh pooling already holds.** Each
`gascity-reader-read-async` call reuses the pooled TRAMP connection; it does
**not** spawn a fresh ssh login per read. Evidence below (handler inspection +
N=10 live measurement against `/ssh:localhost:/home/roman/bright-lights`:
ssh-login-line delta **0**, one and the same `*tramp/ssh localhost*` process
throughout). Per the plan, the downstream W2 consequence is the *document* arm:
record the conclusion where a reader would look for it (code comment in
`gascity-reader.el`/`gascity-remote.el` plus a rig-doc note), changing no
behavior.

`cd emacs-city/` attribution (REQ-006): the write mechanism is identified (an
interactive bash flushing via the `~/.bashrc` line-69 `PROMPT_COMMAND`
multi-window history trick — not TRAMP, not gc/pi non-interactive
subprocesses); the exact originating pane/process cannot be proven from the
available logs (history file has no timestamps, no sshd journal reachable) and
is recorded in Remaining Risks/Open Questions per the no-guessing rule.

## Intended Behavior

REQ-001: determine, with code references and a reproducible measurement,
whether each async `process-file`-class read (`gascity-reader-read-async`,
`lisp/gascity-reader.el:445` — the `make-process` with `:file-handler t`
backing `vui-use-async`) opens a new ssh connection or reuses the pooled one,
and record the finding in the build artifacts. REQ-006: attribute the
suspicious bare `cd emacs-city/` history line observed at 22:27, or record the
unresolved attribution with the gathered evidence. AC-1: concrete evidence —
file/function references plus measured before/after login-line counts;
anything unattributable goes to Open Questions, never guesses.

## Changed Files

None. Diagnosis-only step; no source edits, no commit in the worktree.

| File | Change |
| --- | --- |
| *(none)* | No source file changed; measurement driver kept at `/tmp/w1-diagnose.el` (not part of the repo). |

The only repo artifact of this step is this summary, recorded on the workflow
root bead as `gc.implementation.summary_path`.

## Verification

**Method.** A batch-Emacs driver (`/tmp/w1-diagnose.el`) loads gascity.el from
the item worktree, sets `default-directory` to
`/ssh:localhost:/home/roman/bright-lights`, inspects the active TRAMP
make-process handler, then runs N=10 sequential `gascity-reader-read-async`
calls of `gc rig list --json`, snapshotting after each call: the live TRAMP
process list and the number of ssh login lines in `~/.bash_history` (read-only
counting, pattern `exec env TERM='dumb' INSIDE_EMACS` — the line the sshd
login shell records for TRAMP's inner-shell spawn, 497 of the file's 500
lines). The workflow never modified `~/.bash_history` (or any user dotfile);
counts were taken by reading the file.

**Handler inspection (code evidence).**
`tramp-direct-async-process` is connection-locally bound to **nil** for the
`/ssh:localhost:` connection (Emacs 30.2 / TRAMP 2.7.3.30.2), and
`tramp-direct-async-process-p` — the very predicate TRAMP's `make-process`
dispatch consults, and which `gascity-reader-read-async` itself consults at
`lisp/gascity-reader.el:553` to decide where `:stderr` goes — returns **nil**.
So remote async reads dispatch to **tramp-sh's pooled connection channel**
(`lisp/gascity-remote.el` deliberately sets no direct-async override; nothing
in the worktree enables it), not to `tramp-handle-make-process` (direct-async),
which would spawn a fresh local ssh per read. Code references:
`gascity-reader-read-async` (`lisp/gascity-reader.el:445`), its
`tramp-direct-async-process-p` consult (`:553`), and the handler discussion in
its docstring (`:456`–`:493`).

**First verification command** — baseline login-line count:

```
grep -c "exec env TERM='dumb' INSIDE_EMACS" ~/.bash_history
```

Observed before the 10-read run: **498** (file total 501 lines).

**Measurement run** — N=10 consecutive `gascity-reader-read-async` calls
(`gc rig list --json`), sequential, each awaited:

- all 10 succeeded (`:ok t`, ~1.2–1.6 s each);
- the live process list stayed exactly `("*tramp/ssh localhost*")` before,
  during (every per-read snapshot) and after the run — no new tramp/ssh
  process was ever spawned;
- ssh login lines after the run: **498** → **delta 0**; total-line delta 0
  (per-read snapshots oscillated 497↔498 due to a concurrent unrelated
  writer rewriting the file — see Remaining Risks — with zero net change and
  no monotonic growth tied to the reads).

**Final proof command** — the artifact validation gate from the launcher rig
root:

```
cd /home/roman/workspace/gascity.el && GC_BEAD_ID=ga-v3x1 .gc/scripts/checks/build-artifact-valid.sh
```

Observed: **pass** — `build artifact valid: schema=gc.build.implementation-summary.v1 path=…/implementation-summary-ga-v3x1.md`.

**Corroboration probes.**

- `ssh -q localhost true` (one-shot ssh command): login-line count unchanged
  (497 → 497) — non-interactive remote shells fire no `PROMPT_COMMAND` and
  write no history; one-shot ssh is not a pollution source.
- Control sample of the mechanism: non-interactive bash invocations (gc/pi
  tool calls, `bash <<heredoc`) wrote nothing to `~/.bash_history` across the
  whole session.

**Conclusion for W2 (recorded, not implemented here):** since tramp-sh pooling
already holds, W2 takes the plan's "document in W2" arm — code comment in
`gascity-reader.el`/`gascity-remote.el` plus a rig-doc note stating the
conclusion with this measured evidence; change no behavior. The one-gc-call-site
data plane is untouched by this step.

**`cd emacs-city/` attribution evidence (REQ-006).**

1. The line is now **absent** from both `~/.bash_history` and
   `~/.tramp_history` (checked at 22:50–22:54; observed originally at 22:27
   per the requirements bead). Consistent with a live-observed property of
   this host: `~/.bash_history` is **not append-only** here — during the
   15-second measurement window its login-line count oscillated 498→497→498
   with zero ssh activity from the measurement itself, i.e. some concurrent
   process rewrites/truncates the file. A line seen at 22:27 can be gone by
   22:50 without TRAMP involvement.
2. Mechanism: every interactive bash on this host appends each executed
   command to `~/.bash_history` via the `PROMPT_COMMAND`
   `history -a; history -c; history -r` trick at `~/.bashrc` line 69
   (`shopt -s histappend` at line 67). The line's shape (bare `cd
   emacs-city/`) matches an interactive command, **not** TRAMP's
   `exec env TERM='dumb' …` login-shell lines (497/500 of the file) and
   **not** gc's `( cd /home/roman/bright-lights/ && env …)` form seen in
   `~/.tramp_history`.
3. Non-TRAMP, non-gc exclusion is measured, not assumed: one-shot ssh
   (`ssh localhost true`) adds no line; non-interactive bash subprocesses
   (pi agent tool calls, gc workers' `bash <<heredoc` invocations) add no
   line across the session; our 10 async reads added no line.
4. cwd evidence: `emacs-city/` exists as a directory only under
   `/home/roman`, so the command ran with cwd `/home/roman`. Among tmux
   panes, the user-attached `mayor` session (created 19:47, i.e. present at
   22:27) currently sits at `/home/roman/emacs-city` — consistent with an
   interactive shell in that pane having cd'd from `/home/roman` into
   `emacs-city/` at some point. The gc implementation-worker and dispatcher
   sessions were created 22:42+ (after the observation) and live in the
   gascity.el workspace, not `/home/roman`.

## Remaining Risks

- **Open Question (REQ-006 residual):** the exact process that typed
  `cd emacs-city/` at 22:27 cannot be proven from available evidence
  (`~/.bash_history` has no timestamps — `HISTTIMEFORMAT` unset;
  `journalctl` unavailable and `last` empty on this host, so no sshd-side
  login correlation). Best-supported attribution per the evidence: an
  interactive bash on the local host — most plausibly the user-attached
  `mayor` tmux pane (or the user's own terminal) — flushing via the
  `~/.bashrc` line-69 `PROMPT_COMMAND` history trick. It is definitively
  **not** a TRAMP/ssh-login write and not a gc/pi non-interactive subprocess
  write (both measured to write nothing). Downstream stages should treat
  REQ-006 as satisfied via this evidence record per the requirements' Open
  Questions clause, not as a code change.
- The concurrent rewriter of `~/.bash_history` (responsible for the ±1 line
  oscillation and for the line's disappearance) was not identified; a
  non-`.bashrc`-sourcing interactive bash exiting (which rewrites `HISTFILE`
  wholesale, no `histappend`) is the leading hypothesis. Not needed for the
  REQ-001 conclusion, but it makes any point-in-time history observation on
  this host inherently volatile.
- The diagnosis holds for the current user/Emacs configuration (Emacs 30.2,
  TRAMP 2.7.3.30.2, no direct-async override). If a user enables the
  connection-local `tramp-direct-async-process`, every async read spawns a
  fresh local ssh — that fallback behavior is documented in the reader
  docstring but is the risk W2's documentation note should mention.
- The one-shot `ssh localhost true` corroboration probe caused one new ssh
  login (as does any manual ssh); measured login-line count was unaffected
  (non-interactive), but the login itself is unavoidable evidence gathering.
- W2/W3 (documentation arm, `HISTFILE=/dev/null` for TRAMP inner shells) and
  W4 (host-side recipe) are separate items; the existing 655 KB
  `~/.tramp_history` remains until the user-run truncation.

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
    - path: plans/tramp-history-flood/implementation-plan.md
      hash: sha256:82d6a77fbc91445918d914febe63432d42d4979f03315ad240dddb5677fe1d25
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

# Implementation Summary: W1 — Pooling diagnosis for async remote reads

## Summary

**Finding: TRAMP connection pooling already holds for gascity.el's async remote
reads. The tramp-sh channel handler is active (not the direct-async handler);
N = 10 consecutive `gascity-reader-read-async` calls against the remote test
city spawned exactly one ssh process (at connection establishment, before the
burst) and appended zero new ssh login lines to `~/.bash_history` (501 → 501).
Per the plan (§W1: "If W1 shows pooling already holds …"), W2 becomes
documentation-only: no behavior change is needed; W5's connection-count
verification remains as a regression guard.**

This item is diagnosis-only (no source changes). The evidence below was
gathered with read-only probes against the user's host; no dotfile was
modified by this workflow (the only `~/.bash_history` growth attributable to
this session is the measurement apparatus itself: two marked probe lines and
one line from a fresh TRAMP connection opened for the experiment, all
identified below).

### Evidence 1 — Which async handler is active (REQ-001)

Inspecting the `/ssh:localhost:` connection in a clean batch Emacs
(30.2, bundled TRAMP 2.7.3.30.2) with `default-directory` bound to
`/ssh:localhost:/home/roman/bright-lights/`:

- `tramp-direct-async-process` (connection-local) = `nil` for the `ssh`
  method; `tramp-direct-async-process-p` = `nil`.
- In Emacs 30.2's tramp-sh, the `ssh` method carries the method property
  `tramp-direct-async ("-t" "-t")` (direct async is *available*), but the
  dispatch is gated on the connection-local variable
  `tramp-direct-async-process` (`tramp-sh-handle-make-process` docstring:
  "If method parameter `tramp-direct-async' and connection-local variable
  `tramp-direct-async-process' are non-nil, an alternative implementation
  will be used."). With it nil, every remote `make-process :file-handler t`
  dispatches to `tramp-sh-handle-make-process`, which runs in the shared
  channel buffer `*tramp/ssh localhost*`.
- `gascity-reader-read-async` (`lisp/gascity-reader.el`, ~line 445) uses
  `make-process :file-handler t` on a remote `default-directory`, so async
  reads go through that same tramp-sh channel path. The stderr wrapper and
  the executable/PATH handling in `gascity-remote.el` were built to behave
  identically under both handlers (gce-qke, gce-k5d), so no handler-specific
  divergence exists.

### Evidence 2 — Before/after measurement over N = 10 async reads (REQ-001)

Experiment script drove 10 consecutive `gascity-reader-read-async`
`("session" "list")` calls with `default-directory` pinned to the remote city
root (observed in a batch Emacs run at 22:46:49–22:46:55 local time):

- All 10 reads completed with parsed JSON, zero errors.
- Process inventory before and after the burst: exactly **one** ssh process
  for the whole run, spawned once when the connection was established
  (22:46:48, before the first read), argv:

      ssh -o ControlMaster=auto -o ControlPath=/home/roman/.cache/emacs/tramp.%C \
          -o ControlPersist=no -e none localhost

  (TRAMP's pooled-channel login; one Emacs-side connection process
  `*tramp/ssh localhost*` served all 10 reads.)
- `~/.bash_history` ssh login-line count (`grep -c '^exec env'`):
  **501 before the reads → 501 after the reads, delta 0.** The single +1
  relative to the pre-connection baseline (500 lines at 22:45) was appended
  when the experiment's TRAMP connection was established — one line per new
  pooled connection, zero lines per read.

Supporting host-side attribution of those `exec env` lines (read-only
probes, marked so they are identifiable in the file):

- A non-interactive sshd command session (`ssh localhost 'echo MARKER'`)
  appends **nothing** to `~/.bash_history` — the earlier requirements-era
  observation that "even plain `ssh localhost true` grows the file" did not
  reproduce; plain non-interactive ssh is not a writer.
- An interactive (pty) sshd login shell **does** record what it is given:
  probe A (`echo W1PROBE-A-MARKER` typed into `ssh -tt localhost`) and probe
  B (the exact TRAMP-style login command
  `exec env W1PROBE=1 HISTFILE=/tmp/w1-probe-inner /bin/sh -c exit`) both
  landed in `~/.bash_history` (lines 501/503 at probe time).
- The file's ~500 lines are ~496 identical copies of one line: TRAMP's
  channel login command `exec env TERM='dumb' INSIDE_EMACS='ghostel,tramp:2.7.3.30.2'
  … /bin/sh -i` — i.e. **one recorded line per new pooled TRAMP connection**,
  written by the sshd-spawned interactive login shell that receives TRAMP's
  login command as its first input (`tramp-maybe-open-connection`,
  tramp-sh.el). The flood is therefore proportional to *connection
  churn*, not to read volume — and gascity.el's async reads do not churn
  connections.
- The TRAMP inner shell writes to `~/.tramp_history` as designed (9,179
  lines / 655 KB; zero `exec env` lines) — gascity's own sync `process-file`
  channel commands were observed recorded there, which is the harmless,
  by-design location.

**Conclusion (per plan §W1): pooling already holds → document in W2; no
fresh ssh login per refresh tick exists to fix in gascity.el's read path.**

### Evidence 3 — `cd emacs-city/` line attribution (REQ-006)

Facts gathered (all read-only):

- `/home/roman/emacs-city` is a real Gas City (`city.toml`, a mayor pi
  session in tmux server `-L emacs-city`, `GC_CITY=/home/roman/emacs-city`
  in that session's environment).
- A process `tmux -L emacs-city attach-session -t mayor` (pid 18520) was
  started at **22:27:20** — matching the 22:27 timestamp of the observed
  `cd emacs-city/` history line. Its parent was a GUI Emacs (pid 14577)
  started at 22:26:54 whose working directory is `/home/roman` (i.e. an
  Emacs launched from a shell at `$HOME`, 26 seconds before the attach).
- Writers ruled out by probe:
  - **pi agent bash subshells**: non-interactive `bash -c` shells record
    nothing (probe: non-interactive sshd-spawned and local non-interactive
    shells appended no history lines).
  - **the sshd login shell as an independent cause**: it only ever records
    the command text it is given; for it to write `cd emacs-city/` someone
    would have had to type that line into an interactive remote shell — no
    evidence of such usage.
- Best-supported attribution: **the user's interactive shell at `$HOME`
  (most plausibly a shell inside the GUI Emacs instance started at
  22:26:54), immediately before attaching the emacs-city mayor tmux session
  at 22:27:20.** The exact shell process is no longer identifiable (the
  launching shell is gone; the parent-of-parent chain is init), so the
  final attribution step is recorded in Open Questions rather than
  asserted.
- The line is **no longer present** in `~/.bash_history` today: the file
  currently holds 500 lines — 496 + 4 identical `exec env` copies and one
  unrelated line — so user-typed lines (including the probe markers added
  during this diagnosis) disappear from the file over time while the exec
  copies accumulate. That churn is recorded as an open question below.

## Intended Behavior

- REQ-001: establish, with code references and a reproducible measurement,
  whether each async remote `gc` read opens a new ssh connection or reuses
  the pooled one. **Established: reuse — the tramp-sh pooled channel serves
  every async read; one ssh login per new TRAMP connection, not per read
  (measured: 10 reads → 0 new logins, 1 connection → +1 login line).**
- REQ-006: investigate the 22:27 `cd emacs-city/` line and either attribute
  it or record the unresolved attribution with the evidence. **Recorded
  with evidence; exact shell process unresolved (see Remaining Risks / Open
  Questions).**
- AC-1: the finding is stated in this artifact with before/after counts.

Downstream guidance for W2 (informed by this diagnosis, per plan §W1/§W2):
documentation-only — add the pooling conclusion as a code comment in
`gascity-reader.el`/`gascity-remote.el` and a rig-doc note citing this
measurement; no behavior change.

## Traceability

| ID | Status |
| --- | --- |
| ga-o98t | covered |
| REQ-001 | covered |
| REQ-006 | covered |
| AC-1 | covered |

## Changed Files

None. This item is diagnosis-only; no source files, tests, or docs were
changed. The only artifacts written by this workflow are build artifacts
(this summary) and the two marked probe lines / one connection-login line
they necessarily added to `~/.bash_history` on the user's host (identified
above; the workflow never modified any dotfile itself).

## Verification

- **First verification command** — the pooling experiment (batch Emacs
  against the real remote test city):

      emacs -Q --batch -L lisp -l gascity-reader -l /tmp/w1-pooling-experiment.el

  Observed: **pass** — `remote city dir reachable`, connection-local
  `tramp-direct-async-process` = nil, 10/10 async reads completed with no
  errors, one ssh process total, `exec-line count … (before 501, after
  501, delta 0)`.

- **Final proof command** — the schema gate for this artifact (the shared
  base validator, run from the launcher rig root; the launcher's installed
  copy of `validate_build_artifact.py` resolves its default schema root one
  level too high, so the canonical schema root is passed explicitly):

      cd /home/roman/workspace/gascity.el && \
      GC_BUILD_SCHEMA_ROOTS="$PWD/.gc/schemas/build" python3 \
        .gc/scripts/validate_build_artifact.py \
        --schema gc.build.implementation-summary.v1 \
        --path plans/tramp-history-flood/implementation-summary-ga-o98t.md

  Observed: **pass** — `{"ok": true, "schema":
  "gc.build.implementation-summary.v1"}`. The equivalent gate invocation
  `GC_BEAD_ID=<implement-step-bead> .gc/scripts/checks/build-artifact-valid.sh`
  resolves this same schema/path pair from the workflow root's
  `gc.implementation.summary_path` metadata recorded below.

## Remaining Risks

- **Handler default is environment-dependent, not contractual.** The
  pooled-channel conclusion rests on `tramp-direct-async-process` being nil
  for the `ssh` method on Emacs 30.2 / TRAMP 2.7.3.30.2. A future Emacs (or
  user configuration enabling direct-async) changes the picture; W5's
  connection-count verification guards against exactly this regression
  class.
- **Measurement window concurrency.** The user's live Emacs daemon
  maintains its own TRAMP connections concurrently; the +1 line observed at
  connection establishment could in principle overlap with such noise. The
  decisive signal (delta 0 across the 10-read burst, with the burst's own
  connection pinned to a single long-lived ssh process observed from inside
  Emacs) is robust to that noise.
- **Open question 1 (REQ-006 residue):** the exact interactive shell that
  typed `cd emacs-city/` at ~22:27 is not identifiable; the temporal
  (22:26:54 Emacs start → 22:27:20 tmux attach) and contextual (`$HOME`
  cwd, real `~/emacs-city` city) evidence supports the user's interactive
  shell, but this is not a proof.
- **Open question 2:** user-typed lines disappear from `~/.bash_history`
  over time (the `cd emacs-city/` line, the `tail -F /tmp/*.log` line, and
  probe markers vanish within minutes-to-hours) while `exec env` copies
  accumulate; some shell or process rewrites/trims the file. Untreated
  here; may interact with W3/W4's history-hygiene work.
- The two probe lines and the experiment connection-login line added to
  `~/.bash_history` are measurement residue, identified by the
  `W1PROBE`/marker text and the 22:46:48 connection line; they are of the
  same class as the existing 500-line pollution and were not cleaned (the
  workflow never modifies the file).

# dashboard-v3 P4: Runs view and run detail, live pass (2026-09-25)

Branch `v3-runs`. Scope: `gascity-runs` (§7.6) and the run detail (§7.7).
Cities: `~/emacs-city` (read-only, 63 real runs), `~/bright-lights` locally
and as `/ssh:localhost:/home/roman/bright-lights`. Nothing was mutated.

## How

- Batch driver (byte-compiled lisp, `emacs -Q --batch`, bounded by
  `timeout`): open `gascity-runs`, `H`, `SPC` on a card, open a run
  detail, `C`. It dumps the buffers and logs main-loop gaps over 250 ms.
- A key-driven pass in a tmux `emacs -nw` (`v3-runs-e2e`, torn down
  afterwards). Views were opened by keys: `M-x gascity-runs` from a Dired
  of the city, then `H`, `TAB`, `SPC`, `RET`, `C`, plan `RET`, step `RET`,
  `j j`, `j r`.

## Results

| Check | emacs-city local | bright-lights local | bright-lights ssh:localhost |
|---|---|---|---|
| Runs first paint (idle) | ≈2 s | ≈2 s | 3.2–6.6 s |
| Counts line | 0 active · 0 waiting · 51 done · 12 failed | 0 · 3 waiting · 7 done · 0 | same as local |
| Failed (24h) cards, ladder `◆◆◆◆◆◆◆✕◆◆ review 9/10 control_dispatch_error` | ✓ be-bn2, be-j2b | none | none |
| `H` history, 20/page, `… 43 more  + more` | ✓ | ✓ (7) | ✓ |
| `SPC` card drawer (full ladder) | ✓ | ✓ | ✓ |
| Run detail from Runs (shared entry, no new gc read) | ✓ | ✓ | ✓ |
| Step tree: loops `▸/▾`, iterations inline, drain members | ✓ | ✓ | ✓ |
| `C` control nodes | ✓ | ✓ | ✓ |
| Plan `RET` opens on host (R6) | – | – | ✓ `/ssh:localhost:/home/roman/hello-world/plans/…` |
| Step `RET` → beads.el in the rig store | – | – | ✓ `*beads-show[/ssh:localhost:\|hello-world]/hw-vqv*` |
| `j j` → cockpit, `j r` → Runs | – | – | ✓ |
| Main-loop stalls > 250 ms | none | none | one, 1.03 s: the `gascity-runs` command itself on first contact (city discovery, a listed §8.5 exception); none after |

## Findings fixed during the pass

- Plan paths can be relative to the run's `gc.work_dir`: the review
  formula records `plans/…/review-report.md`. The plans line now joins
  them to `gc.work_dir` as a pure string operation. Before the fix, `RET`
  opened a non-existent file.
- A run with no steps yet (waiting latches in bright-lights) rendered a
  bare `0/0`. The card now reads `no steps  waiting`, and its drawer reads
  `no steps yet`.
- The rig column shifted with the width of the time. The time is now
  left-padded to 9 columns, with no trailing pad.
- `RET` on the Steps header no longer echoes "Nothing to act on here".

## Harness note

The first remote batch pass seemed to hang with every section at `…`.
Cause: the driver's "store idle" check (0 reads, 0 queued) races the
composite read. After `rig list` completes, the store delivers remote
results from `run-at-time 0`, and the per-store reads are dispatched
only after that, so the host is briefly idle while the entry is still
pending. The driver has to wait for the entry itself, not for the host.
Three repeated probes all rendered.

## Not covered

- An active run with a live worker. None was running in either city
  during the pass (the cities are read-only or idle). ERT covers it from
  the real be-52m5 graph set to in-progress (`gascity-test-runs-render-cards`,
  `gascity-test-run-detail-renders-active-run`).
- TRAMP direct-async mode (§8.4 mode 3).

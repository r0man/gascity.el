# dashboard-v3 §8.4: the TRAMP matrix, all views (2026-09-25)

Target: bright-lights, as `~/bright-lights` and as
`/ssh:localhost:/home/roman/bright-lights`. Main at `f80fab1` (store round 3
and P3 live merged). Driver: `scripts/qa/dashboard-v3-tramp-matrix.el`, a
batch Emacs per mode, byte-compiled lisp, every call bounded by `timeout`.
The driver opens, in order: cockpit, Agents, Agents tree, agent detail
(mayor), Runs, run detail (hw-hry), Health, Cities, the rig dashboard
(hello-world), mail, convoys, orders, dolt and sessions. For each view it
waits until the store settles (at most 90 s, 40 s for the last two modes).
It then refreshes every view at once (contention) and waits for the live
`seq` to advance. It records a view as ready once its buffer has no read
in flight and the host has no read running or queued.

## Modes

| Mode | What it is |
|---|---|
| local | `~/bright-lights` |
| ssh | default: `gascity-remote-transport` `ssh`, so reads are local `ssh -T` pipes |
| ssh-da | as ssh, plus connection-local `tramp-direct-async-process t` for ssh:localhost |
| tramp | `gascity-remote-transport` `tramp` over tramp-sh (the fallback path) |
| tramp-da | `tramp` transport plus direct-async: **§8.4 mode 3** |
| mock | `/mock::` (tramp-tests' local-sh method): a non-ssh method, so reads use TRAMP `make-process` and live must poll |

`/sudo::` was not run: `sudo -n true` needs a password on this host. mock
stands in for it (also non-ssh, also an implicit host).

## Results

Ready time is from open until the store settled; "—" means never settled
within the wait.

| View | local | ssh | ssh-da | tramp | tramp-da | mock |
|---|---|---|---|---|---|---|
| cockpit | 2.7 s | 5.8 s | 6.8 s | — (89 s) | 7.5 s | 4.7 s |
| agents | 0.5 | 0.4 | 0.7 | 1.5 | 0.8 | 0.5 |
| agents tree | 0.1 | 0.8 | 2.2 | — | 2.5 | — (39 s) |
| agent detail | 1.2 | 1.2 | 1.1 | — | 1.5 | — |
| runs | 1.2 | 1.5 | 1.5 | — | 3.6 | — |
| run detail | 1.2 | 1.1 | 0.0 (shared) | — | 1.9 | — |
| health | 2.3 | 2.6 | 2.2 | — | 2.6 | — |
| cities | 3.0 | 6.2 | 3.9 | — | 4.8 | 13.3 |
| rig | 1.5 | 5.9 | 2.4 | — | 3.3 | — |
| mail | 0.7 | 0.9 | 1.3 | 1.2 | 1.1 | 4.5 |
| convoys | 2.3 | 2.3 | 2.7 | 2.5 | 5.4 | 2.2 |
| orders | 0.4 | 0.4 | 0.5 | – | 0.4 | 0.4 |
| dolt | 1.5 | 2.1 | 1.6 | – | 1.9 | 1.8 |
| sessions | 0.8 | 1.1 | 0.9 | – | 19.9 | 0.8 |
| contention, all refresh | 5.3 | 17.7 | 11.6 | – | 26.3 | 14.6 |
| max concurrent remote gc | n/a (local) | **3** | **3** | 3 | **3** | 4* |
| live stream | live, seq advances | live, seq advances | live, seq advances | – | live, seq advances | **broken** (below) |

`–` means not reached: the tramp run was stopped once the pattern was clear.
`*` means the mock count includes local helper processes (the counter
matches TRAMP processes by their `remote-command`), so it is not a clean
remote cap reading.

The renders are identical local vs remote in the modes that settle
(ssh, ssh-da, tramp-da). The diffs are live-data drift between runs 40 min
apart: status probe state, unread count, store size, activity.

Main-loop stalls over 200 ms, opening commands included:

- **ssh / ssh-da**:
  - cockpit 1.27 s, which is first contact. It is the TRAMP connection setup
    inside `city.toml` discovery (profiled: `file-exists-p city.toml` 1.04–1.26 s),
    a listed §8.5 exception.
  - Cities 0.57–0.66 s (bug B3).
  - Once, 0.22–0.34 s during the refresh-all.
  - Nothing else.
- **tramp-da**:
  - cockpit 1.5 s (first contact), Cities 0.64 s.
  - Twenty 0.2–0.64 s gaps while Sessions loads and during the refresh-all,
    all with 13 views alive. Session list opened alone makes no TRAMP call
    over 0.1 s, so these are concurrent TRAMP spawns and refresh ticks, not
    a Session list defect. This is the cost the ssh-pipe transport was built
    to avoid (§8.5).
- **tramp** (tramp-sh): 0.5–1.2 s blocked on almost every open (the
  synchronous remote-shell setup per `make-process`), plus the hangs from
  bug B1.

## Bugs

- **B1 (store, reported): a remote read's completion is lost for good.**
  - *Mechanism:* `gascity-store--start`'s `finish` cancels the job's deadline,
    then defers `gascity-store--complete` with `run-at-time 0`. TRAMP's
    `with-tramp-suspended-timers` (tramp.el:2286) let-binds `timer-list` to nil
    around `accept-process-output`. A sentinel that fires in that window puts
    its timer into the let-bound list, and the timer is dropped when the
    binding unwinds.
  - *Effect:* the entry stays pending forever; the deadline is already gone.
    Instrumented, `session list` shows `done=t result=:ok`, process exit 0, no
    `complete` call, and `:reads 0 :queued 0` for over 40 s.
  - *Where it hits:* every vui view in `tramp` and mock. The tabulated lists
    re-read on their own and survive.
  - *Repro:* deterministic, in batch, no ssh. Make the fake sentinel call
    inside `(let (timer-list timer-idle-list) …)`. The script is in the lead
    report; it works as an ERT test.
  - *Default mode:* any synchronous TRAMP operation (city discovery,
    find-executable, `find-file`, Cities' city-root probe) opens the same
    window. This is the likely explanation for an earlier one-off remote Runs
    load that stayed `…` (2026-09-25 Runs pass, "harness note").
- **B2 (live, reported): the non-ssh poll fallback never works on gc 1.4.2.**
  - *Poll rejected:* the poll runs `gc events --after SEQ`, and gc 1.4.2
    answers "`--after` requires `--follow` or `--watch`" with exit 1, so the
    stream goes `offline`. Verified by hand: `gc events --watch --after SEQ`
    replays the backlog and exits in about 1 s, or blocks until the next
    event.
  - *Status lookup misses:* the stream is keyed on the city root with TRAMP's
    default host filled in (`/mock:m1:/…`), but the views look it up under
    `/mock::/…`. `gascity-live-status` is therefore nil, and the header and
    lighter never show the state. `/sudo::` has an implicit host too.
- **B3 (reader/context, reported): Cities blocks 0.55–0.67 s on open over
  ssh.**
  - *Cause:* `gc cities` is read in `/ssh:host:/`. The reader's city args call
    `gascity-context-city-root` synchronously; its walk calls
    `abbreviate-file-name`, which triggers TRAMP's
    `file-name-case-insensitive-p` probe (a remote temp-file write, 0.53 s,
    profiled).
  - *Suggested fix:* no city args for `cities`, or cache negative city-root
    results per directory.
- **Minor:** opening Session list resolves `gc` on the host synchronously
  (`gascity-remote-find-executable`, 0.13–0.14 s, 4–5 `file-executable-p`
  probes). It is under budget, but it is a synchronous TRAMP round trip at
  open.

Nothing in the Runs / run detail code needed a fix: its failures in tramp and
mock are B1.

## Budgets (R9)

- **ssh, ssh-da:**
  - Concurrency cap met: 3 per host, plus the stream.
  - First paint on a warm connection ≤ 2.5 s for every view except the
    cockpit (5.8–6.8 s). The cockpit loads 7 reads plus per-rig fan-out
    under the cap of 3; its first 1.3 s is connection setup.
  - Main-loop stalls within 200 ms except first contact and B3.
- **tramp-da (mode 3):**
  - Correct: every view renders, cap 3, live streams.
  - Over the stall budget whenever several views are alive.
- **tramp, mock:** not usable until B1 is fixed.

## Re-run after B1, B2 and B3 (main 87612b4, 23:02–23:13)

Same driver and target, all six modes, per-view wait 60 s. Main now has
the B1 fix (deferred store work survives TRAMP's timer suspension), the
B2 fix (live poll and canonical keys), the B3 fix (Cities city-root
probe), the store latency and idle work, and the stderr leak fixes.

| View | local | ssh | ssh-da | tramp | tramp-da | mock |
|---|---|---|---|---|---|---|
| cockpit | 2.6 s | 4.7 s | 5.2 s | 17.1 s | 5.1 s | 4.2 s |
| agents | 0.4 | 0.5 | 0.8 | 3.0 | 0.8 | 0.5 |
| agents tree | 0.1 | 0.8 | 1.1 | 0.0 (cached) | 0.8 | 1.5 |
| agent detail | 1.1 | 1.1 | 1.4 | 3.0 ¹ | 1.1 | 1.5 |
| runs | 1.2 | 0.8 | 1.2 | 4.4 | 1.6 | 1.2 |
| run detail | 0.0 | 0.1 | 0.8 | 0.0 | 0.9 | 0.8 |
| health | 2.1 | 2.2 | 2.3 | 9.5 | 2.2 | 2.3 |
| cities | 3.2 | 4.1 | 3.4 | 6.6 | 3.3 | 3.4 |
| rig | 1.5 | 1.5 | 1.4 | 7.8 | 1.4 | 1.9 |
| mail | 0.8 | 1.4 | 1.1 | 1.6 | 1.1 | 1.1 |
| convoys | 1.7 | 1.9 | 2.6 | 2.6 | 2.9 | 3.1 |
| orders | 0.5 | 0.4 | 0.7 | 1.1 | 0.8 | 0.9 |
| dolt | 2.1 | 2.0 | 2.3 | 6.7 | 2.2 | 3.0 |
| sessions | 0.8 | 0.4 | 1.5 | 2.2 | 1.4 | 0.9 |
| contention, all refresh | 6.9 | 9.9 | 10.2 | 62.0 | 11.8 | 10.2 |
| max concurrent remote gc | n/a | 3 | 3 | 3 | 3 | 4 ² |
| live stream | live, seq +3 | live, seq +3 | live, seq +3 | live, seq +1 | live, seq +1 | **polling, seq +7 in 5 s** |
| stalls > 200 ms | none | cockpit 1.07 s | cockpit 1.24 s | many (below) | cockpit 1.27 s, one 0.93 s | cockpit 0.27 s |

¹ One read failed once under contention ("gc transcript: … Process has
died"). The agent detail rendered its other sections. Three follow-up
opens were clean.
² The mock counter also counts local helper processes; see above.

### Results

- **B1 fixed:** no view hangs at `…` in any mode. tramp and mock render
  every view, the Runs view and run detail included.
- **B2 fixed:** mock's live stream runs in `polling` state and advances
  (seq 85523 → 85530 in 5 s). `gascity-live-status` finds it under the
  view's directory, so the header shows it.
- **B3 fixed:** Cities opens in ≤ 0.02 s in every ssh mode; it was
  0.55–0.67 s before.
- **ssh, ssh-da, tramp-da:**
  - Every view renders the same as local; the only diffs are live data
    (store size, ages, counts).
  - At most 3 concurrent remote gc; live streams.
  - The only stall over the budget is the first-contact cockpit open
    (1.1–1.3 s, the §8.5 exception) and one 0.93 s gap during tramp-da's
    refresh-all.
- **mock** (non-ssh method, TRAMP `make-process`): now as good as ssh.
  One 0.27 s gap on first contact.
- **tramp (tramp-sh over ssh): correct, but not usable.**
  - Every view settles, but opening a list blocks 0.7–2.3 s.
  - Stalls of 0.6–4 s throughout, one of 45.6 s during the refresh-all,
    and the contention phase took 62 s to settle.
  - An instrumented re-run showed TRAMP's own channel dying ("Remote file
    error: Process has died"). The main loop is not wedged between these
    stalls.
  - This is F8 mechanism 1 (qa/f8-root-cause.md): each tramp-sh async
    read is an ssh mux client with a pty, and the ControlMaster blocks
    writing a full pty while TRAMP waits on another channel. mock (no ssh
    master) and direct-async (no pty) are unaffected.
  - Recommendation for the lead: `gascity-remote-transport 'tramp` over
    an ssh-family method should not be offered as is. Force direct-async
    or `tramp-use-connection-share 'suppress` for gascity's processes, or
    document that it is for non-ssh methods only.

### Fixed on this branch

- **Runs order:** two waiting runs with the same `created_at` (bl-0q8w,
  bl-70ac, both 2026-09-23T21:21:16Z) swapped order between runs, because
  the sort followed the order the stores answered in. Runs now break
  time ties by id.

### Budgets (R9), re-run

- **ssh, ssh-da, tramp-da, mock:**
  - Concurrency cap met.
  - Warm first paint ≤ 2.5 s for every view except the cockpit
    (4.2–5.2 s) and Cities (3.3–4.1 s). Those two read many entries under
    the cap of 3.
  - Stalls within 200 ms except first contact.
- **tramp over ssh:** fails the stall budget (F8, above).

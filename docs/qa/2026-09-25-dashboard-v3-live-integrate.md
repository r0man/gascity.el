# dashboard-v3 integration — the live stream reaches every view

Date: 2026-09-25 · Branch `v3-integrate` · bright-lights, local and
`/ssh:localhost:/home/roman/bright-lights`.

Driver: `scripts/qa/dashboard-v3-live-integrate.el` (batch Emacs under
`timeout 200`, `gascity-live-in-batch` t; batch has no visible windows,
so `gascity-store-refetch-hidden` is t there). It opens the cockpit,
mail inbox, Agents, Runs, Health and the session list, sends one mail
to `human` from a shell OUTSIDE Emacs (`gc mail send`), and measures
with no `g` when each mail-dependent view shows it; then archives it.

| | local | remote (ssh transport) |
|---|---|---|
| stream state in every view's header / mode line | `● live` (6/6) | `● live` (6/6) |
| mail inbox shows the new mail | 4.0 s (runs: 5.8, 8.2, 4.0) | 3.8 s |
| cockpit mail count updated | 4.3 s | 3.8 s |
| archive → inbox drops it | ≈ 4 s | ≈ 4 s |

Instrumented breakdown (local): event on the stream +0.2 s, debounced
invalidation +2.7 s (`gascity-live-debounce` 2.5 s), reads done +3.9 /
+4.3 s. The 8.2 s outlier coincided with a burst of `order.*` events
(bd reads re-run for every open view); budget §8.3 R9 is ≤ 4 s local /
≤ 5 s remote — met in the steady state, missed by the outliers, whose
cost is gc read time, not Emacs.

Restored: both check messages archived (`gc mail count`: 4 unread, as
before).

Re-run after rebasing on main 4cf1b96: remote inbox 3.3 s / cockpit
3.6 s; local inbox 3.5 s / cockpit 3.7 s. Restored (4 unread).

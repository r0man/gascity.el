# Improvement plan — gascity.el + beads.el

Run: dogfood 2026-10-15, city `/home/roman/bright-lights`, mode **rw**.
Workflow root `ga-9jqvo`, dogfood step `ga-c8p5a`, run epic `ga-jqt9q`,
gascity.el @ `origin/main` (2b2e19e). Session: implementation-worker-3.

This plan is the operator-requested consolidated answer to "how to improve both
gascity.el and beads.el", based on driving the real porcelain against the live
bright-lights city and the beads.el surfaces it delegates to.

Legend — Owner: `gascity.el` / `beads.el`. Size: **QW** quick win, **LG**
larger change. Status: **filed** (bead id) / **not filed**.

---

## A. gascity.el

### A1 — Store-health warning: doubled label + persistent list timeout
- **Severity:** P2 (user-visible, keeps the cockpit in "Needs you").
- **Owner:** gascity.el — Health view (`lisp/gascity-health.el`) and cockpit
  Needs-you row (`lisp/gascity-dashboard.el`); underlying timeout is gc
  (`counting retained bead rows` → `list timed out: context deadline exceeded`).
- **Size:** QW for the doubled prefix; LG/needs-investigation for the timeout.
- **Evidence:** Health renders
  `store health: store health: counting retained bead rows: hydrating list
  fallback: list timed out: context deadline exceeded`; cockpit truncates to
  `health: store health: counting retained bead ro…`. Recurred 13:06 and 13:21;
  `gc doctor` 102 passed / 9 warnings and `gc status` health lists only
  `agent_state_unknown`.
- **Fix:** the view prepends `"store health: "` to a message that already
  starts with that label — drop the prefix or strip it from the source string.
  Then investigate why the retained-row count probe times out under normal
  load (raise the internal deadline, or degrade to "not counted" rather than
  surfacing a warning).
- **Status:** **filed** `ga-jqt9q.1`.

### A2 — Runs view lumps `waiting` runs under "Active"
- **Severity:** P3 (misreads stale work as live).
- **Owner:** gascity.el — `M-x gascity-runs` (`lisp/gascity-runs.el`).
- **Size:** QW (grouping/labels) or LG (staleness heuristics).
- **Evidence:** summary `1 active · 7 waiting` but section header `Active 8`;
  six runs `waiting` since Sep 23–27 sit beside live runs. New run `hw-yz8c`
  shows `no live worker`.
- **Fix:** split the section into `Active` / `Waiting`, or mark stale rows
  (age > N) and make the header match the summary counts.
- **Status:** **filed** `ga-jqt9q.2`.

### A3 — Costs view prints unexplained `EST_USD 0.0000`
- **Severity:** P3 (misleading).
- **Owner:** gascity.el — `M-x gascity-costs` (`j $`).
- **Size:** QW.
- **Evidence:** rows with `INVOCATIONS 0`, `EST_USD 0.0000`, `UNPRICED 0` but
  `WALL_S` up to 46490. `GC_DISABLE_USAGE_METRICS=1` was inherited in this
  session; a user cannot tell zero-cost from missing-data.
- **Fix:** annotate zero rows (`no usage recorded` / `metrics disabled`) or
  show a banner when usage metrics are off, instead of printing `0.0000`.
- **Status:** **filed** `ga-jqt9q.3`.

### A4 — Cockpit "Rigs" section omits the HQ city rig
- **Severity:** P4 (count disagrees with the rig list).
- **Owner:** gascity.el — cockpit Rigs section (`lisp/gascity-dashboard.el`).
- **Size:** QW.
- **Evidence:** cockpit `Rigs 1` (hello-world only) vs `M-x gascity-rig-list`
  showing bright-lights + hello-world.
- **Fix:** include the HQ rig, or label the section `Rigs (non-HQ)` so the
  count is not read as total rigs.
- **Status:** **filed** `ga-jqt9q.4`.

### A5 — View-open city resolution is silent when the current buffer is not in a city
- **Severity:** P3 (wrong-city data, no warning). *Harness-triggered here.*
- **Owner:** gascity.el — `gascity-context` / every `gascity-*-show-buffer`.
- **Size:** LG.
- **Evidence:** invoking `(gascity-runs)` / `(gascity-events)` with the
  selected buffer at a non-city `default-directory` (the worktree) silently
  showed **emacs-city** runs/events while the cockpit showed bright-lights.
  Only after pinning `default-directory` to the city did the views scope
  correctly. A user running `M-x gascity-runs` from an unrelated buffer hits
  the same ambiguity.
- **Fix:** when a view's buffer is not under a known city, either prompt for
  the city or refuse with a message; never resolve through `default-directory`
  alone. Consider showing the resolved city more prominently in the header.
- **Status:** **not filed** (caused here by non-interactive invocation; worth a
  follow-up once reproduced from a real buffer).

### A6 — Non-interactive invocation of prompting commands wedges the server
- **Severity:** P4 (diagnostic hazard, not a user path).
- **Owner:** gascity.el (`j b` → `gascity-jump-beads` prompts "Beads for:"
  when there is no rig at point).
- **Size:** QW (document/test-harness guidance).
- **Evidence:** `(gascity-jump-beads)` via `emacsclient -e` left Emacs blocked
  at the "Beads for:" minibuffer prompt; had to send `C-g` twice to recover.
  This matches the harness's own warning about blocking evals, not a product
  defect.
- **Fix:** none required in the product; keep the e2e harness on tmux
  keystrokes for prompting commands, and/or add a batch-mode guard.
- **Status:** **not filed**.

---

## B. beads.el

The delegated surfaces exercised from gascity.el all worked and were correctly
scoped by binding `default-directory` to the owning rig's repo (per
DESIGN.md §4.3):

- `gascity-rig-beads "hello-world"` → `*beads-dashboard<hello-world>*`,
  correctly scoped (Open 9 / Ready 8 / In-progress 1 / Blocked 1 / Closed 191),
  showing the freshly-slung bead `hw-yz8c` under In progress.

### B1 — Beads dashboard gives no explicit city/rig breadcrumb beyond the rig name
- **Severity:** P4.
- **Owner:** beads.el (`beads-dashboard`; `lisp/beads-dashboard.el`).
- **Size:** QW.
- **Evidence:** the header is `Beads-Dashboard — hello-world`; the owning city
  is not named, so when several cities carry a same-named rig the target is
  ambiguous.
- **Fix:** include the city (or the resolved store path) in the dashboard
  header.
- **Status:** **not filed** (low confidence from a single observation; needs a
  multi-city same-rig repro).

No beads.el *defect* was reproduced this run. The gascity→beads scoping
contract held; the plan's beads.el contribution is therefore deliberately
small, and B1 should be validated on a second observation before filing.

---

## Not filed (summary)
- A5 view-open city resolution (harness-triggered) — follow up from a real buffer.
- A6 non-interactive prompt blocking — harness guidance, not product.
- B1 beads dashboard breadcrumb — single observation, low confidence.
- Harness artifact: the dogfood Emacs inherited the worker's `GC_DISABLE_USAGE_METRICS=1`
  (and `GC_PROVIDER`/`GC_SESSION_*`); it may have zeroed the Costs view. Future
  runs should launch the Emacs with a clean environment for cost/attribution
  observations.
- Bright-lights data state (not product): six `waiting` runs since Sep 23–27;
  `order-tracking-sweep` failure 12:45; heavy order churn.

## Filing cap
4 of a permitted 8 issues filed. Remaining observations are recorded above.

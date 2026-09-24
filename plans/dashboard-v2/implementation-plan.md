---
schema: gc.build.plan.v1
workflow:
  id: ga-uxhh
  formula: build-basic
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: build-basic
  stage: plan
  attempt: 1
status: approved
trace:
  upstream:
    - path: plans/dashboard-v2/requirements.md
      hash: sha256:912141fa0e63c3d5615b7131e0bcb54e832776f594f7778afd17632217259a07
      ids:
        - ga-7pq7
    - path: lisp/gascity-dashboard.el
      hash: git:5ae47af99a60b29267eab5d4a034248a44922371
  coverage:
    - id: ga-7pq7
      status: covered
      rationale: >-
        The plan's proposed implementation covers every behavior and
        acceptance criterion of the Dashboard v2 target bead: runs view,
        run detail, convoy join, events activity feed, mail header, honest
        needs-you, costs dim pointer, TRAMP parity, and gate coverage.
---

# Implementation Plan — Dashboard v2 (runs, honest needs-you, activity, mail)

## Summary

Implement **Dashboard v2** in `lisp/gascity-dashboard.el` (plus tests in
`lisp/test/gascity-test.el`): a runs view built from workflow beads
(`gc bd list --json`, client-side grouping on `gc.graphv2_root_key`), a
run-detail drill-in of the step graph, a real Activity section fed by
`gc events --since` JSONL, a mail-unread cockpit header from
`gc mail count --json` with an `m` key into the existing mail reader, an
honest needs-you selector (delete the dead `awaiting-input` arm), and a
costs dim pointer. The data plane stays `gc`/`bd` CLI only — zero HTTP, all
reads through the existing per-section async plumbing
(`vui-use-async` / `gascity-reader-read-async`), stale-while-revalidate,
magit-grade inline errors, TRAMP-safe through the reader layer. `RET`
semantics stay "drill in / toggle"; new drill-ins reuse
`gascity-view-get-buffer-create`.

Work is split into five steps (S1–S5) sized for one session each; S1–S4 are
independently mergeable behind a green `scripts/gate.sh`, S5 closes with the
e2e pass and the delivery report. The steps are execution guidance only —
every acceptance criterion is verified once, at S5, against the live city.

## Current System

- The city dashboard (`gascity-city-dashboard-mode`, root component
  `gascity-dashboard-app` at `lisp/gascity-dashboard.el`, landed on `main`
  at `bbd6091..5ae47af`) renders: cockpit, Work in flight, Needs you,
  Agents, Sessions, Beads (+Convoys), an **Activity pointer stub**, and
  Rigs. Each section is backed by an independent
  `gascity-reader-read-async` read in the root component's render; loads go
  through `gascity-dashboard--effective-load` for stale-while-revalidate;
  collapse state and the `/` bead filter are lifted to the root component.
- The Activity section is a placeholder: it renders
  `gascity-status--events-pointer-vnode` because `gc event` had no JSON
  support at the time (documented gap ga-69kj, REQ-008 of the previous
  dashboard work). The new CLI surface `gc events --since <window>` emits
  JSON Lines (verified live: `{"actor","payload","seq","subject","ts",
  "type","ok"}` per line), so a real feed is now possible.
- The needs-you selector (`gascity-dashboard--needs-you-reason` et al.)
  ports the SPA's precedence `awaiting-input > errored > rate-limited >
  stalled`, but `pending` is hardcoded `nil` at the call site
  (`(pending nil) ; gc exposes no pending-interaction read yet`), so the
  `awaiting-input` arm and its prompt rendering
  (`gascity-dashboard--prompt-line`, the `"respond"` action mapping) are
  dead code that can never fire.
- No runs view exists. Workflow runs are invisible; the only structure is
  the flat ready/in-progress/blocked bead lists. Verified live in
  `emacs-city`: `gc bd list --json` carries `gc.graphv2_root_key`,
  `gc.formula_name`, `gc.formula_contract: graph.v2`, and
  `gc.input_convoy_id` in bead metadata; `gc convoy list --json` rows
  carry `progress: {closed,total}`; `gc convoy status <id> --json` exposes
  tracked-bead children.
- `gc mail count --json` works (live: `{"ok":true,...,"total":N,
  "unread":N}`); the mail inbox (`gascity-mail-inbox`, bound in
  `gascity-mode-map` as `m`) is a `tabulated-list` view in
  `gascity-tabulated.el`. `gc costs --json` returns
  `{"ok":false,"error":{"code":"json_unsupported",...}}`; `gc usage` does
  not exist — no costs JSON surface.
- `gascity-reader.el` is the single gc call site: sync `-read` and async
  `-read-async` (`make-process`, one callback per payload). There is no
  JSONL reader today; the reader's streaming plumbing (used by peek/attach)
  is the closest prior art for line-oriented output.
- Testing is one ERT file (`lisp/test/gascity-test.el`, 380+ tests) with
  `cl-letf` stubs on `gascity-reader-read` / `gascity-reader-read-async`;
  the gate is `scripts/gate.sh` (byte-compile with `--warnings-as-errors`
  + full suite). Dashboard selectors are pure functions tested by feeding
  fixture payloads.

## Proposed Implementation

New pure selectors and async section loads extend the existing root
component; no architecture change. Five steps, each ending with
`scripts/gate.sh` green and a commit.

### S1 — Runs section (list + selectors)

1. **Workflow-run discovery.** One new async read in
   `gascity-dashboard-app`: `gascity-reader-read-async '("bd" "list")`
   (full list; stores are small, per the requirements' rationale). New
   pure selector `gascity-dashboard--workflow-runs` groups raw bead alists
   into run rows:
   - A bead is a **run root** when its metadata carries
     `gc.graphv2_root_key` and it has no `gc.logical_bead_id`/step
     metadata (root vs step discrimination is: root beads TRACK steps;
     verified live, roots carry `gc.kind: workflow` — prefer
     `gc.kind == "workflow"`, fall back to lacking `gc.ralph_step_id`).
   - A bead is a **step** when it carries the same root key and
     `gc.ralph_step_id` (or `gc.step_id`). Group steps under their root.
   - Per-run row: run id (bead id), formula (`gc.formula_name`), phase
     (root bead status), progress `closed/total` (count steps by status),
     current step (first non-closed step having a non-empty `assignee`),
     updated (root `updated_at`).
   - Exclude closed runs from the default view (dim "N closed runs" line
     when any exist — the requirements leave this latitude to the plan).
2. **Rendering.** Replace "Work in flight"'s role or extend it: keep
   "Work in flight" (it shows live bead×session joins, which runs do not),
   and add a **Runs** section above it. Rows rendered dim/`vui-text`
   style consistent with other sections; the run row is stamped so
   `gascity-section` navigation and `RET` land on it.
3. **RET drill-in (S2** below renders it**):** stamp the run row with the
   root bead id; `gascity-dashboard-activate` dispatches on that property
   to open the run-detail buffer.
4. **Tests.** ERT fixtures: root-vs-step discrimination, grouping,
   progress fraction, current-step pick, closed-run exclusion.

### S2 — Run detail (step graph + input convoy)

1. New command `gascity-run-show` (run root bead id, or called at-point
   from the Runs section): buffer via `gascity-view-get-buffer-create`
   (base name `*gascity-run*`), mode deriving `gascity-section-mode`.
2. Data: reuse the `bd list` payload already loaded by S1 where possible;
   run-detail opens with its **own** async read of `bd list` filtered
   client-side to the run (one read, independent load, per-section
   failure rule). Join the input convoy from the already-loaded
   `convoy list` payload via `gc.input_convoy_id` (fallback: its own
   `gc convoy status <id> --json` read when opened outside the dashboard).
3. Rendering: a section per step — step id, title, kind (`gc.kind` /
   `gc.control_for`), status, assignee — in dependency order as returned
   by the payload; header shows phase, progress `closed/total`, formula;
   a dim convoy row when an input convoy exists (id, title, status,
   progress). `g` refreshes; `q` buries.
4. Tests: step-graph rendering fixtures; convoy join present/absent;
   failure surfaces as the standard inline error vnode.

### S3 — Activity feed (events JSONL)

1. **Reader JSONL support.** Add a JSONL variant next to
   `gascity-reader-read-async` (e.g. `gascity-reader-read-async-lines` or
   an option on the existing function): accumulate process output,
   split lines, decode each line as JSON, deliver a list of decoded alists.
   Per the requirements, a malformed line becomes a decode-error marker,
   not a whole-feed failure — the delivered payload carries
   `(good . bad)` where `bad` counts (or carries the raw line of) the
   undecodable lines.
2. **Async section load.** In `gascity-dashboard-app`:
   `gascity-reader-read-async '("events" "--since" "2h")` via the JSONL
   path. Cap at the most recent N events client-side (N=500 default,
   `defcustom gascity-dashboard-events-limit`).
3. **Filter.** New state variable on the root component
   (`event-types-excluded`, default
   `("order.fired" "order.completed" "bead.updated")`), applied before
   render; extend the `/` transient (`gascity-dashboard-filter-dispatch`)
   with an events submenu (toggle default-chatty, clear). Filter state is
   lifted to the root so it survives refresh, like `bead-rig`.
4. **Rendering.** Replace the Activity pointer stub with the feed:
   rows of ts (HH:MM:SS), type, subject, first line of a summary (from
   `payload.title`/`payload.summary` when present, else subject-only);
   a trailing dim line "N older events hidden" when capped. A JSONL
   decode error renders a dim inline line (never blank); an events read
   failure renders the standard dim error line with retry hint.
5. **Tests.** Fixtures: JSONL decode (good/bad split), chatty-type
   exclusion default, filter toggling, N-cap trimming, ts formatting.

### S4 — Mail header + honest needs-you + costs pointer

1. **Mail.** New async read `gascity-reader-read-async
   '("mail" "count")` in the root component; the cockpit vnode renders
   "mail N unread" (dim when zero) from the `unread` field; new key `m`
   in `gascity-city-dashboard-mode-map` → `gascity-mail-inbox` (existing
   command; `default-directory` is pinned to the city by
   `gascity-view-get-buffer-create`, so the reader scopes correctly).
2. **Honest needs-you.** Delete from
   `gascity-dashboard--needs-you-reason`, `--needs-you-detail`,
   `--needs-you-actions` and their helpers/tests:
   the `awaiting-input` precedence arm, the prompt-line helper, and the
   `respond` action mapping. Update the file's header comment and the
   mode docstring: "Pending interactions need the supervisor API; out of
   scope by user directive." `errored`/`rate-limited`/`stalled` stay,
   still derived purely from `gc status` + `gc session list --json`.
   No fake data, no dead paths.
3. **Costs.** In the cockpit vnode, after the mail segment, a dim pointer
   row: "costs — run `gc costs` in a shell; no JSON surface". File the
   capability-request bead (see S5) — do not implement the CLI side here.
4. **Tests.** Mail header fixture (unread > 0 / 0); needs-you selector
   fixtures updated to prove `awaiting-input` can no longer be produced;
   costs pointer renders exactly one dim row.

### S5 — Verification, e2e, capability bead, report

1. **Static gates.** Whole-package byte-compile with
   `--warnings-as-errors`; `rg -in "url\\|http" lisp/gascity-dashboard.el
   lisp/gascity-reader.el` over the diff — nothing that calls the
   supervisor API; no synchronous `gc` added in render/eldoc/prefix paths.
2. **ERT.** All new selectors covered (S1–S4 lists); full suite green.
3. **TRAMP parity.** Manual pass over
   `/ssh:localhost:/home/roman/bright-lights`: runs, run detail, activity,
   mail header, needs-you, costs pointer — identical data and behavior,
   no TRAMP sync stalls.
4. **Interactive e2e (acceptance gate).** Per AGENTS.md: fresh Emacs in
   tmux (`scripts/e2e-harness.sh` helpers, timeouts everywhere), connect
   to the bright-lights city over TRAMP, exercise the real flow — open
   dashboard, drill into the live build-basic run, watch activity, jump
   to mail. Record the pass in `docs/qa/` (dogfood report).
5. **Capability bead.** File one bead requesting a costs JSON surface
   (referencing the `json_unsupported` error) and, if not already covered
   by the requirements' gap notes, one for pending interactions.
6. **Delivery report.** Short markdown report (artifact root):
   sections added, exact CLI recipes used, the two documented CLI gaps
   with their dim-pointer treatment. Update the footer legend + header
   line to document all new keys/sections (`m`, Runs, Activity).

## Non-Goals

- Any supervisor HTTP API call (REST `/runs`, `/session/{id}/pending`,
  readiness/waits) — user directive; the data plane is the `gc` CLI.
- Usage/cost panels from CLI data: `gc costs --json` is
  `json_unsupported`; dim pointer only, capability bead instead.
- A transcript pane; tmux attach via `t` remains the answer (regression
  covered by existing tests; no new pane).
- Implementing the missing CLI capabilities in gc (file request beads).
- Changes to the Go web dashboard repo (`~/workspace/gascity` — READ-ONLY
  for this workflow).
- Upstream PRs; work lands as local commits on `main`.
- Changes outside `lisp/gascity-dashboard.el`, `lisp/gascity-reader.el`
  (JSONL plumbing only), `lisp/test/gascity-test.el`, `docs/qa/`, and the
  artifact root — no core-domain or tabulated changes except where a
  drill-in reuses an existing command unchanged.

## Verification

- **Unit/ERT (each of S1–S4, whole gate at S5):** `scripts/gate.sh` —
  byte-compile `--warnings-as-errors` (catches cross-file wiring) + full
  ERT suite including new fixtures for: workflow-run grouping (root key,
  root-vs-step, progress fraction, current step), events JSONL decode
  (good/bad split, chatty-type filter, N cap), mail-count header,
  needs-you honesty (no `awaiting-input` path), run-detail rendering and
  convoy join.
- **Live city spot checks (S5):** against `emacs-city` — Runs section
  shows the real build-basic run with a correct progress fraction; `RET`
  opens the step graph; activity renders non-chatty events; mail header
  matches `gc mail count --json`.
- **TRAMP (S5):** the same checks on
  `/ssh:localhost:/home/roman/bright-lights`, plus the tmux-Emacs e2e
  pass recorded under `docs/qa/`.
- **Honesty greps (S5):** no `awaiting-input`/`respond` symbols remain;
  no `url`-/`http`-based calls; the costs pointer string exists.

## Coverage Matrix

| ID | Status |
| --- | --- |
| ga-7pq7 | covered |

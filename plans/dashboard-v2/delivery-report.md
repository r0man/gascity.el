# Delivery Report — Dashboard v2 (ga-7pq7 / plans/dashboard-v2)

Date: 2026-09-24 · Workflow root `ga-uxhh` (build-basic) · Item `ga-gmbh` (S5)

## Sections added (all in `lisp/gascity-dashboard.el`, `lisp/gascity-run.el`, `lisp/gascity-reader.el` + tests)

| Section / view | Read (exact CLI recipe) | Notes |
| --- | --- | --- |
| Runs | `gc bd list --status open,in_progress,blocked,deferred,closed --rig <each rig>` per `gc rig list`, plus `gc bd list --status in_progress --rig <each rig>` and `gc bd list --status blocked --rig <each rig>` for the other censuses | Rig fan-out (`--bd-list-rigs-async`): one `rig list` read, one `bd list` per rig store, rows stamped with the owning store; progress fractions count closed steps |
| Run detail (`RET` on a run row) | `gc bd list --status open,in_progress,blocked,deferred,closed --rig <owning rig>` + `gc convoy status <input_convoy_id>` | Step graph (id/title/kind/status/assignee), progress closed/total, dim input-convoy row; affected-list fallback with rig stamps when opened without a rig |
| Activity | `gc events --since 2h` (JSONL) | ts/type/subject/summary rows; chatty types (`order.fired`, `order.completed`, `bead.updated`) excluded by default via the state-variable filter (`e`, or `/` → "Events…"); malformed lines render as a dim count, never a blank section |
| Cockpit mail header | `gc mail count` | "mail N unread"; `m` opens the existing mail inbox scoped to the city |
| Costs pointer | — | dim row: "costs — run `gc costs` in a shell; no JSON surface" (capability bead `ga-ik26`) |
| Honest needs-you | `gc status` + `gc session list` (existing reads) | `awaiting-input` selector arm, prompt rendering and the `respond` action deleted; `errored`/`rate-limited`/`stalled` all derivable (capability bead `ga-jcv1`) |

Footer legend + header line document every new key: `m` mail, `e` events
filter, Runs section, `N/P` section jumps.

## Documented CLI gaps and their dim-pointer treatment

1. **Costs**: `gc costs --json` returns
   `{"ok":false,"error":{"code":"json_unsupported",…}}` (verified live in
   emacs-city) and `gc usage` does not exist → the cockpit renders exactly
   one dim pointer row instead of a panel; capability bead `ga-ik26` requests
   the JSON surface.
2. **Pending interactions**: `gc status --json` and
   `gc session list --json` expose no pending/awaiting-input field (the data
   lives only behind the supervisor REST API, which gascity.el must not call
   by user directive) → the `awaiting-input` code path was deleted, not
   faked; capability bead `ga-jcv1` requests a JSON surface.

## Known caveats

- The **Beads → Ready** census still reads the city HQ store's `bd ready`
  (pre-existing read, capped at 100 by gc); the in-progress/blocked groups
  and the Runs census fan out over rig stores. A ready-census fan-out is a
  natural follow-up if the city-store bias matters.
- `gc bd list` cannot aggregate across rigs — the rig fan-out is the
  porcelain-side treatment; an aggregate `--rig all` would remove the extra
  reads (candidate for the gc CLI, same family as the two capability beads).

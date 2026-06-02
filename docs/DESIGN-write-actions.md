# gascity.el — Write / Action Commands Design

*Phase “WRITE” of the porcelain: interactive, magit/forge-style mutate
commands driven off the existing `gascity-command` classes.*

Status: **design** (no implementation). Companion to [`DESIGN.md`](DESIGN.md);
this elaborates the write surface beyond the P1 dispatch already shipped
(DESIGN.md §7 “P1 — Command dispatch”). Tracked by the epic this document
seeds (see §12).

Bead: `gce-p7t`.

---

## 1. Scope — what exists, what this adds

The read-only porcelain and a **first slice of mutating commands** already
ship (DESIGN.md §7 P1). The existing write layer (`gascity-action.el` +
the `gascity-command-action` classes in `gascity-types.el`) covers:

| Domain | Already implemented (P1) |
|---|---|
| Rig | suspend · resume · restart |
| Session | nudge · suspend · kill · wake · drain · peek (read-only) |
| Dispatch | sling (target + bead/text; models `--formula`/`--nudge`/`--dry-run`) |
| Order | run |
| City | start · stop |

This design specifies the **delta** — the rest of the write surface the
bead asks for, grouped by the context it acts from:

| Context | New actions this design covers |
|---|---|
| **Bead** | sling/route (richer) · close (`--reason`) · note · update (status/priority/assignee/deps) · create · reopen |
| **Agent / session** | reset · undrain · (phase 3) rename · close · pin/unpin · prune |
| **City / rig** | reload (`gc reload`, city-level) · rig add/remove · (refresh/resume/suspend already done) |
| **Mail** | read · archive · mark-read/unread · reply · send |

It also defines the **two new primitives** the delta needs that P1 did not:
a bead-write command base that routes by store (§3.2), and a lightweight
**compose buffer** for multi-line bodies (mail, bead description) (§6).

### 1.1 Non-goals / corrections to the brief

Research against the live `gc` (`2026-06-02`) corrected two items in the
brief; the design reflects the CLI as it actually is:

- **“reset” is a *session* command, not a rig one.** `gc session reset`
  (“Restart a session fresh while preserving the bead”) is distinct from
  `gc session kill` (force-kill, reconciler restarts) and from `gc rig
  restart`. It belongs in the **agent/session** context.
- **“reload” is *city*-level, not rig-level.** `gc rig` has **no**
  `reload` subcommand (only add/list/remove/restart/resume/set-endpoint/
  status/suspend). Config reload is `gc reload` (“re-read effective config,
  process one reload tick”, with `--soft` to absorb drift without draining
  sessions). It belongs on the **status dashboard** (city scope), not the
  rig dashboard.

Two further non-goals, inherited from DESIGN.md §4.3:

- **We do not reimplement beads.el’s bead editor.** Deep bead authoring
  (full description/design/acceptance bodies, dependency-graph editing)
  stays in beads.el; `RET` on a bead reference opens beads.el’s detail
  view, scoped to the owning store. gascity owns only *targeted command
  dispatch* on a bead (§4).
- **We do not auto-generate the UI.** Per DESIGN.md’s binding UI direction,
  every surface here is hand-built. beads-meta generates a transient only
  where we explicitly want one as an **arg-collection backend** (the sling
  flag popup, §5).

---

## 2. Principles

1. **Reuse the P1 spine.** Every new mutation is a `gascity-command-action`
   subclass (or a close sibling, §3.2) executed through the existing
   `gascity-command-act` → echo-summary → `gascity--refresh-current-view`
   path (`gascity-action.el:68`, `:166`). No parallel execution machinery.
2. **The porcelain is human-operated.** It is used by the operator, not by
   polecats. The polecat-only prohibition *“never close beads”* does **not**
   constrain this UI — the human may close, reopen, and edit beads. (The
   prohibition lives in agent prompts, not in gascity.)
3. **Mutations are explicit and reversible-aware.** Destructive or
   far-reaching actions confirm (y/n) or offer dry-run; safe additive
   actions (note, mark-read, refresh) run immediately. §8.
4. **One read path, one write path.** Reads go through `gascity-reader`
   (DESIGN.md §3); writes go through `gascity-command-execute` →
   `gascity-command-act`. Bead writes additionally pin the store with
   `-C`/`--directory` (§3.2) the same way bead *reads* already do
   (`gascity-beads--show-in-store`, the gce-bhr fix).
5. **Keys are consistent with what shipped.** `g` refresh, `RET` drill-in /
   primary, `q` bury everywhere; the new action keys slot into the gaps
   without shadowing those (§10).

---

## 3. Command-class layer

### 3.1 The base already fits most actions

`gascity-command-action` (`gascity-command.el:140`) is exactly right for
exit-status mutations: `--json` defaults **off**, success is read from the
exit code, and `gascity-action.el` specializes
`gascity-command-execute-interactive` on it to run synchronously and report
via `gascity-command-act`. Most new commands are one more class in
`gascity-types.el` plus a `gascity-command-validate` method for required
positionals — no new infrastructure:

```elisp
;; e.g. session reset — mirrors the existing session-kill class exactly
(gascity-defcommand gascity-command-session-reset (gascity-command-action)
  ((target :initarg :target :type string :initform "" :positional 1
           :documentation "Session id or alias to restart fresh."))
  :documentation "Restart a session fresh while preserving its bead.")

(cl-defmethod gascity-command-validate ((command gascity-command-session-reset))
  (and (gascity-command--blank-p command 'target) "a session target is required"))
```

The same shape covers: `runtime-undrain`, `mail-read`, `mail-archive`,
`mail-mark-read`, `mail-mark-unread`, `reload`, and the bead verbs that
take no captured payload (`bd close`, `bd note`, `bd priority`, `bd
assign`, `bd reopen`).

### 3.2 Two small extensions

**(a) Bead-write store routing — a `directory` slot.** Bead mutations run
`gc bd <verb> <id>`. The shared Dolt server can resolve a working directory
to a *different* rig’s database than its `.beads/` config names — the exact
gce-bhr failure that `gascity-beads--show-in-store` (`gascity-section.el:258`)
already fixes for reads by forcing `bd --directory` (`-C`). Bead writes
inherit the same hazard, so the bead-action base declares an optional
`directory` slot mapped to `-C`, populated from the bead id’s prefix via the
**existing** `gascity-beads--bead-path` (`gascity-section.el:247`):

```elisp
(defclass gascity-command-bd-action (gascity-command-action)
  ((directory :initarg :directory :initform nil
              :long-option "directory" :short-option "C" :option-type :string
              :documentation "Store dir (-C) resolved from the bead id prefix;
pins the write to the right rig's database despite shared-server misrouting."))
  :abstract t
  :documentation "Base for `gc bd' mutations. Concrete verbs add positionals.")
```

Callers resolve it once: `(gascity-beads--bead-path id)` → the store dir →
`:directory`. This reuses the prefix→path map already proven on the read
side; nothing new is invented.

**(b) Payload-returning actions — flip `--json` on, teach the summary.**
A few mutations return a small object worth surfacing: `gc bd create`
yields the new id, `gc mail send`/`reply` yield the message. For these the
class sets `json t` (overriding the action default) so
`gascity-command-parse` decodes it, and `gascity-action--summarize`
(`gascity-action.el:57`) gains two clauses — recognise `id`/`issue` (echo
“created gce-123”) and `message_id` (echo “sent”). That is a 4-line
addition to one helper, not a new class hierarchy.

### 3.3 Refresh coverage gap

`gascity--refresh-current-view` (`gascity-action.el:166`) dispatches on the
current major mode but omits **mail inbox** and **convoy list**. Add the two
missing clauses (`gascity-mail-inbox-mode` → `gascity-mail-inbox-refresh`,
`gascity-convoy-list-mode` → `gascity-convoy-list-refresh`) so mail/convoy
mutations refresh in place like every other list.

---

## 4. The bead-action boundary (key decision)

The brief asks for bead create/update/close/note *in the porcelain*, yet
DESIGN.md §4.3 binds us to **delegate bead UI to beads.el**. These reconcile
along a clean seam:

> **gascity owns *command dispatch on a bead*; beads.el owns *bead
> browsing and authoring*.**

- **gascity (gc-specific, not in beads.el):** `sling`/route (`gc.routed_to`),
  `assign` to an agent/refinery. These are Gas-City routing verbs with no
  beads.el equivalent.
- **gascity (quick at-point convenience, via `gc bd`):** `close --reason`,
  `note`, `priority`, `set-status`, `reopen`. Justification: the operator is
  already looking at a bead **reference** in a gascity view (a polecat’s
  on-hook bead, a rig’s ready/in-progress list, recent history) and wants a
  one-key action without a context switch. Each is a single `gc bd <verb>
  <id>` routed by prefix (§3.2) — a thin dispatch, not a re-rendering of the
  bead.
- **beads.el (unchanged):** `RET` on any bead reference opens beads.el’s
  detail/board for full reading and rich editing (multi-field create,
  dependency graph). gascity does not duplicate it. A gascity “create”
  offers only **quick-capture** (title/type/priority/assignee via
  `gc bd create`); elaboration happens in beads.el on the returned id.

This keeps the §4.3 contract intact (gascity never *renders* beads) while
delivering the requested write verbs as what they naturally are —
keyboard-first dispatch on the bead under point.

---

## 5. UX — dispatch and confirmation

The brief leaves two UX choices to justify.

### 5.1 Dispatch: direct keys + hand-built sub-transients (keep the P1 model)

P1 established the pattern and we extend it rather than replace it:

- **Direct single keys** for the highest-frequency at-point actions, bound
  in each view’s keymap (as `N`/`s`/`K`/`w`/`D`/`p` already are).
- **Hand-built sub-transients** group the rest and self-document, exactly
  like the existing `gascity-rig-dispatch` / `gascity-session-dispatch` /
  `gascity-lifecycle-dispatch` (`gascity-action.el:403`). New ones:
  `gascity-bead-dispatch`, `gascity-mail-dispatch`, plus a richer
  `gascity-sling-dispatch`. Each view binds the relevant dispatcher to one
  key (so the menu is reachable in-context); the main `gascity` transient
  also lists them.

Why not auto-generated transients-as-UI: DESIGN.md’s binding direction. Why
not a single mega-popup: per-context dispatchers keep menus short and
scoped to what’s under point.

### 5.2 Confirmation: y/n for single-arg mutations, a transient only where
flags exist

- **Keep `gascity-action--confirm` (`yes-or-no-p`)** for destructive
  single-shot verbs (close, kill, reset, archive, remove, stop). It is the
  P1 convention, needs no buffer, and reads cleanly in the echo area.
- **Argument collection stays in the minibuffer** (`completing-read` over
  live `gc` data for targets/rigs/orders; `read-string` for a reason or a
  one-line note) — the existing `gascity-action--read-*` helpers
  (`gascity-action.el:134`) already do this and extend trivially
  (`--read-bead`, `--read-message`).
- **A transient is used only for genuinely multi-flag commands** — `sling`
  (`--formula` · `--merge {direct,mr,local}` · `--no-convoy` · `--reassign`
  · `--dry-run` · `--var k=v` · `--title`). Here infixes are the right tool,
  beads-meta can generate the popup from the slot metadata
  (`gascity-defcommand … :global-section`), and **`--dry-run` doubles as the
  preview** the brief asks for: run with `-n`, show gc’s plan, then re-run
  for real. This folds in DESIGN.md §11 deferred items #8 (richer sling)
  and #9 (`order run --rig`).
- **Multi-line bodies** (mail send/reply, bead description) use the compose
  buffer (§6), finalized with `C-c C-c` — no confirmation needed beyond the
  deliberate finalize keystroke.

So: minibuffer + y/n for the many small mutations; a transient for the one
flag-heavy command; a compose buffer for the two body-bearing ones. Each
tool where it pays for itself.

---

## 6. New primitive — `gascity-compose-mode`

Mail send/reply and bead description are multi-line; a minibuffer is wrong
for them. Add one small buffer mode, modeled on `git-commit`/`log-edit`:

- `gascity-compose-mode` derives from `text-mode`; the buffer opens with a
  read-only header (recipient + subject for mail; bead id + field for
  beads) and a body area.
- `C-c C-c` (`gascity-compose-finish`) runs a caller-supplied closure with
  the body text (which builds and `gascity-command-act`s the command), then
  buries the buffer and refreshes the originating view.
- `C-c C-k` (`gascity-compose-abort`) discards.
- Subject/recipient for mail are read in the minibuffer *before* opening the
  buffer (or edited in header fields); the body is the buffer.

This is the only genuinely new UI surface; everything else is keymap entries
and command classes. ~40 lines, in a new `gascity-compose.el`.

---

## 7. Per-context action catalog

`act` = quick `gc … --json`-off mutation via `gascity-command-act`;
`json` = payload parsed then summarized (§3.2b); `compose` = §6 buffer;
`transient` = §5.2 flag popup. “Confirm” column: `y/n` = `yes-or-no-p`;
`—` = runs immediately; `dry-run` = preview-then-commit available.

### 7.1 Bead (`gascity-bead-dispatch`, on a bead reference)

| Action | gc command | Class | Mech | Confirm |
|---|---|---|---|---|
| Sling / route | `gc sling [target] <id> [flags]` | `gascity-command-sling` (extant) | transient | dry-run |
| Close | `gc bd close <id> -r <reason>` | `gascity-command-bd-close` | act | y/n |
| Reopen | `gc bd reopen <id>` | `gascity-command-bd-reopen` | act | — |
| Note (append) | `gc bd note <id> <text>` | `gascity-command-bd-note` | act / compose | — |
| Set priority | `gc bd priority <id> <n>` | `gascity-command-bd-priority` | act | — |
| Set status | `gc bd update <id> --status …` | `gascity-command-bd-update` | act | — |
| Assign | `gc bd assign <id> <name>` | `gascity-command-bd-assign` | act | — |
| Create (quick) | `gc bd create <title> --type --priority -a` | `gascity-command-bd-create` | json | — |

All bead verbs carry `:directory` (`-C`) from `gascity-beads--bead-path`
(§3.2a). The subject id comes from `gascity-bead-at-point`
(`gascity-section.el:201`), which already resolves a bead from a
`gascity-bead` text property or a tabulated row id.

### 7.2 Agent / session (extends the shipped session keys)

| Action | gc command | Class | Mech | Confirm |
|---|---|---|---|---|
| Reset (fresh restart) | `gc session reset <t>` | `gascity-command-session-reset` | act | y/n |
| Undrain | `gc runtime undrain <t>` | `gascity-command-runtime-undrain` | act | — |
| Rename *(ph3)* | `gc session rename <t> <name>` | `gascity-command-session-rename` | act | — |
| Close *(ph3)* | `gc session close <t>` | `gascity-command-session-close` | act | y/n |
| Pin / Unpin *(ph3)* | `gc session pin/unpin <t>` | … | act | — |

Targets resolve via the existing `gascity-action--session-at-point` /
`--read-session` (`gascity-action.el:139`).

### 7.3 City / rig

| Action | gc command | Class | Mech | Confirm |
|---|---|---|---|---|
| Reload config | `gc reload [--soft]` | `gascity-command-reload` | act | — (`--soft` via prefix arg) |
| Rig add *(ph3)* | `gc rig add <path>` | `gascity-command-rig-add` | act | — |
| Rig remove *(ph3)* | `gc rig remove <name>` | `gascity-command-rig-remove` | act | y/n |

Refresh/resume/suspend/restart already shipped (P1).

### 7.4 Mail (`gascity-mail-dispatch`, in the inbox)

| Action | gc command | Class | Mech | Confirm |
|---|---|---|---|---|
| Read | `gc mail read <id>` | `gascity-command-mail-read` | act (+show body) | — |
| Mark read / unread | `gc mail mark-read/unread <id>` | `gascity-command-mail-mark-read` … | act | — |
| Archive | `gc mail archive <id>` | `gascity-command-mail-archive` | act | y/n |
| Reply | `gc mail reply <id> -s … -m …` | `gascity-command-mail-reply` | compose | — |
| Send | `gc mail send <to> -s … -m …` | `gascity-command-mail-send` | compose | — |

Mail at-point id: the inbox row id is the whole message alist
(`gascity-mail-inbox--entry`, `gascity-tabulated.el:805`); `read`/`archive`/
`reply` need the message’s `id`. **Caveat to verify (phase-1 task):**
confirm `gc mail inbox --json` includes `id` per the v1 `mail_message`
schema; if it is absent, the row must be enriched with it (a quick `gc mail`
field check), since the documented schema today lists only
`from`/`subject`/`created_at`/`read`.

`gc mail read` also *marks read*; the inbox refresh then drops it under the
default unread view. `RET` keeps its current cheap behavior (show cached
fields without contacting gc); `r` is the gc-contacting read.

---

## 8. Safety model

- **Confirm the irreversible / far-reaching:** close, reopen-vs-close,
  session reset/close/kill, rig remove, city stop, archive. `yes-or-no-p`
  with the subject named (the P1 helper already interpolates the target,
  e.g. `gascity-action.el:196`).
- **Dry-run the dispatch:** `sling` exposes `--dry-run`/`-n` as a transient
  infix; running it shows gc’s routing plan in the echo/peek buffer before a
  real run. This is the preview affordance for the one command where “what
  will this do” is non-obvious (auto-convoy, formula instantiation,
  cross-rig).
- **Validate before `gc`:** every required positional gets a
  `gascity-command-validate` method (the `gascity-command--blank-p` pattern,
  `gascity-types.el:255`) so a missing id/target fails locally with a clear
  message, never a raw gc usage error.
- **Surface failures cleanly:** `gascity-command-act` already re-signals
  validation/command errors as `user-error` carrying gc’s stderr
  (`gascity-action.el:80`); new commands inherit this untouched.
- **No silent store cross-talk:** bead writes always pass `-C` (§3.2a) so a
  mutation can never land in the wrong rig’s database.

---

## 9. Async / refresh / error flow

Unchanged from P1, extended at the edges:

```
key/​transient → build gascity-command-* → gascity-command-execute-interactive
  → (action) gascity-command-act           ; sync, validated, echo summary
      → success: gascity--refresh-current-view   ; in-place re-render
      → failure: user-error (gc stderr)
  → (compose) C-c C-c → same act path with the buffer body
```

Quick mutations stay **synchronous** (they return in well under a second;
P1 made this call deliberately). The only long-running writes remain city
start/stop, which keep the streaming `async-shell-command` base method.
Refresh reuses the mode-dispatch table (§3.3 fills its two gaps).

---

## 10. Keybinding map (collision-checked)

Reserved today — base: `]` `[` `G` `S`(sort, tabulated) · `RET` `q` (vui);
common: `g` `/` `RET` `b` `d` `t` `i` `s` `r` `R` `N` `K` `w` `D` `p` `n`
`x`. New bindings avoid every one of these **within each view’s own keymap**
(transient menus are separate keymaps once invoked, so their inner letters
don’t collide with view keys):

| View | New keys |
|---|---|
| status dashboard | `L` reload (prefix → `--soft`) · `c` → `gascity-bead-dispatch` (on a bead ref) · `R` reset · `U` undrain (on an agent) |
| rig dashboard | `c` → bead-dispatch (ready/in-progress refs) · `R` reset · `U` undrain |
| session detail | `c` → bead-dispatch (hook/history refs) · `R` reset · `U` undrain |
| session list | `R` reset · `U` undrain |
| mail inbox | `r` read · `R` reply · `a` archive · `u` mark-unread · `c`→ `gascity-mail-dispatch` (adds send) |
| (bead refs everywhere) | `S` sling/route shortcut (→ `gascity-sling-dispatch`) |

`gascity-bead-dispatch` inner keys: `s` sling · `c` close · `o` note · `p`
priority · `u` status · `a` assign · `r` reopen · `n` create · `v` visit
(beads.el). `gascity-mail-dispatch` inner keys: `r` read · `R` reply · `s`
send · `a` archive · `u` unread. Main `gascity` transient gains a
**“Bead/Mail”** group entry for each dispatcher. (Exact letters are the
proposal; final assignment is fixed in each phase’s review.)

---

## 11. Testing strategy

Follow the shipped suite (`lisp/test/gascity-test.el`, ~101 ERT tests):
pure, gc-free tests plus a skip-if-no-gc integration test.

- **Command-line construction** per new class — assert
  `gascity-command-line` emits the right `gc bd close <id> -C <dir> -r …`,
  `gc session reset …`, `gc mail reply <id> -s … -m …` (mirrors
  `gascity-test-list-command-lines`).
- **Validation** — missing id/target/reason yields the expected
  `gascity-command-validate` string.
- **Store routing** — `gascity-beads--bead-path` feeds `:directory`; a
  bead-write class for a `gce-` id emits `-C <gascity rig path>`.
- **Summary** — `gascity-action--summarize` renders `id` (create) and
  `message_id` (send).
- **Confirmation gating** — `cl-letf` `yes-or-no-p`/`gascity-command-execute`
  to assert a “no” answer skips the run and a destructive verb is gated
  (mirrors the existing terminal-attach behavior tests).
- **Refresh dispatch** — `gascity--refresh-current-view` now resolves mail
  and convoy modes.
- **Compose** — `gascity-compose-finish` calls its closure with the buffer
  body and buries the buffer.

Each phase ships its slice of tests with its code; the offline byte-compile
+ test gate stays green per the rig convention.

---

## 12. Phasing (the epic)

Ordered safest/highest-value → richest, per the brief. P1 verbs are already
done and are **not** re-listed. Each phase is a sub-issue of the epic, plus a
testing sub-issue.

- **Phase 1 — Safe additive + lifecycle completion.** New action-base
  plumbing (§3.2–3.3: `gascity-command-bd-action` `-C` slot, summarize
  `id`/`message_id`, refresh gaps). Bead **note**; session **reset** +
  **undrain**; city **reload** (`--soft`); mail **read** / **archive** /
  **mark-read/unread** (+ verify inbox `id`). Lowest blast radius; exercises
  bead-id and mail-id at-point resolution end to end.
- **Phase 2 — Dispatch + close.** `gascity-bead-dispatch` +
  `gascity-mail-dispatch` transients; richer **sling** transient
  (`--formula`/`--merge`/`--reassign`/`--no-convoy`/`--var`/`--title` +
  `--dry-run` preview, deferred #8); bead **close**/**reopen** + **assign**;
  `order run --rig` (deferred #9); mail **send**/**reply** via the compose
  buffer (§6, new `gascity-compose.el`).
- **Phase 3 — Author + compose.** Bead **update** (status/priority/
  assignee/deps) and **create** quick-capture (hand off to beads.el for
  elaboration); session **rename**/**close**/**pin/unpin**/**prune**; rig
  **add**/**remove** (confirmed). Highest surface; lands last.

Each phase: code + ERT (§11) + a short dogfood pass against the live town,
read-then-write, on a throwaway bead/mail.

---

## 13. Open questions

1. **Mail row `id`.** Does `gc mail inbox --json` carry `id`? Needed for
   at-point read/archive/reply. Verified-by task in phase 1; if absent,
   enrich the row (cheap `gc mail` lookup) rather than block.
2. **`gc bd` prefix routing vs `-C`.** `gc bd` *may* already route writes by
   the id prefix (it does for `show`). The design pins `-C` defensively
   (matching the proven read-side gce-bhr fix); a phase-1 check can confirm
   whether `-C` is strictly required or belt-and-suspenders. Keep it either
   way — correctness over brevity for mutations.
3. **Create depth.** Quick-capture in gascity vs. always bounce to beads.el
   `create-form`. Proposed: quick-capture for title/type/priority/assignee,
   beads.el for bodies. Revisit if operators want full authoring in-place.
4. **`gc session submit`** (semantic-intent message) — richer than `nudge`;
   worth a later action? Deferred; not in the brief.

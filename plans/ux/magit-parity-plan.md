# beads.el + gascity.el — Magit/Forge-parity UX study and plan

Bead: `ga-uhyll` ([ux] beads.el + gascity.el magit/forge-parity UX study + plan)
Author: pool worker `ec-wisp-rollhm` (agent `gascity.el/pi`)
Date: 2026-10-11
Scope: UX/text study only — no product behavior was changed by this study.

---

## 0. TL;DR

Both packages are already far past "auto-generated transient" territory: they
have hand-written dispatch menus, a single navigation contract, sectioned vui
buffers, at-point actions, async reads, and an explicit extension model. The
gap to Magit/Forge is no longer *architecture*; it is **consistency and
discoverability across the two packages**, and **documentation that has
drifted from the code**.

The three changes with the largest payoff:

1. **One shared key registry, checked by a test.** gascity.el rebinds keys
   that already mean something different in beads.el (`d`, `s`, `w`, `i`,
   `t`, `S`, `D`, `K`, `M`, `C`). Today the meaning silently changes when you
   cross from a beads list to a gascity list. Publish the collision table and
   make a cross-package ERT test assert it.
2. **Fix the documented entry points and dispatch tables, or generate them.**
   `README.md` lists dispatch keys that do not exist (`s`=Show, `S`=Stats,
   `e`=Export, `i`=Import, `M`=Mark all) and `docs/ui-redesign.md` says
   `M-x beads` opens `beads-status`, while the code maps it to
   `beads-dashboard` and `beads-list` is a transient prefix, not the list.
3. **Unify the two gascity dispatch menus and add levels to the maintenance
   wall.** `M-x gascity`, `gascity-dispatch` (`?`), and the per-context
   backends overlap with different keys; `beads-maintenance` is ~60 suffixes
   in one frame with no `:level` filtering.

---

## 1. Method and evidence

Read-only study. No GUI frames, no screenshots. All evidence is reproducible
headless.

* Read `beads.el/README.md`, `beads.el/MAGIT_PATTERNS.md`,
  `beads.el/docs/ui-redesign.md`, `gascity.el/docs/DESIGN.md`,
  `gascity.el/docs/DESIGN-write-actions.md` (§10), and the menu/keymap source
  of both packages.
* Introspected the flattened keymaps with a batch Emacs
  (`/tmp/ux-introspect.el`, script inlined in §7) on Emacs 31.1.
* Drove a throwaway **beads-only** store with the real `bd` (1.3.1) and
  rendered the real beads.el buffers (`beads-list-all`, `beads-show`,
  `beads-dashboard`) in batch Emacs.
* gascity was exercised by source/keymap inspection; the cockpit was not
  rendered against a live city (see §8 residuals).

### 1.1 The beads fixture

```bash
TMP=$(mktemp -d /tmp/beads-ux.XXXXXX); cd "$TMP"; git init -q
bd init --prefix ux
bd create "Design login flow" -t feature -p 1
bd create "Implement login"   -t task    -p 1
bd create "Write docs"        -t chore   -p 3
bd dep add ux-526 ux-o8d --type blocks
bd update ux-o8d -s in_progress
bd update ux-526 --add-label backend
bd close ux-bnz -r "not needed yet"
```

`beads-list-all` rendered (buffer `*beads-list[beads-ux.Y0YGQY]*`):

```
  ▾ In progress (1)
  ux-o8d   feature  in_progress  P1  Design login flow   2026-10-11 17:07  2026-10-11 17:07
  ▾ Open (1)
  ux-526   task     open         P1  Implement login     2026-10-11 17:07  2026-10-11 17:07
```

`beads-show ux-o8d` rendered (buffer
`*beads-show[beads-ux.Y0YGQY]/ux-o8d Design login flow*`):

```
ux-o8d: Design login flow
◐ In Progress  P1  Feature  Roman Scherer
──────────────────────────────────────────────────────────────
  q bury · g refresh · ? dispatch
  Store  beads-ux.Y0YGQY
Created: … Started: … Updated: …
BLOCKS
  ← ○ ux-526: (TASK) Implement login ● P1
────────────────────────────────────────────────────────────
 d close ·  C claim ·  s status ·  # priority ·  e edit ·  c comment ·  w copy id ·  ? dispatch
```

`beads-dashboard` rendered:

```
Beads-Dashboard — beads-ux.Y0YGQY
▾ 📊 Stats
Open 1  Ready 0  In-progress 1  Blocked 1  Closed 1
▾ 📦 Recently Closed (1) ...
▾ 🚧 In progress (1) ...
▾ ✅ Ready (0)   Nothing ready.
▾ 🔒 Blocked (1) ...
▾ 🎯 Epic Progress (0)   Nothing to show.
▾ 💤 Stale in-progress (0)  Nothing to show.
▾ 🩹 Orphaned dependencies (0)  Nothing to show.
▾ Recent changes (3) ...
KEYS: TAB/S-TAB next/prev · SPC fold · N/P section · M-0..M-4 depth · +/-/* rows · g refresh · c claim · b blocker · a agent · RET visit · q quit
```

Because the agent shell leaks `GC_*`/`BD_*`/`BEADS_*` (this session had
`GC_CITY=/home/roman/emacs-city`, `BEADS_DIR=…/gascity.el/.beads`), every
command above had to run under
`env -u GC_CITY -u BEADS_DIR -u BEADS_ACTOR …`. A first `bd init` in the
throwaway repo actually aborted on `emacs-city`'s store. **This is itself a
UX/documentation bug worth fixing**: the README's setup instructions do not
warn that agent shells poison the store, although the study bead did.

### 1.2 The flattened keymaps (introspection output, abridged)

`beads-list-mode-map` (effective local bindings):

```
RET=beads-list-show  TAB=beads-thing-forward  SPC=beads-thing-toggle
n/p=next/prev  N/P=next/prev section  g=refresh  q=quit  ?=beads-dispatch
m=mark u=unmark U=unmark-all  *!=mark-all  B s/p/c/o=bulk
c/+=create  e=update  D=delete  d=close  k=close  o=reopen  C=claim
s=set-status  #=set-priority  w/C-w=copy-id  S=sort  l=filter  /=filter-menu
x=clear-filter  a=agent-prefix  ]/[/G=pager
```

`gascity-dashboard-mode-map` (effective local bindings):

```
RET=activate  TAB/S-TAB=thing motion  SPC=toggle  N/P=sections  g=refresh
?=gascity-dispatch  S=sling  j=jump-map  W=live
i=detail  v=peek  b=beads  d=dired  t=tmux  l=rig-log
M=nudge  s=suspend  r=resume  K=kill  w=wake  D=drain  R=reset  U=undrain
c=bead-dispatch  m=mail-dispatch  L=reload  C=lifecycle  O=order-run
```

`gascity-section-mode-map` flattened shows **multiple definitions per key**
inherited + local: `?`→{`beads-dispatch`,`gascity-dispatch`},
`RET`→{`beads-section-visit-issue`,`gascity-section-activate`},
`TAB`→{`beads-thing-forward`,`gascity-thing-forward`,`vui-forward`},
`q`→{`beads-section-quit`,`quit-window`,`vui-quit`},
`g`→{`beads-section-refresh`,`vui-refresh`}. Local wins, but the flattened
dump is a maintenance trap (see F11).

---

## 2. Scorecard against the rubric

| # | Criterion | beads.el | gascity.el | Notes |
|---|---|---|---|---|
| 1 | Hand-written transients | **B+** | **A-** | Excellent dispatch + per-command menus; maintenance menu is a wall (F5); some menus are still auto-generated backends. |
| 2 | Sectioned buffers | **A-** | **A** | vui sections, fold, hl-line, at-point; dashboard and cockpit both good. gascity work/agent sections are especially Magit-like. |
| 3 | Key consistency | **C+** | **B+** | Internally mostly consistent; cross-package collisions are the big hole (F1). Duplicate close keys (F8). |
| 4 | Context sensitivity | **B** | **A-** | gascity confirms destructive actions and uses tracked async processes; beads prompts for close reason but has no confirm for bulk/delete beyond the menu. |
| 5 | Discoverability | **C** | **B** | Footers inconsistent (F7); README/maintenance stale (F2); `?` not in every footer. |
| 6 | Reversibility / safety | **B-** | **B** | No undo; gascity has confirm + reset/undrain; beads has transient delete but no dry-run for bulk. |
| 7 | Process/error UX | **B** | **A-** | gascity has deadline+store+log; beads surfaces `bd` errors but has no single log/error buffer. |
| 8 | Ergonomics (top-10) | **B** | **B+** | See §6. |

---

## 3. Findings, ranked by impact

Each finding has an exact reproduction.

### F1 — Cross-package key collisions silently change meaning (HIGH)

gascity.el is layered on beads.el (`gascity-section-mode` derives
`beads-section-mode`; `beads-define-prefix` everywhere), yet its agent/list
keys reuse letters that already mean something else in beads.el:

| Key | beads.el meaning | gascity.el meaning | Type |
|---|---|---|---|
| `d` | close issue (`beads-actions-close`) | Dired at point (`gascity-dired-at-point`) | destructive vs navigate |
| `s` | set status (`beads-actions-set-status`) | suspend agent (`…suspend`) | mutation |
| `w` | copy id | wake agent | safe vs mutation |
| `i` | show issue (dispatch `i Show…`) | polecat detail | navigate |
| `t` | stats (dispatch `t Stats`) | tmux attach | navigate |
| `S` | sort list | sling (sort moves to header click) | — |
| `D` | delete (list) / distill (show) | drain agent | destructive |
| `K` | — | kill agent | destructive |
| `M` | (README: mark all; actually unbound) | nudge agent | mutation |
| `C` | claim | lifecycle dispatch | — |
| `l` | list/filter | rig log | — |

`docs/DESIGN-write-actions.md` §10 says the map is "collision-checked" — but
§10 only checks collisions **within a single gascity view**. It never checked
against beads.el's own keys. The result is that the same physical key does
opposite things depending on which package's buffer you are in, with the same
`?` menu chain.

Repro / evidence: §1.2 keymap dump, plus
`docs/DESIGN-write-actions.md` §10.

**Impact:** the destructive ones (`D` drain vs delete, `K` kill, `s`
suspend vs status) are the ones a Magit user reaches for by muscle memory.
This is the single biggest blocker to "world-class, safe" parity.

### F2 — Documentation has drifted from the code (HIGH)

* `README.md` §"Entry Points" (lines ~174–200) advertises dispatch keys that
  are wrong or missing:
  * `s` "Show specific issue" → actual `i` is Show; `s` is **Set status**.
  * `S` "Show statistics" → actual `S` is **Swarms**; stats is `t`.
  * `e` "Export to JSONL" → actual `e` is **Edit field**.
  * `i` "Import from JSONL" → actual `i` is **Show**.
  * `M` "Mark all" (list mode) → not bound; actual is `* !` / `* *`.
  * `RET` / `s` "Show issue" in list mode → `s` is **set-status**.
* `docs/ui-redesign.md` §1: "`M-x beads` | `beads-status` | the Magit-like
  status board — the front door" and the same table says
  "`M-x beads-list` / `beads-ready` / `beads-blocked` | list views". In the
  code `beads.el:378` maps `beads` → `beads-dashboard`, and `beads-list` is a
  **transient prefix** (`beads-command-list.el:1592`), not the list view.
* `MAGIT_PATTERNS.md` recommends buffer names `*beads-list: PROJECT*`; actual
  is `*beads-list[ROOT]*` and `*beads-show[ROOT]/ID TITLE*`.

Repro:
```bash
emacs -Q --batch --eval '(progn (require (quote beads))
  (princ (documentation (quote beads-list))))'   # shows "List issues with filters" transient doc
grep -n "autoload .beads " lisp/beads.el          # 378: (autoload 'beads "beads-dashboard" nil t)
```

### F3 — `beads-list` is a transient, but every doc says it is the list (MEDIUM)

The dispatch does `("l" "List beads" beads-list)`; `l` opens a filter
transient (`l l` to actually list). The command menu and README describe it
as a direct navigation action. This is a guaranteed "why did nothing open?"
for a new user.

**Fix options:** rename the transient to `beads-list-filters`, and have
`l` call `beads-list-all` directly with the filter menu on `/`; or keep it and
document `l l`. The first matches Magit (a menu key always opens the view).

### F4 — gascity has two overlapping dispatch menus (MEDIUM)

`M-x gascity` (`gascity`, `gascity.el:118`) and `?`→`gascity-dispatch`
(`gascity-dashboard.el:2273`) cover the same verbs with different keys
(`h` vs `j j`, `d` vs `j g`, `r`/`a`/`c` vs `j r`/`j a`/`j v`, `R`/`A`/`S`/`O`/`L`
vs the at-point group). The `?` menu is the better one (it teaches view keys),
so the top-level menu is the one that should converge on it.

Additionally the flattened `gascity-section-mode-map` carries duplicate
handlers for `?`, `RET`, `TAB`, `q`, `g` (F11) — a symptom of layering
without reconciling intent.

### F5 — `beads-maintenance` is a ~60-key wall (MEDIUM)

`beads-menu.el:123` holds 9 groups × 5–13 keys = ~60 suffixes in a single
frame with no `:level` filtering, mixing daily operations (Defer, Delete,
Backup) with rare ones (ADO, Notion, Federation, Migrate). Magit solves this
with `:level` and nested dispatchers.

Repro: `M-x beads-maintenance` (or `!` from any beads buffer).

### F6 — Two things named "status"/"dashboard" (MEDIUM)

`beads-dashboard` (the board) and `beads-status` (`bd status` snapshot,
`beads-command-status.el`) are different objects with confusingly similar
names, and the design doc conflates them with the front door (F2). A user
typing `M-x beads-status` gets stats, not the board.

### F7 — Footer/help coverage is inconsistent (LOW–MED)

* `beads-show` footer ends `… ? dispatch` — good.
* `beads-dashboard` footer lists `RET visit · q quit` but **omits `?`**
  (dispatch is the most important discoverability key).
* gascity tabulated lists show sort/filter/refresh state in the mode line but
  no at-a-glance "`?` all verbs" hint in the header line.
* `beads-list` has no footer at all (only the tabulated header row).

### F8 — Duplicate and unadvertised close keys (LOW)

`beads-list-mode-map` binds both `d` and `k` to `beads-actions-close`, while
the dispatch menu advertises `x` for "Close bead" (`beads-menu.el:84`) and
the show buffer uses `d`. Three letters for one verb, and `x` means
`clear-filter` in list mode. Pick `d` (Magit `d` = discard/delete-adjacent)
everywhere and retire `k`/`x` for close; `x` stays "clear filter" only.

### F9 — Buffer-name drift from the documented convention (LOW)

`*beads-list[ROOT]*` / `*beads-show[ROOT]/ID TITLE*` vs the documented
`*beads-list: PROJECT*`. Not harmful, but the convention doc should match the
code (or vice-versa) so external code can match on names.

### F10 — No dry-run/preview for bulk mutation (LOW–MED)

`beads-list` bulk (`B c` close, `B o` reopen) executes directly; a marked
set can be large. Magit's analogue is a confirmation summary of what will be
acted on. gascity already has preview for its costly/ambiguous action
(sling), so the pattern exists.

### F11 — Flattened keymap duplicates are a maintenance trap (LOW, hygiene)

The introspection in §1.2 shows `?`, `RET`, `TAB`, `q`, `g` defined at more
than one level of the `beads-section-mode` → `gascity-section-mode` chain.
Local bindings win today, but a future parent redefinition can silently
re-point them. Add a test that asserts the *effective* binding of the
navigation contract keys and of the shared agent keys (this is also the
mechanism for F1's registry).

---

## 4. Proposed changes

### 4.1 Both packages — a shared key registry (fixes F1, F8, F11)

Create `docs/key-registry.md` in **each** repo (cross-referenced), listing
every reserved key and the at-point type it applies to. gascity.el adds a
`lisp/test/gascity-key-registry-test.el` (and beads.el a mirror) that:

1. Asserts the universal contract (`q` bury, `g` refresh, `TAB`/`S-TAB`
   thing motion, `SPC` toggle, `RET` activate, `n`/`p` item, `N`/`P`
   section, `?` dispatch) in every mode's **effective** map.
2. Asserts at-point action keys keyed by the type at point, not by mode:
   a bead row and a session row may share a key only when the verb is the
   same. The test enumerates `(mode, key) → command` and compares against the
   registry, failing on an unregistered divergence.

Proposed registry (superset; the "scope" column is what the test enforces):

| Key | Bead scope | Agent/session scope | City/rig scope | List scope |
|---|---|---|---|---|
| `RET` | visit bead | detail | drill in | drill in |
| `SPC` | toggle/fold | toggle drawer | fold | row detail |
| `d` | **close bead** | — | — | close bead |
| `D` | delete (menu) | **drain** | — | — |
| `s` | set status | suspend | suspend rig | — |
| `S` | sling bead | sling work | sling | sling |
| `C` | claim | — | — | claim |
| `#` | priority | — | — | priority |
| `w` | copy id | wake | resume | copy |
| `K` | — | kill | — | — |
| `M` | — | nudge | — | — |
| `i` | show | detail | — | — |
| `t` | stats | attach tmux | — | — |
| `x` | — (filter clear only) | — | — | clear filter |
| `?` | beads-dispatch | gascity-dispatch | gascity-dispatch | beads/gascity-dispatch |

Concrete rule to resolve F1: **gascity may not reuse `d`, `s`, `w`, `i`, `t`,
`D`, `C`, `#` for a non-bead verb inside any buffer that can also contain a
bead**. For agent rows the verbs move under a namespaced key:

* `a` (already the agent prefix in beads) → `a n` nudge, `a s` suspend,
  `a w` wake, `a k` kill, `a D` drain, `a r` reset, `a u` undrain, `a t`
  attach, `a d` dired.
* `gascity-dashboard` keeps the fast single-letter aliases **only** because
  its rows are agents, not beads; the header line must say
  `M nudge · s suspend · K kill` (it already does), and the registry test
  records the exception explicitly. This is the Magit "context major mode"
  escape hatch, but now it is *declared* and tested rather than implicit.

### 4.2 beads.el — entry points and menus

* Rename the filter prefix `beads-list` → `beads-list-filters`; make the
  dispatch `l` open `beads-list-all` directly; keep `/` for filters and
  `l` inside the list for the full transient. Update autoloads.
* Fix or generate the README key table. Best: add
  `beads-dispatch` documentation generated from the transient definition in a
  CI check (a `--batch` script that walks the prefix and asserts the README
  block matches). Minimal fix: correct the five wrong rows.
* `docs/ui-redesign.md` §1: correct `M-x beads` → `beads-dashboard`, and
  state that `beads-status` is the `bd status` snapshot, not the front door.
* `MAGIT_PATTERNS.md`: update the buffer-name examples to the `[ROOT]` form.
* Add `:level` to `beads-maintenance` groups: level 1 = daily (Defer,
  Undefer, Delete, Rename, Unclaim, Count, Stats, Comments, Events), level 3
  = database, level 5 = integrations, level 7 = setup/migration. Split
  `Integrations` and `Setup` into their own sub-dispatchers reached from
  maintenance (`n`, `I`). Add the standard `C-x l` level cycling hint to the
  docstring.
* Retire `k` for close in `beads-list-mode-map` (keep `d`); keep `x` =
  clear-filter only. (F8)
* Add a dry-run/summary confirmation to bulk close/reopen: echo
  `Close 7 issues? (y or n)` listing ids, matching gascity's
  `gascity-action--confirm` style. (F10)

### 4.3 gascity.el — one dispatch, namespaced agent verbs

* Make `gascity` (top-level) a thin two-column menu that *is* the front door
  (views + jump), and point users at `?`→`gascity-dispatch` for verbs;
  delete duplicated verb keys from the `M-x gascity` prefix, or make
  `gascity` call `gascity-dispatch`. (F4)
* Reconcile the layered maps: `gascity-section-mode-map` should bind each
  contract key exactly once at the level that owns it, and the test in §4.1
  asserts the effective binding. (F11)
* Add the at-a-glance hint to tabulated header lines:
  `filter: …  · ? all verbs · j jump`. (F7)
* Fix `docs/DESIGN-write-actions.md` §10 to include the cross-package table
  from §4.1 and cite the registry test.

---

## 5. ASCII mockups

### 5.1 Unified gascity dispatch (`?`)

```
Gas City  emacs-city  ~/emacs-city   ● live 00:03
──────────────────────────────────────────────────────────────
 Jump                              Agent at point (row type: agent)
  j j  cockpit        j o  orders    M  nudge…      s  suspend
  j a  agents         j v  convoys   K  kill        w  wake
  j r  runs           j d  dolt      D  drain       R  reset
  j b  beads          j g  rig       U  undrain     t  attach
  j m  mail           j $  costs
  j e  events         j h  health    Bead at point (row type: bead)
  j c  cities                        S  sling…      c  close
                                     o  note…       p  priority
 Work          City                  u  status…     a  assign
  S  sling…     L  reload            r  reopen      n  create
  m  mail…      C  lifecycle…        v  visit (beads.el)
                O  run order…
                W  toggle live
                +  more rows   -  fewer rows
                g  refresh        /  filter…
──────────────────────────────────────────────────────────────
[Agent] / [City] group labels are generated from the row type at point;
both halves are shown when the dashboard has no row at point.
```

### 5.2 Cross-package key registry (the table the test enforces)

```
KEY  bead row        agent row       rig row      list/tabulated
────────────────────────────────────────────────────────────────
RET  visit bead      open detail     rig dash     drill in
SPC  fold/toggle     toggle drawer   fold         row detail
d    close bead      —               —            close bead
D    delete…         drain           —            —
s    status…         suspend         suspend      —
S    sling…          sling…          sling…       sling…
w    copy id         wake            resume       copy
K    —               kill            —            —
M    —               nudge           —            —
C    claim           —               —            claim
#    priority        —               —            priority
x    —               —               —            clear filter
?    beads-dispatch  gascity-dispatch gascity-dispatch per package
```

### 5.3 `beads-dispatch` with the `[City]` provider group (target, tidy)

```
Beads — beads-ux.Y0YGQY
──────────────────────────────────────────────────────────────
 Issues                Workflow             Views
  l  List beads         r  Ready work        a  Agents…
  c  Create bead        b  Blocked work      F  Formulas…
  /  Search             d  Dependencies      v  Graph
  i  Show…              #  Priority          D  Dashboard
  u  Update bead        C  Claim             H  History
  x  Close bead         s  Set status        R  Recent changes
  o  Reopen bead        m  Molecules         Y  Orphans
  e  Edit field         G  Gates             t  Stats
                        T  Types             X  Context
 Manage               Maintenance
  L  Labels…            !  Maintenance…      City (gascity)
  k  Dolt…              g  Refresh cache      h  cockpit   S  sling…
  .  Config             q  Quit              j  jump      s  suspend
  W  Worktrees…                             (provider group)
```

### 5.4 `beads-maintenance` with levels (collapsed default view)

```
Maintenance            [C-x l cycles levels]      level 1
──────────────────────────────────────────────────────────────
 Issue Lifecycle            Database               Setup (level 7)
  f  Defer                   b  Backup              I  Init project
  F  Undefer                 E  Export JSONL        Q  Hooks…
  D  Delete                  h  Compact             W  Quickstart
  R  Rename                  +  Doctor
  u  Unclaim                 U  Upgrade            Integrations (level 5)
                                                    n  Jira   N  Linear
 Views & Reports            Structure               y  GitLab 9  GitHub
  c  Count                   J  SQL query            A  ADO
  t  Stats                   k  Rename prefix         >  Federation
  l  Lint                    _  Forget memory
  O  Find duplicates
  o  Orphans
```

### 5.5 beads.el front-door decision (F2/F6/F3)

```
                 before                              after
 M-x beads      → beads-dashboard            M-x beads      → beads-dashboard  (unchanged)
 M-x beads-list → filter transient           M-x beads-list → list view (beads-list-all)
 l  in dispatch → filter transient           l  in dispatch → list view (beads-list-all)
                                             /  in list    → filter transient
 M-x beads-status → bd status snapshot        M-x beads-status → snapshot (docstring renamed "Status snapshot")
 docs/ui-redesign says M-x beads → beads-status   docs say M-x beads → beads-dashboard
```

---

## 6. Top-10 task keyboard cheat-sheet

| Task | Today | Proposed |
|---|---|---|
| Open the board | `M-x beads` | `M-x beads` (unchanged) |
| List all issues | `l l` (dispatch → transient) | `l` (one key) |
| Show issue at point | `RET` (list/show) | `RET` |
| Create issue | `c` (list) / dispatch `c` | `c` |
| Close issue | list `d`/`k`; dispatch `x`; show `d` | `d` everywhere |
| Set status | `s` | `s` |
| Set priority | `#` | `#` |
| Claim | `C` | `C` |
| Add/remove dep | dispatch `d`; bead menu `d`/`D` | `gascity-bead-dispatch d`/`D` (namespaced) |
| Sling work | gascity `S` | `S` |
| Nudge agent | dashboard `M` | dashboard `M`; agent prefix `a n` in mixed buffers |
| Full verb list | `?` | `?` in every footer |

---

## 7. Evidence script (reproduce the keymap dump)

```elisp
;;; /tmp/ux-introspect.el  — run with a batch Emacs, stripping GC_*/BD_*/BEADS_*
(setq load-prefer-newer t)
(dolist (d '("/home/roman/workspace/beads.el/lisp"
             "/home/roman/workspace/gascity.el/lisp"
             "/gnu/store/q3fwddl2gmq7y2fbzcc5p7vdlp8p800v-emacs-vui-1.4.0/share/emacs/site-lisp/vui-1.4.0"))
  (add-to-list 'load-path d))
(require 'beads) (require 'gascity)
(defun ux-dump (m) (princ (format "\n### %S\n" m))
  (map-keymap (lambda (k d) (when (symbolp d)
                              (princ (format "%s => %s\n" (key-description (vector k)) d))))
              (symbol-value m)))
(dolist (m '(gascity-section-mode-map gascity-tabulated-base-map
             gascity-dashboard-mode-map gascity-session-list-mode-map))
  (ux-dump m))
```

```bash
env -u GC_CITY -u GC_CITY_PATH -u BEADS_DIR -u BEADS_ACTOR \
  emacs -Q --batch -l /tmp/ux-introspect.el
```

---

## 8. Prioritized roadmap

### Quick wins (hours, no architecture change)

1. Fix the five wrong README dispatch rows; fix the `docs/ui-redesign.md`
   entry-point table; fix `MAGIT_PATTERNS.md` buffer names. **(beads)**
2. Add `? dispatch` to the `beads-dashboard` and gascity-list header/footer
   hints. **(beads + gascity)**
3. Add the cross-package key table to `docs/DESIGN-write-actions.md` §10.
   **(gascity)**
4. Retire `k` (and dispatch `x`) for close in favour of `d`. **(beads)**
5. `:level` tag the `beads-maintenance` groups. **(beads)**

### Medium

6. Rename `beads-list` prefix → `beads-list-filters`; dispatch `l` opens the
   list directly. **(beads, touches autoloads/tests)**
7. Merge `M-x gascity` into `gascity-dispatch` (one verb menu). **(gascity)**
8. Namespaced agent verbs (`a n/s/w/k/D/r/u/t/d`) for mixed buffers +
   registry test. **(gascity + beads test seam)**
9. Bulk-mutation confirmation summary. **(beads)**
10. Effective-binding registry test in both repos. **(both)**

### Larger (each its own bead)

11. A single "front door" story: decide whether `beads-dashboard` and the
    `bd status` snapshot merge into one Magit-style status buffer
    (Stats as a section), and rename `beads-status` accordingly. **(beads)**
12. A generated snapshot/docs test so the dispatch reference can never drift
    again (`eldev` script + CI). **(beads, gascity consumes)**
13. Undo/revert for bead mutations (event-backed), Magit-style. **(beads)**

### Repo ownership

* beads.el only: F2 (beads half), F3, F5, F8, F9, F10, quick wins 1, 4, 5.
* gascity.el only: F4, quick wins 2 (gascity half), 3, 7.
* both: F1, F6, F7, F11, medium 10, large 12.

---

## 9. Quick bug fixes applied by this study

**None.** This pool-worker pass is a read-only UX study; applying code fixes
would require dedicated branches/worktrees in two sibling repos and PRs, which
is out of the authorized scope of this bead's worker. Every quick fix above is
itemized with file/line evidence so it can be filed as its own bead (the bead
description explicitly allows "describe it in the plan instead of hacking it"
for anything not quick).

Residual risks / not covered:

* The gascity cockpit was not rendered against a live city in this pass
  (the study bead allows read-only gc; the plan's gascity findings are
  source + keymap evidence). A follow-up should render the cockpit and the
  session/rig/mail views over TRAMP against `~/bright-lights` and record
  friction in `docs/qa/`.
* The `beads-dashboard` async render was exercised only on a 3-issue fixture;
  large-store behaviour (paging, `M-0..M-4` depth, live marks) was not
  measured.
* No screenshots were produced (headless study, per the bead).

---

## 10. Summary

The top three changes that would most improve the two modes:

1. **A shared, tested cross-package key registry** — end the silent
   meaning-swap of `d`, `s`, `w`, `D`, `K` between beads and gascity buffers.
2. **Truthful entry points and dispatch documentation** — `M-x beads` is the
   board, `beads-list` is a transient, and the README's dispatch table is
   wrong; fix or generate it.
3. **One gascity verb menu and a levelled maintenance menu** — collapse the
   duplicate dispatch and stop showing 60 rare commands at level 1.

Verification for this deliverable: the plan itself, plus the reproducible
headless keymap dump (§7) and the real rendered buffers (§1.1).

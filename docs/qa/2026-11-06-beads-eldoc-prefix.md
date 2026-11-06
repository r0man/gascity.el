# Bead-id eldoc by prefix — live acceptance (2026-11-06)

Docs/QA item `ga-uq5pl` (plan
`plans/beads-eldoc-prefix/implementation-plan.md`, §H item 5; requirements
REQ-016, REQ-017, AC-5).

**Status: partial — the user-facing half is blocked at the merge boundary, not
at this item.**  The implementation is four sibling items that were still
uncommitted worktrees when this pass ran; none is merged into this docs
worktree (`origin/main` `994b42f` + the docs commit).  To verify anything
user-visible, this pass assembled a **QA-only composite tree** from the items'
current working trees in `/home/roman/workspace/gascity.el/worktrees/`:

| Item | Worktree | State at pass time |
|---|---|---|
| 1 map core (`ga-3cc7x`) | `ga-3cc7x` | module + tests + manual option entries, uncommitted |
| 2 install path (`ga-ewqlp`) | `ga-ewqlp` | install module + terminal wiring + test rewrite, uncommitted |
| 3 caller migration (`ga-jaup5`) | `ga-jaup5` | section/tabulated edits in progress at pass time, **not included** |
| 4 refresh/invalidation (`ga-5bpu0`) | `ga-5bpu0` | map invalidation + store/context wiring + tests, uncommitted |

The composite is a QA harness artifact, not a shippable tree: each item's
tests assert that item's own module shape, and composing them left 19 test
mismatches (e.g. the install tests' plist map stub against the struct
accessors, and the two item test files defining the same module).  The
authoritative green state is each item's own worktree and, at merge time, the
merged tree — not this composite.  The docs commit itself is verified by
`scripts/gate.sh` (998/998) and `make -C doc` (clean) on the unmodified docs
tree.

## Method

Fresh non-graphical Emacs 31.1 (`emacs -nw -Q`) inside tmux, driven through
`scripts/e2e-harness.sh` (every emacs/emacsclient/tmux call under `timeout`,
session verified before every send/capture).  Load path:
`<worktree>/lisp` → `~/workspace/beads.el/lisp` →
`~/workspace/beads.el/.eldev/31.1/packages/vui-1.4.0`.  Batch Emacs with the
same load path for the deterministic probes.

Cities: the local dogfood city `emacs-city` (rigs `ec` HQ, `be`, `ga`) and the
remote test city `/ssh:localhost:/home/roman/bright-lights` (rigs `bl` HQ,
`hw`).  No workflow was launched or mutated, no city restarted, no `gc` change.

## A. AC-1 — per-id resolution in a view buffer (PASS on the composite)

Local cockpit opened with `(let ((default-directory "/home/roman/emacs-city/"))
(gascity-dashboard))`:

```
buffer   *gascity: emacs-city@/home/roman/emacs-city/*
mode     gascity-dashboard-mode
scope    /home/roman/emacs-city/
prefixes ("ec" "be" "ga")
```

Point on the first `ga-` id in the rendered cockpit, then
`(beads-eldoc-function callback)` delivered:

```
id      ga-4hdav
echo    ga-4hdav [closed]: do-work
```

The id is a `gascity.el` rig id displayed in the **city's** cockpit and it
resolved in the `gascity.el` store (`/home/roman/workspace/gascity.el/`), not
the city store — the per-id contract, not the old per-buffer one.

`C-c b` is **BLOCKED**: in the vui view it still resolves to beads.el's prefix
map, not the new command:

```
(key-binding (kbd "C-c b"))
=> (keymap (63 . beads-dispatch) (98 . beads-mode-extension-bead-at-point))
```

That is item 3's key binding (`ga-jaup5`), unmerged.  When it lands, the
`C-c b` half of AC-1 and the vui half of REQ-014 need this same check again.

## B. AC-2 — worktree-captured buffer and TRAMP

The install contract was exercised with the city captured while
`default-directory` sits in a polecat worktree **outside** the city tree
(the local attach case), in batch:

```
buffer         qa-worktree
scope          /home/roman/emacs-city/
cold prefixes  ("")
after fill     ec-abcde -> /home/roman/emacs-city/
               ga-abcde -> /home/roman/workspace/gascity.el/
```

A live tmux agent transcript was **not driven**: the attach path itself is not
available in the composite beyond item 2's terminal wiring, and attaching to a
sibling item's working session during this pass would have interfered with
that item's run.  The worktree capture (the defect AC-2 targets) is verified;
the live attach buffer is deferred to the merged-tree pass.

Remote city over TRAMP, same Emacs:

```
buffer   *gascity: bright-lights@/ssh:localhost:/home/roman/bright-lights/*
scope    /ssh:localhost:/home/roman/bright-lights/
prefixes ("bl" "hw")

hover id  bl-bdj
echo      bl-bdj [open]: Formula v2 step targets (gc.run-operator) fail to
          resolve from HQ scope: 'unknown formulas v2 target'

tramp-list-connections before hover  1
tramp-list-connections after  hover  1
```

Hovering opened no new TRAMP connection (AC-2's proof), and the `bl-` id
resolved in the remote city store.

## C. AC-3 — cold start and in-place heal (PASS in batch)

In a fresh buffer created through the view factory for `emacs-city`:

```
cold:  prefixes ("")          resolver(ga-abcde) => nil
fill:  one `gc rig list` read (4 store ticks, ~0.4 s)
warm:  prefixes ("ec" "be" "ga")
       resolver: ec -> /home/roman/emacs-city/
                 ga -> /home/roman/workspace/gascity.el/
                 be -> /home/roman/workspace/beads.el/
                 zz -> nil
```

The same buffer went from deny-all to the city's prefixes without being
reopened or reverted.  No wrong-store `no issues found`, no spawn while cold.

A live view's cold window is sub-second on this host and could not be caught
deterministically from `emacsclient`; the batch probe above is the recorded
cold-start evidence.

## D. AC-4 — `post-command`, unknown prefix, repeated miss

With the warm allowlist in the cockpit buffer:

```
(beads-issue-id--allowed-p "post-command" beads-issue-id-prefixes) => nil
resolver("zz-abcde")                                            => nil
```

`post-command` and unknown prefixes start no lookup.  A known-prefix miss was
counted by advising `beads-eldoc--spawn` in batch (buffer seeded with
`ga-zzzzz`):

```
query-1 (first hover)                  state=pending spawned=1
query-2 (after the miss landed)        state=nil     spawned=0
```

The second query is answered from beads.el's negative cache: one lookup, not
two.

## E. REQ-014 — mouse hover

**BLOCKED (recorded reason).**  The pass is headless (`emacs -nw` in tmux); no
graphical frame exists, so `eldoc-mouse-mode` cannot be exercised.  Mouse hover
calls the same `beads-eldoc-function` whose buffer-local contract (resolver
function + prefix allowlist) is verified above, but the mouse event path itself
was not run.  Re-run it in a graphical session on the merged tree.

## F. Gates and docs

| Check | Result |
|---|---|
| `make -C doc` (docs tree) | **PASS** — `gascity.info` built, no makeinfo warnings |
| `scripts/gate.sh` (docs tree) | **PASS** — compile clean, 998/998 ERT |
| `scripts/lint.sh` (docs tree) | see the implementation summary |
| `scripts/gate.sh` (composite QA tree) | **FAIL** — 19 failures, all merge-shape mismatches between the four unmerged item trees; not a defect of any one item |

## Verdict

AC-1 (data plane), AC-2 (worktree capture, remote store, no new connection),
AC-3 and AC-4 are verified on the composite.  The `C-c b` halves of AC-1 and
REQ-014, the live agent transcript, and mouse hover are **deferred to the
merged-tree pass** (items 2/3 and a graphical frame), with the reasons above
rather than silently skipped.  Documentation (NEWS, manual section, option
entries) is committed and builds cleanly.

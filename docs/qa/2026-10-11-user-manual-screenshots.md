# QA: user-manual screenshots — fixture capture, verify, and reproducibility

Date: 2026-10-11
Bead: ga-1s3jv (WI-5, REQ-004/REQ-002; AC-4, AC-5, AC-10)
Worktree: `/home/roman/workspace/gascity.el/worktrees/ga-1s3jv`

## Summary

The screenshot pipeline was run end to end against the throwaway fixture,
the committed `doc/images/` were regenerated, and reproducibility was
proven two ways: `capture.sh --verify all` captured every fixture-producible
view twice and found every raw PNG **byte-identical** (26/26), and
`capture.sh --check-isolation cockpit` proved the 54 committed images
outside the scope kept their exact bytes. No live store (`~/emacs-city`,
`~/bright-lights`, the repo `.beads`) was read or written; all three mtimes
are unchanged.

Three manifest views are **excluded** from the fixture capture because the
offline fixture cannot seed sessions/agents/runs/mail; their committed
images are legacy live captures and are not regenerated. The exclusion is
recorded in `doc/screenshots/fixtures/README.md` ("Exclusions and risks"),
and is enumerated below. There are no *permitted* pixel differences
(plan D4): the raw captures of every producible view are byte-identical.

## Environment

| Tool | Version |
| --- | --- |
| Emacs (pgtk/GUI) | 31.1 |
| sway (headless wlroots) | 1.12 |
| ImageMagick `convert` | 6.9.13-5 |
| gc | 1.5.0 |
| ef-themes | 2.2.1 |

## Fixture

The fixture was created, seeded, and torn down by the pipeline itself. It
was pinned to a private `TMPDIR` so it could not collide with a concurrent
capture run in the shared fixed path:

```
fixture city (private TMPDIR): /tmp/ga-1s3jv-tmp/gascity-fixture
fixture rig:  demo-rig (prefix demo)
fixture GC_HOME: /tmp/ga-1s3jv-tmp/gascity-fixture/gc-home
```

`fixture.sh` unsets `BEADS_DIR`, `BEADS_DOLT_PORT`,
`BEADS_DOLT_SERVER_PORT`, `GC_DOLT_PORT` and passes an explicit `--city`,
so a leaked environment value cannot redirect a `bd`/`gc` call at a live
store. The seeded data is role-addressed (`demo-<role>`).

## Exact commands run

All from the item worktree, with the private `TMPDIR` so the fixed-path
fixture is isolated:

```sh
# 1. Regenerate the committed images from the fixture (deliverable 1)
TMPDIR=/tmp/ga-1s3jv-tmp GASCITY_SHOT_STAGING=/tmp/ga-1s3jv-final \
  make -C doc screenshots
# -> rc=0; 26 views captured; doc/images/ refreshed

# 2. Reproducibility: two runs, byte-identical (deliverable 2)
TMPDIR=/tmp/ga-1s3jv-tmp GASCITY_SHOT_STAGING=/tmp/ga-1s3jv-verifysub \
  doc/screenshots/capture.sh --verify all
# -> rc=0; verify: byte-identical for 26 image(s) (scope all)
#         isolation: OK (no non-selected committed image to check; scope all)

# 3. Subset-isolation check (AC-4): regenerate only cockpit, prove the rest untouched
TMPDIR=/tmp/ga-1s3jv-tmp GASCITY_SHOT_STAGING=/tmp/ga-1s3jv-verifysub2 \
  doc/screenshots/capture.sh --check-isolation cockpit
# -> rc=0; isolation: OK; 54 non-selected image(s) byte-identical (scope cockpit)

# 4. Fixture lifecycle self-check (REQ-003)
doc/screenshots/fixture.sh --verify
# -> PASS; 6 role-keyed beads OK; fixture removed

# 5. Scope/isolation unit self-test (no GUI)
doc/screenshots/capture.sh --self-test
# -> PASS (all checks)
```

`make -C doc screenshots` is the deliverable-1 spelling; it runs
`doc/screenshots/capture.sh` (default scope `all`) against the fixture.

## verify result

`--verify all` runs the whole manifest twice into two staging dirs and
`cmp`s every produced file byte for byte. Result:

```
[capture] verify: byte-identical for 26 image(s) (scope all)
[capture] isolation: OK (no non-selected committed image to check; scope all)
```

The scope produces 29 outputs (20 `-dark`, 9 `-light`); 26 are
fixture-producible. The 3 excluded outputs fail their thunks against the
offline fixture and are recorded below, not silently faked.

## Second-run digest manifest

`sha256sum` of every raw PNG from the second verify run
(`/tmp/ga-1s3jv-verifysub/verify-b/`). Manifest digest:
`sha256:7e73d233c8c2d698ab222a42e7ddf2709d7e41ecf2bec6e0d7b736067b214fa5`.

```
22f3328b31e3ae464d78227cbb2992ddd6e2c56943f11062bc0463acbe66dd68  agents-dark.png
4f1b81b7154870af00dabd6e89586d12f7ff534e028ff98a0bccbda57be8fbac  agents-tree-light.png
22aa38586e3e73a8f8037e37a070000682e37929535e4657f0c44a54fdcacd3c  bookmarks-dark.png
c5473490b364351b99108af90fcc9d1a56ce8b02d96d62f0fddef2b6883793df  cities-light.png
619714ae9930753674d813f8f42e04a058d012c48c583364234e426b6bee7a26  cockpit-dark.png
e47a51a0a84caeea9d354a37615f83e00c875279fb6a52f26b1f3083aec0f297  cockpit-light.png
a27c8166a73362e3665c7a91829db68305346d60a0b2492e1a055c6afe86bc9c  convoy-list-dark.png
13a5ad167222747a2bf997c2efa85280be5c39ddaeb34f445eea4573d0fdf913  costs-dark.png
747d3b14b7b251df0dc363ceb347fa361f4ac5ce77efb87f78c83ba56b7dee78  dispatch-dark.png
1a5e44a99a5c4e4a060181a253e2be31a676df33350c18c9ec5f5ceb0709d7ad  dolt-list-dark.png
cda87c1ea3e9d62281937c5ce0c128ca68cd3d381c0df0c5e5c01686259468da  events-dark.png
bfacaf4770b4d8e732528cadff3af2011b4825104a0752e751b4306e46e237f5  health-dark.png
4012f1e48137509808c41c31766b7bb8d69254fc7ce1f017ee51ed674decc8c1  lighter-dark.png
1d7420720d4705972670bb67170f01a901667e61da6e63600d902c18f60998e0  mail-inbox-light.png
20443a0176a8fecf51aebda3591f2725084e523eaa9b3c1ca9286983601de17a  order-list-light.png
c5473490b364351b99108af90fcc9d1a56ce8b02d96d62f0fddef2b6883793df  remote-cities-light.png
3a0820bea4d02937e5fc4e35b2f53ddee78214c3a20019819fdcabee34efdfb3  rig-dashboard-dark.png
dffd1aef7c5ada4796da34248725206e5d7ee78bc7d72e69503750b1c1b229a5  rig-list-light.png
026593b9212534a8de61487747be67d995b28fbea8dacbb51eea41141bd9b154  runs-dark.png
11a2a44c439ed8a8d2a65e54b40e75d99bc811b5070eed41921a38916cbd58b5  session-list-dark.png
91450a0f1f019b0c77bb911f5bf49e81abb93182b04150ee0feae11a51917bc1  sling-cold-dark.png
d965361ed7e9594503a25f912c789254b2b931fb871f123c9ea28affa7631ffc  sling-formula-dark.png
525656f621dd02e3f01e23a78f691fb56ac4e793f90b473248d6166643c23b85  sling-on-dark.png
7b2fa10f4828773f0d6e68cf8e124f02fd92a4c3ad808afc483584da075c420d  sling-plain-dark.png
742bc69f990dcc45c8c041058356ad67d74117f9cdb611349ee2387662602fbb  sling-preview-dark.png
acb1fcb2f07c1abf802d5d40799b5632ab6d7a27f0362db8446b092fa264ecd7  terminal-attach-dark.png
```

## Normalization (no permitted drift)

The fixture pins role ids (`demo-<role>`) and timestamps, and the
post-render hook in `gascity-shots.el` maps residual live values to stable
tokens before export:

| Rendered value | Rule | Why it cannot be seeded |
| --- | --- | --- |
| `demo-<hash>` run-generated bead id | → `demo-role` | created by gc during the run |
| `/tmp/gascity-fixture.<hash>` | → `/tmp/gascity-fixture` | `mktemp` suffix |
| ISO-8601 timestamp | → `1970-01-01T00:00:00Z` | wall clock |
| `↻ Ns ago` header age | → `↻ 0s ago` (header-line filter) | wall clock, outside buffer text |
| `reconnecting (Ns)` | → `reconnecting (0s)` | live stream retry countdown |
| ` (exit N)` suffix | removed | present only when the child reported a status |

The header line is a `(:eval ...)` form outside the buffer text, so it is
normalized by freezing it to a literal string (`gascity-shots--normalize-header-line`)
rather than by the buffer-text rules. A late async repaint between
`screenshot-settle` and export is prevented by `gascity-shots--await-stable`,
and a queued pgtk surface resize by `gascity-shots--await-frame-resize`.

## Coverage

| ID | Status |
| --- | --- |
| run-detail-dark | excluded |
| agent-detail-light | excluded |
| mail-thread-light | excluded |
| cockpit-dark | covered |
| cockpit-light | covered |
| agents-dark | covered |
| agents-tree-light | covered |
| runs-dark | covered |
| events-dark | covered |
| health-dark | covered |
| rig-dashboard-dark | covered |
| rig-list-light | covered |
| session-list-dark | covered |
| convoy-list-dark | covered |
| dolt-list-dark | covered |
| lighter-dark | covered |
| costs-dark | covered |
| bookmarks-dark | covered |
| cities-light | covered |
| remote-cities-light | covered |
| order-list-light | covered |
| mail-inbox-light | covered |
| dispatch-dark | covered |
| sling-plain-dark | covered |
| sling-cold-dark | covered |
| sling-formula-dark | covered |
| sling-on-dark | covered |
| sling-preview-dark | covered |
| terminal-attach-dark | covered |

### Excluded views (recorded reason)

The offline fixture runs `gc init --no-start` with no controller, so it
cannot produce sessions, agents, runs, or a live mail session. The three
views below therefore error their thunks against the fixture
(`run-detail`: `Nothing to act on here`; `agent-detail`: `No session/agent
at point`; `mail-thread`: `gascity-mail-thread-id nil`). Their committed
`doc/images/*.png` are legacy captures from commit `7c23f47` and are
**not** regenerated from the fixture; the manual still embeds them. This
mirrors the plan's "no silent fake / exclude with a recorded reason" rule
and the exclusion table in `doc/screenshots/fixtures/README.md`. The
remaining 26 outputs — including the empty/degraded states the fixture can
honestly render (e.g. `agents-dark`, `session-list-dark`, the cockpit's
`controller down`) — are byte-reproducible.

`--verify` covers every image a scope actually produces; a view whose thunk
fails produces no image, so the exclusion is explicit here rather than a
faked frame.

## Protected paths untouched (AC-6)

`stat -c '%Y %n'` before and after the whole evidence run:

| Path | mtime | before == after |
| --- | --- | --- |
| `~/emacs-city` | `1791203064` | yes |
| `~/bright-lights` | `1791202982` | yes |
| repo `.beads` | `1791715559` | yes |

The fixture used a throwaway `GC_HOME`
(`/tmp/ga-1s3jv-tmp/gascity-fixture/gc-home`) and a fixture-private
`TMUX_TMPDIR`, and `TMUX` was unset, so the Cities view and the
terminal-attach shot never read the developer's own cities or tmux
sessions. `fixture.sh --verify` additionally asserts the repo `.beads`
mtime is unchanged across its own run.

## Remaining risks

- **Three views are not fixture-reproducible** (above). Regenerating them
  requires seeding sessions/agents/runs from a deterministic controller
  run; until then their images are stale relative to the current UI. This
  is the largest gap to AC-5 and is called out rather than papered over.
- **`--verify` tolerates a thunk that produces no image.** Coverage is
  every file a scope actually writes, so an excluded/broken view can pass
  verify silently unless, as here, the exclusion is enumerated.
- **The fixed fixture path is not concurrency-safe.** This pass avoided it
  with a private `TMPDIR`; two default-path runs at once still collide
  (recorded in `fixtures/README.md`).
- **The graphical stack is required** for the image evidence; CI without
  sway/GUI Emacs can only run `--self-test`, `--list-scope`, and the
  fixture shell checks, which guard the scope/isolation logic but not the
  pixels.

## Verdict

The fixture pipeline reproduces every producible committed image byte for
byte across two runs, the subset-isolation guarantee holds, the fixture is
throwaway and role-addressed, and no live store was touched. Three views
are excluded with recorded reasons.

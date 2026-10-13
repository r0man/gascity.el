---
schema: gc.build.implementation-summary.v1
workflow:
  id: ga-w76j9
  formula: do-work
methodology:
  pack: gascity
  name: build-basic
producer:
  formula: do-work
  stage: implement
  attempt: 1
status: approved
trace:
  upstream:
    - path: beads/ga-6h1k7
      hash: bead:ga-6h1k7
      title: "W3 — Manual info_TEXINFOS and HTML/PDF integration"
      ids:
        - REQ-005
        - REQ-011
        - REQ-015
    - path: plans/gnu-toolchain/requirements.md
      hash: sha256:d33381ad53e17004047443340dc4cd0e810c67d22254049f332e4abd8c6e8a36
      title: "Approved requirements (REQ-001..REQ-023, AC-1..AC-10)"
    - path: plans/gnu-toolchain/implementation-plan.md
      hash: sha256:46b9ef86fb207bd417b22c825421ff5cf846da9fac5742864296baaeba3ad292
      title: "Approved implementation plan (W3, decisions D4/D5, §4)"
    - path: plans/gnu-toolchain/decomposition.md
      hash: sha256:b1eb1eee2d7310ed63f9348eba55e1219b11f6ac2e44c815a0ad7c28e82f3b58
      title: "Approved decomposition (W3 depends on W1; W4 depends on W3)"
    - path: doc/Makefile
      hash: git:47dc0c572689a04d3b93c1ba523ffc6f5be2ba78
      title: "Standalone manual build removed; folded into info_TEXINFOS"
    - path: doc/Makefile.am
      hash: sha256:8c50f7f2a06e341c15ad633265bcb53c962f1a1a8eb6f6c04234c8ef2676d179
      title: "info_TEXINFOS integration, inlined-CSS/lightbox HTML, pdf"
    - path: doc/generated/keys.texi
      hash: sha256:64f810043ca75d1cd3ecbe184ca1e5b3f3a8567ce58f0d73a537a86e1c7a4d58
      title: "Tracked generated key-registry include (W4 fills it)"
    - path: doc/generated/commands.texi
      hash: sha256:8ae6a5bd2a369e6ac4b044c8e51f55cb6fb3c0eb76bd316f788cd14b99a22d62
      title: "Tracked generated command/dispatch include (W4 fills it)"
  coverage:
    - id: REQ-005
      status: covered
    - id: REQ-011
      status: covered
    - id: REQ-015
      status: covered
---

# Implementation Summary: W3 — Manual `info_TEXINFOS` and HTML/PDF integration (source anchor ga-6h1k7)

## Summary

Folded the manual build into automake's `info_TEXINFOS` machinery (plan W3,
requirements REQ-005/REQ-011/REQ-015). The standalone `doc/Makefile` is gone
in favour of `doc/Makefile.am`, which declares `info_TEXINFOS = gascity.texi`
and an explicit `gascity_TEXINFOS` list (stylesheet, lightbox, generated
Texinfo includes, screenshots) so `make`, `make info`, `make install` and
`make dist` handle the manual without a separate Makefile.

`make html` keeps the old recipe's exact output: a split, multi-page,
self-contained manual. The stylesheet is inlined into every page through
`--css-include`, `lightbox.js` is inlined through the `PRE_BODY_CLOSE`
customization variable, and the raw `<img>` screenshots (which makeinfo does
not copy) are mirrored into `doc/gascity.html/images/`. `make pdf` keeps the
`texi2pdf` invocation through automake's built-in `.texi.pdf` rule, and
`make -C doc` still works because automake generates `doc/Makefile`.

The task's generated includes are tracked placeholders
(`doc/generated/keys.texi`, `doc/generated/commands.texi`) listed in
`gascity_TEXINFOS`; W4 owns their generator, drift gate and `@include` in
`gascity.texi`.

## Intended Behavior

- **`info_TEXINFOS` (REQ-011).** `doc/Makefile.am` is the single manual
  definition. `make info` builds `gascity.info`; automake's `.texi.pdf` rule
  builds `gascity.pdf`; `make dist` ships `doc/gascity.texi` plus every file
  in `gascity_TEXINFOS` and the whole `doc/screenshots/` tree. The standalone
  `doc/Makefile` is removed and no longer referenced.
- **Self-contained HTML (REQ-015).** `AM_MAKEINFOHTMLFLAGS` adds
  `--css-include=$(srcdir)/manual.css` and
  `--set-customization-variable "PRE_BODY_CLOSE=<script>$(cat
  $(srcdir)/lightbox.js)</script>"` to automake's HTML rule. An
  `html-local` hook, wired by automake as a prerequisite of `html-am`, runs
  after `gascity.html` is built and copies `$(srcdir)/images` into
  `doc/gascity.html/images/`. The result is a split directory of per-node
  pages, an inlined `<style>` (no external stylesheet link) and a working
  lightbox.
- **Wiring/recursion (REQ-005).** `SUBDIRS = doc` in the top-level
  `Makefile.am` means `make html`, `make pdf`, `make info` and `make dist`
  work from the repository root; `make -C doc` works on the generated
  `doc/Makefile`.
- **Generated includes (REQ-011/REQ-015).** `generated/keys.texi` and
  `generated/commands.texi` are tracked artifacts listed in
  `gascity_TEXINFOS` and distributed by `make dist`, ready for W4's
  generator to replace without further `Makefile.am` changes.

## Changed Files

- `doc/Makefile.am` (modified) — added `AM_MAKEINFOHTMLFLAGS` (inlined CSS +
  lightbox), the `html-local` image-copy hook, the `generated/keys.texi` and
  `generated/commands.texi` entries, and kept `EXTRA_DIST = $(gascity_TEXINFOS)
  screenshots`. Documentation comment explains the HTML override.
- `doc/generated/keys.texi` (new) — tracked generated key-registry include.
- `doc/generated/commands.texi` (new) — tracked generated command/dispatch
  include.
- `doc/Makefile` — already deleted by W1's autotools skeleton; verified absent
  from the tree and from the `make dist` tarball.
- `plans/gnu-toolchain/build/implementation-summary-ga-6h1k7.md` (new) — this
  summary.

No runtime Elisp, `gc` CLI surface, keymap, transient, or beads.el delegation
boundary is touched (REQ-020).

## Verification

First verification command (bootstrap must stay clean under automake
`-Wall -Werror`, then the manual and its HTML build):

```
$ ./autogen.sh
autoreconf: Leaving directory `.'
exit=0                       # no "warnings are treated as errors" output

$ make html                  # from the worktree root, recursing into doc
Making html in doc
makeinfo --html --css-include=./manual.css \
  --set-customization-variable "PRE_BODY_CLOSE=<script>$(cat ./lightbox.js)</script>" \
  -I . -o gascity.htp gascity.texi
rm -rf gascity.html && mv gascity.htp gascity.html
rm -rf gascity.html/images
cp -R ./images gascity.html/images
exit=0
```

Final proof commands and observed results:

```
$ grep -c 'rel="stylesheet"' doc/gascity.html/index.html
0                            # stylesheet is inlined, not linked

$ grep -c 'function buildOverlay' doc/gascity.html/index.html
1                            # lightbox.js inlined at PRE_BODY_CLOSE

$ ls doc/gascity.html/images | wc -l
52                           # all screenshots copied into the split tree

$ make -C doc pdf            # with a complete TeX Live on PATH
Output written on gascity.pdf (73 pages, 633587 bytes).
exit=0

$ make dist
exit=0
$ tar tzf gascity-0.1.0.tar.gz | grep -E 'doc/(gascity\.texi|generated/|images/)' | wc -l
# 56: doc/gascity.texi, doc/generated/{keys,commands}.texi, doc/images/*.png
$ tar tzf gascity-0.1.0.tar.gz | grep -cE 'doc/Makefile$'
0                            # standalone Makefile no longer shipped
```

Environment caveat: in the bare sandbox this worktree runs in, no complete
TeX Live is installed, so `make pdf` reached `texi2pdf` and failed at the TeX
step with `epsf.tex not found` (plan R3 keeps `texi2pdf` optional). Supplying
a stock `epsf.tex` on `TEXINPUTS` plus the profile `TEXMFCNF` made the exact
same recipe produce a 73-page PDF, so the target itself is correct and only
the missing TeX package blocked the unqualified run.

### Coverage

| ID | Status |
| --- | --- |
| REQ-005 | covered |
| REQ-011 | covered |
| REQ-015 | covered |

## Remaining Risks

- **`make pdf` depends on a TeX installation.** The recipe is wired exactly as
  before (`texi2pdf` through automake), but a TeX Live with `epsf.tex` is
  required; the sandbox lacked it. W9/CI must keep `texinfo`/TeX provisioning
  documented but out of the default `all` build.
- **Generated includes are placeholders.** `doc/generated/*.texi` currently
  only carry a header comment and are not yet `@include`d by `gascity.texi`.
  W4 must emit real content, add the `@include`s, and gate drift; this does
  not block the HTML/PDF/dist paths here.
- **Out-of-tree/VPATH builds.** The HTML/PDF rules use `$(srcdir)` for inputs
  and write outputs to the build directory, but `make distcheck` was not
  exercised, so a VPATH regression is not ruled out.
- **Automake version surface.** The `html-local` hook and
  `AM_MAKEINFOHTMLFLAGS` behavior were verified with automake 1.17; older
  automake releases use the same documented hook and variable.

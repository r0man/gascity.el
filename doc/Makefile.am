## doc/Makefile.am --- build and install the gascity manual
##
## The manual is built by automake's `info_TEXINFOS' machinery, so
## `make', `make info', `make install' and `make dist' all handle it
## without a standalone Makefile.  The stylesheet, lightbox, screenshots
## and generated Texinfo includes are part of the distribution so a
## tarball builds the manual as shipped.
##
## HTML and PDF are explicit rules that replace automake's plain
## `.texi.html'/`.texi.pdf' suffix rules: the shipped manual must be a
## self-contained, split multi-page tree (the stylesheet inlined by
## `--css-include', the lightbox inlined through the PRE_BODY_CLOSE
## customization variable, and the screenshots --- emitted as raw <img>,
## which makeinfo does not copy --- mirrored into the output directory),
## and the PDF keeps the standalone Makefile's `texi2pdf' invocation.
##
## `make html' and `make pdf' at the top level recurse here through
## `SUBDIRS = doc' in the top-level Makefile.am.
##
## The screenshot list is explicit rather than `$(wildcard ...)': the
## latter is a GNU make extension that `AM_INIT_AUTOMAKE([-Wall -Werror])'
## rejects.
##
## SPDX-License-Identifier: GPL-3.0-or-later

info_TEXINFOS = gascity.texi

## The generated tables (REQ-014, D4) are committed includes emitted by
## doc/generate-tables.el; a clean checkout builds the manual from them.
## The wildcard keeps this file valid before the generator first runs.
gascity_generated_TEXINFOS = $(wildcard $(srcdir)/generated/*.texi)

gascity_TEXINFOS = \
  manual.css \
  lightbox.js \
  $(gascity_generated_TEXINFOS) \
  images/agents-dark-thumb.png \
  images/agents-dark.png \
  images/agents-tree-light-thumb.png \
  images/agents-tree-light.png \
  images/bookmarks-dark-thumb.png \
  images/bookmarks-dark.png \
  images/cities-light-thumb.png \
  images/cities-light.png \
  images/cockpit-dark-thumb.png \
  images/cockpit-dark.png \
  images/cockpit-light-thumb.png \
  images/cockpit-light.png \
  images/convoy-list-dark-thumb.png \
  images/convoy-list-dark.png \
  images/costs-dark-thumb.png \
  images/costs-dark.png \
  images/dispatch-dark-thumb.png \
  images/dispatch-dark.png \
  images/dolt-list-dark-thumb.png \
  images/dolt-list-dark.png \
  images/events-dark-thumb.png \
  images/events-dark.png \
  images/health-dark-thumb.png \
  images/health-dark.png \
  images/lighter-dark-thumb.png \
  images/lighter-dark.png \
  images/mail-inbox-light-thumb.png \
  images/mail-inbox-light.png \
  images/order-list-light-thumb.png \
  images/order-list-light.png \
  images/remote-cities-light-thumb.png \
  images/remote-cities-light.png \
  images/rig-dashboard-dark-thumb.png \
  images/rig-dashboard-dark.png \
  images/rig-list-light-thumb.png \
  images/rig-list-light.png \
  images/runs-dark-thumb.png \
  images/runs-dark.png \
  images/session-list-dark-thumb.png \
  images/session-list-dark.png \
  images/sling-cold-dark-thumb.png \
  images/sling-cold-dark.png \
  images/sling-formula-dark-thumb.png \
  images/sling-formula-dark.png \
  images/sling-on-dark-thumb.png \
  images/sling-on-dark.png \
  images/sling-plain-dark-thumb.png \
  images/sling-plain-dark.png \
  images/sling-preview-dark-thumb.png \
  images/sling-preview-dark.png \
  images/terminal-attach-dark-thumb.png \
  images/terminal-attach-dark.png

EXTRA_DIST = $(gascity_TEXINFOS) screenshots

## Split, multi-page HTML with the stylesheet and lightbox inlined into
## every page.  Passing `-o NAME' with no `.html' suffix makes makeinfo
## emit a directory of per-node pages (index.html plus one file per
## node), so `rm -rf' first and mirror the raw screenshot images in
## afterwards.  The shell command substitution lands the lightbox as a
## single argument, so its quotes and `$' characters need no escaping.
gascity.html: gascity.texi $(gascity_TEXINFOS)
	rm -rf $@
	$(MAKEINFO) --html --css-include=$(srcdir)/manual.css \
	  --set-customization-variable "PRE_BODY_CLOSE=<script>$$(cat $(srcdir)/lightbox.js)</script>" \
	  -I $(srcdir) -o $@ $<
	cp -R $(srcdir)/images $@/images

## `texi2pdf' (a thin wrapper over `texi2dvi --pdf') keeps the standalone
## Makefile's invocation; it needs a TeX installation and is therefore
## not part of the default build.
gascity.pdf: gascity.texi $(gascity_TEXINFOS)
	$(TEXI2PDF) -I $(srcdir) $(srcdir)/gascity.texi

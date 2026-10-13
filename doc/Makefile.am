## doc/Makefile.am --- build and install the gascity manual
##
## The manual is built by automake's `info_TEXINFOS' machinery, so
## `make', `make info', `make install' and `make dist' all handle it
## without a standalone Makefile.  The stylesheet, lightbox, screenshots
## and generated Texinfo includes are part of the distribution so a
## tarball builds the manual as shipped.
##
## The HTML recipe stays automake's built-in `.texi.html' rule, extended
## through AM_MAKEINFOHTMLFLAGS so the shipped manual is a self-contained,
## split multi-page tree: the stylesheet is inlined by `--css-include' and
## the lightbox script through the PRE_BODY_CLOSE customization variable.
## The `html-local' hook then mirrors the raw screenshot images into the
## output directory, because makeinfo emits them as <img> without copying
## them.  The PDF keeps automake's built-in `.texi.pdf' rule, the same
## `texi2pdf' invocation the standalone Makefile used.
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
## doc/generate-tables.el; a clean checkout builds the manual from them
## and a normal `make' never rewrites them.  `make check-doc-drift'
## (wired into `make check') diffs a fresh generation against these
## tracked copies; `make regen-doc-tables' rewrites them.
gascity_TEXINFOS = \
  manual.css \
  lightbox.js \
  generated/keys.texi \
  generated/commands.texi \
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

EXTRA_DIST = $(gascity_TEXINFOS) generate-tables.el screenshots

## Inline the stylesheet and the lightbox into every HTML page.  Automake
## passes these flags to `$(MAKEINFO) --html' for its built-in
## `.texi.html' rule; the shell command substitution lands the lightbox
## as a single `--set-customization-variable' argument, so its quotes and
## `$' characters need no escaping.
AM_MAKEINFOHTMLFLAGS = \
  --css-include=$(srcdir)/manual.css \
  --set-customization-variable "PRE_BODY_CLOSE=<script>$$(cat $(srcdir)/lightbox.js)</script>"

## `makeinfo' does not copy the screenshot images the manual references as
## raw <img>, so mirror doc/images/ into the built HTML tree once it
## exists.  Automake wires this hook into the `html' target through
## `html-am'.
html-local: gascity.html
	rm -rf gascity.html/images
	cp -R $(srcdir)/images gascity.html/images

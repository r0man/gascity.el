## doc/Makefile.am --- build and install the gascity manual
##
## The manual is built by automake's `info_TEXINFOS' machinery, so
## `make', `make info', `make install' and `make dist' all handle it
## without a standalone Makefile.  The HTML and PDF targets come from
## automake as well; the stylesheet, lightbox and screenshots are part
## of the distribution so a tarball builds the manual as shipped.
##
## The screenshot list is explicit rather than `$(wildcard ...)': the
## latter is a GNU make extension that `AM_INIT_AUTOMAKE([-Wall -Werror])'
## rejects.
##
## SPDX-License-Identifier: GPL-3.0-or-later

info_TEXINFOS = gascity.texi

gascity_TEXINFOS = \
  manual.css \
  lightbox.js \
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

# doc/Makefile --- Build the gascity.el manual.
#
# gascity.el uses Eldev, not autotools, so the manual is built by this
# small standalone Makefile rather than by `info_TEXINFOS'.  It mirrors
# the two outputs of a Guix-style Texinfo manual:
#
#   make            Info + styled multi-page HTML
#   make info       gascity.info
#   make html       gascity.html/ (one page per node, manual.css inlined)
#   make pdf        gascity.pdf (needs a TeX installation)
#   make screenshots  regenerate doc/images/ from the live city
#   make clean      remove built manual outputs
#
# SPDX-License-Identifier: GPL-3.0-or-later

PACKAGE  = gascity
TEXI     = $(PACKAGE).texi
MAKEINFO = makeinfo
TEXI2PDF = texi2pdf

.PHONY: all info html pdf screenshots clean

all: info html

info: $(PACKAGE).info
$(PACKAGE).info: $(TEXI)
	$(MAKEINFO) -I . -o $@ $<

# Split, multi-page HTML with the stylesheet inlined into every page.
# `-o NAME' with no .html extension makes makeinfo emit a directory of
# per-node pages (index.html + one file per node).  The screenshots are
# emitted as raw <img> (for the lightbox), which makeinfo does not copy,
# so mirror doc/images/ into the output directory afterwards.
#
# `lightbox.js' is inlined verbatim into the bottom of every page through
# the PRE_BODY_CLOSE customization variable -- the script counterpart to
# the CSS that `--css-include' inlines into every <head> -- so the output
# stays self-contained with no external script asset to copy.  The shell
# command substitution lands the file as a single argument, so its quotes
# and `$' characters need no escaping.
html: $(PACKAGE).html
$(PACKAGE).html: $(TEXI) manual.css lightbox.js $(wildcard images/*.png)
	rm -rf $@
	$(MAKEINFO) --html --css-include=manual.css \
	  --set-customization-variable "PRE_BODY_CLOSE=<script>$$(cat lightbox.js)</script>" \
	  -I . -o $@ $<
	cp -R images $@/images

pdf: $(PACKAGE).pdf
$(PACKAGE).pdf: $(TEXI)
	$(TEXI2PDF) -I . $<

screenshots:
	./screenshots/capture.sh

clean:
	rm -rf $(PACKAGE).info $(PACKAGE).html $(PACKAGE).pdf \
	       $(PACKAGE).aux $(PACKAGE).cp $(PACKAGE).fn $(PACKAGE).ky \
	       $(PACKAGE).log $(PACKAGE).pg $(PACKAGE).toc $(PACKAGE).tp \
	       $(PACKAGE).vr $(PACKAGE).cps

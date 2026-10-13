#!/bin/sh
# autogen.sh --- bootstrap the gascity.el autotools build.
#
# Run this once after a fresh clone (or after changing configure.ac /
# Makefile.am): it regenerates `configure', `Makefile.in', the auxiliary
# scripts under build-aux/ and the m4 expansion.  Then:

#     ./configure --with-beads-dir="$HOME/workspace/beads.el"
#     make
#
# SPDX-License-Identifier: GPL-3.0-or-later
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

for tool in autoreconf autoconf automake; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "autogen.sh: $tool is required to bootstrap the build" >&2
        exit 1
    fi
done

exec autoreconf --install --force --verbose

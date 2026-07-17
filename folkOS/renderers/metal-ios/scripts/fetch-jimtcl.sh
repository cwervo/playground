#!/bin/sh -e
# Regenerates Vendor/jimsh0.c — the single-file Jim Tcl bootstrap
# amalgamation — from upstream jimtcl. Only needed to upgrade Jim;
# the generated file is committed.
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone --depth 1 https://github.com/msteveb/jimtcl.git "$tmp/jimtcl"
(cd "$tmp/jimtcl" && ./make-bootstrap-jim) > Vendor/jimsh0.c
cp "$tmp/jimtcl/LICENSE" Vendor/JIMTCL-LICENSE
echo "Vendor/jimsh0.c: $(wc -l < Vendor/jimsh0.c) lines"

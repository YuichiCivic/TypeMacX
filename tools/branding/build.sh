#!/usr/bin/env bash
# Regenerates the TypeMacX branding assets from tools/branding/render.swift.
#
#   mac/Resources/AppIcon.icns     full-color app icon (16...1024 px)
#   mac/Resources/icon.tiff        input-menu template glyph (16 px @1x + @2x)
#   tools/branding/out/TypeMacX-1024.png   1024 px icon for the landing page
#
# SWIFTC can point at a specific toolchain, e.g.
#   SWIFTC=~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/usr/bin/swiftc tools/branding/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/typemacx-branding.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

"$SWIFTC" -O -sdk "$(xcrun --show-sdk-path)" "$HERE/render.swift" -o "$WORK/render"
"$WORK/render" "$WORK"

iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/mac/Resources/AppIcon.icns"
# tiffutil -cathidpicheck makes the 32 px image the @2x representation of the 16 px one
# (it recognizes it by the "@2x" file name), so NSImage sees one 16 pt image with two reps.
tiffutil -cathidpicheck "$WORK/glyph.png" "$WORK/glyph@2x.png" -out "$ROOT/mac/Resources/icon.tiff" >/dev/null

mkdir -p "$HERE/out"
cp "$WORK/TypeMacX-1024.png" "$HERE/out/TypeMacX-1024.png"
cp "$WORK/glyph.png" "$HERE/out/menu-glyph-16.png"
cp "$WORK/glyph@2x.png" "$HERE/out/menu-glyph-32.png"
echo "branding assets updated"

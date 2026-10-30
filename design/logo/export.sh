#!/bin/sh
# Renders the app icon and the menu bar glyph into Wisp's asset catalog.
# Needs rsvg-convert (brew install librsvg). The output is committed, so builds don't need this.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
assets="$here/../../Wisp/Resources/Assets.xcassets"
icons="$assets/AppIcon.appiconset"
glyph="$assets/MenuGlyph.imageset"
mkdir -p "$icons" "$glyph"

for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" "$here/wisp-icon.svg" -o "$icons/icon_${size}.png"
  rsvg-convert -w $((size * 2)) -h $((size * 2)) "$here/wisp-icon.svg" -o "$icons/icon_${size}@2x.png"
done
rsvg-convert -f pdf "$here/wisp-glyph.svg" -o "$glyph/wisp-glyph.pdf"
echo "Exported to $assets"

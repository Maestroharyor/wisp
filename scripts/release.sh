#!/bin/sh
# Builds a universal Release of Wisp and packages it as a DMG for GitHub Releases.
#
#   scripts/release.sh                 sign with "Wisp Dev" (or ad-hoc); people must
#                                      click "Open Anyway" in System Settings once
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" \
#   NOTARY_PROFILE=wisp scripts/release.sh
#                                      sign with a Developer ID and notarise; opens
#                                      normally everywhere
#
# NOTARY_PROFILE names credentials saved once with:
#   xcrun notarytool store-credentials wisp --apple-id you@example.com --team-id TEAMID
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/.*MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' project.yml | head -1)
out=build/release
app="$out/derived/Build/Products/Release/Wisp.app"
dmg="$out/Wisp-$version.dmg"

if [ -n "${DEVELOPER_ID:-}" ]; then
  identity=$DEVELOPER_ID
  # Notarisation needs a secure timestamp on every signature.
  flags="--timestamp"
elif security find-identity -p codesigning | grep -q '"Wisp Dev"'; then
  identity="Wisp Dev"
  flags=""
else
  identity="-"
  flags=""
fi
echo "Wisp $version, signing as: $identity"

rm -rf "$out"
xcodegen generate --quiet
xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Release -derivedDataPath "$out/derived" \
  -destination "generic/platform=macOS" -quiet \
  CODE_SIGN_IDENTITY="$identity" OTHER_CODE_SIGN_FLAGS="$flags" build
codesign --verify --strict --verbose=1 "$app"

staging="$out/dmg"
mkdir -p "$staging"
ditto "$app" "$staging/Wisp.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Wisp" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
rm -rf "$staging"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --sign "$identity" --timestamp "$dmg"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
  else
    echo "warning: NOTARY_PROFILE not set; the DMG is signed but not notarised"
  fi
else
  echo "warning: no Developer ID; first launch needs System Settings > Privacy & Security > Open Anyway"
fi

sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
echo "$sha  Wisp-$version.dmg" >"$dmg.sha256"
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" scripts/wisp.rb.template >"$out/wisp.rb"

echo
echo "DMG:    $dmg"
echo "SHA256: $sha"
echo "Cask:   $out/wisp.rb (for a personal tap, e.g. Maestroharyor/homebrew-tap)"

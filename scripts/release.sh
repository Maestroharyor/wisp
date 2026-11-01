#!/bin/sh
# Builds a universal Release of Wisp: a DMG for first installs, a zip for Sparkle
# updates, checksums, the Homebrew cask and (when a Sparkle key is given) appcast.xml.
#
#   scripts/release.sh
#       Signs with the self-signed "Wisp Dev" certificate (or ad-hoc without it). No
#       hardened runtime, so Sparkle.framework loads. First launch needs "Open Anyway".
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=wisp scripts/release.sh
#       Signs with a Developer ID, turns the hardened runtime on and notarises.
#
# Sparkle (optional): SPARKLE_BIN points at the folder holding sign_update, and the
# private EdDSA key comes from SPARKLE_PRIVATE_KEY (CI) or the login Keychain account
# named by SPARKLE_KEYCHAIN_ACCOUNT (local).
#
# NOTARY_PROFILE names credentials saved once with:
#   xcrun notarytool store-credentials wisp --apple-id you@example.com --team-id TEAMID
set -eu
cd "$(dirname "$0")/.."

version=$(sed -n 's/.*MARKETING_VERSION: *"\{0,1\}\([0-9][^" ]*\)"\{0,1\}.*/\1/p' project.yml | head -1)

# CFBundleVersion must grow with every release for Sparkle. Same formula as
# WispCore/BuildNumber.swift: major * 10000 + minor * 100 + patch.
build=$(printf '%s\n' "$version" | awk -F. 'NF == 3 && $2 < 100 && $3 < 100 && $0 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ {
  print $1 * 10000 + $2 * 100 + $3 }')
if [ -z "$build" ]; then
  echo "error: MARKETING_VERSION '$version' is not x.y.z with minor and patch under 100" >&2
  exit 1
fi

out=build/release
app="$out/derived/Build/Products/Release/Wisp.app"
dmg="$out/Wisp-$version.dmg"
zip="$out/Wisp-$version.zip"

if [ -n "${DEVELOPER_ID:-}" ]; then
  identity=$DEVELOPER_ID
  # Notarisation needs the hardened runtime and a secure timestamp on every signature.
  hardened=YES
  flags="--timestamp"
elif security find-identity -p codesigning | grep -q '"Wisp Dev"'; then
  identity="Wisp Dev"
  hardened=NO
  flags=""
else
  identity="-"
  hardened=NO
  flags=""
fi
echo "Wisp $version ($build), signing as: $identity"

rm -rf "$out"
xcodegen generate --quiet
xcodebuild -project Wisp.xcodeproj -scheme Wisp -configuration Release -derivedDataPath "$out/derived" \
  -destination "generic/platform=macOS" -quiet \
  CODE_SIGN_IDENTITY="$identity" OTHER_CODE_SIGN_FLAGS="$flags" ENABLE_HARDENED_RUNTIME="$hardened" \
  CURRENT_PROJECT_VERSION="$build" build
codesign --verify --deep --strict --verbose=1 "$app"

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  # Notarise and staple the app itself, so the zip Sparkle installs is stapled too.
  ditto -c -k --keepParent "$app" "$out/notarise.zip"
  xcrun notarytool submit "$out/notarise.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  rm "$out/notarise.zip"
fi

ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"

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

for file in "$dmg" "$zip"; do
  name=$(basename "$file")
  echo "$(shasum -a 256 "$file" | cut -d' ' -f1)  $name" >"$file.sha256"
done
sha=$(cut -d' ' -f1 "$dmg.sha256")
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" scripts/wisp.rb.template >"$out/wisp.rb"

if [ -n "${SPARKLE_BIN:-}" ]; then
  if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    signature=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/sign_update" --ed-key-file - -p "$zip")
  elif [ -n "${SPARKLE_KEYCHAIN_ACCOUNT:-}" ]; then
    signature=$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_KEYCHAIN_ACCOUNT" -p "$zip")
  else
    echo "error: SPARKLE_BIN is set but neither SPARKLE_PRIVATE_KEY nor SPARKLE_KEYCHAIN_ACCOUNT is" >&2
    exit 1
  fi
  scripts/make-appcast.sh "$version" "$build" "$signature" "$(stat -f%z "$zip")" >"$out/appcast.xml"
  echo "Appcast: $out/appcast.xml"
else
  echo "warning: SPARKLE_BIN not set; no appcast.xml, so installed copies won't see this update"
fi

echo
echo "DMG:    $dmg"
echo "Zip:    $zip"
echo "Cask:   $out/wisp.rb (for a personal tap, e.g. Maestroharyor/homebrew-tap)"

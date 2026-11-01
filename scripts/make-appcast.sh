#!/bin/sh
# Prints a one-item Sparkle appcast for a release. Sparkle only needs the newest item;
# the feed is served from the latest GitHub release, so older items never matter.
#
#   scripts/make-appcast.sh <version> <build> <edSignature> <length> > appcast.xml
#
# WISP_NOTES_HTML names an HTML file with the release notes to show in Sparkle's
# update window; without it the window loads the GitHub release page.
# WISP_DOWNLOAD_BASE overrides where the zip is downloaded from (for local tests).
set -eu

version=$1
build=$2
signature=$3
length=$4
repo=https://github.com/Maestroharyor/wisp
base=${WISP_DOWNLOAD_BASE:-$repo/releases/download/v$version}
date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
page=$repo/releases/tag/v$version

if [ -n "${WISP_NOTES_HTML:-}" ]; then
  notes="<description><![CDATA[$(sed 's/]]>/]]]]><![CDATA[>/g' "$WISP_NOTES_HTML")]]></description>
      <sparkle:fullReleaseNotesLink>$page</sparkle:fullReleaseNotesLink>"
else
  notes="<sparkle:releaseNotesLink>$page</sparkle:releaseNotesLink>"
fi

cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Wisp</title>
    <link>$repo</link>
    <item>
      <title>Wisp $version</title>
      <pubDate>$date</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      $notes
      <enclosure url="$base/Wisp-$version.zip" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
EOF

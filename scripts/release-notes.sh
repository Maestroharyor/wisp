#!/bin/bash
# Prints the HTML release notes for Sparkle's update window for a tag, built from the
# "Release note" line of each pull request merged since the previous tag.
# Usage: scripts/release-notes.sh v0.1.3   (needs gh, jq, swiftc and the full git history)
set -euo pipefail

tag=$1
version=${tag#v}
repo=${GITHUB_REPOSITORY:-Maestroharyor/wisp}
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The first release has no previous tag; then every commit up to the tag counts.
if previous=$(git -C "$root" describe --tags --abbrev=0 "$tag^" 2>/dev/null); then
  range="$previous..$tag"
else
  range=$tag
fi

# Squash merges end their subject with "(#123)".
git -C "$root" log "$range" --format=%s | sed -n 's/.*(#\([0-9][0-9]*\))$/\1/p' |
  while read -r number; do
    gh pr view "$number" -R "$repo" --json title,body
  done | jq -s . > "$work/pulls.json"

swiftc -O -o "$work/release-notes" "$root/scripts/release-notes/main.swift" "$root/WispCore/ReleaseNotes.swift"
"$work/release-notes" "$version" "https://github.com/$repo/releases/tag/$tag" < "$work/pulls.json"

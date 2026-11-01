#!/bin/sh
# commit-msg hook: the first line must be a conventional commit, e.g.
# "feat: add a shelf size setting" or "fix(media)!: drop the old player".
# Merge and revert messages that git writes itself are allowed.
set -eu

subject=$(sed -n '/^[^#]/{p;q;}' "$1")

case "$subject" in
  Merge\ * | Revert\ * | fixup!\ * | squash!\ *) exit 0 ;;
esac

types='feat|fix|docs|refactor|test|chore|perf|ci|build|revert|style'
if printf '%s\n' "$subject" | grep -Eq "^($types)(\([a-z0-9._/-]+\))?!?: [^ ]"; then
  exit 0
fi

cat >&2 <<EOF
Commit message must start with a conventional type, for example:
  feat: add a shelf size setting
  fix(media): keep artwork when the track changes
Types: ${types}. Add ! before the colon for a breaking change.
Got: ${subject}
EOF
exit 1

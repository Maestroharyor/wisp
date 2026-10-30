<!--
The PR title becomes the squash commit on main, and release-please reads it to pick the
next version. Use a conventional title: "feat: ...", "fix: ...", "docs: ...", and add "!"
for a breaking change ("feat!: ..."). The pr-title check enforces this.
-->

## Summary

<!-- What this changes and why, in a few sentences. Link the issue if there is one. -->

## Type

- [ ] feat (new behaviour people will notice)
- [ ] fix (a bug)
- [ ] refactor or perf (no behaviour change)
- [ ] docs
- [ ] chore, ci or build

## What changed

<!-- The main changes, file or feature by feature. -->

-

## How it was tested

- [ ] `make lint`
- [ ] `make build` (no warnings)
- [ ] `make test` (count: )
- [ ] Checked in the running app (`make run`):

<!-- What you tried by hand, and anything you could not check. -->

## Screenshots

<!-- For UI changes: before and after, or a short recording. Delete if not UI. -->

## Release note

<!-- One line for the changelog, written for people who use Wisp. "None" for internal changes. -->

## Checklist

- [ ] The PR title is a conventional commit
- [ ] No em dashes in UI copy, docs or comments
- [ ] No new dependency, private API or permission without agreement first
- [ ] README, PLAN.md and docs updated where behaviour changed
- [ ] Anything skipped, stubbed or hardcoded is listed below

### Skipped, stubbed or hardcoded

<!-- "Nothing" if so. -->

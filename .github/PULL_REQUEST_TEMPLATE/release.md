<!--
Checklist for release-please's "chore(main): release x.y.z" PR. release-please writes its
own description; paste this below it, or open a PR with ?template=release.md.
-->

## Before merging the release PR

- [ ] The version bump is what I expect (feat bumps the minor below 1.0, fix the patch, "!" for breaking)
- [ ] CHANGELOG.md reads well for people who use Wisp; reword PR titles on main if not
- [ ] `project.yml` MARKETING_VERSION matches the new version
- [ ] CI is green on this PR (test and pr-title)
- [ ] Secrets are still set: RELEASE_PLEASE_TOKEN, WISP_DEV_P12, WISP_DEV_P12_PASSWORD, SPARKLE_PRIVATE_KEY
- [ ] RELEASE_PLEASE_TOKEN does not expire within the next month

## After merging

- [ ] The Release workflow finished and the release is published (not a draft)
- [ ] The release has the DMG, the zip, both .sha256 files, appcast.xml and wisp.rb
- [ ] `curl -sL https://github.com/Maestroharyor/wisp/releases/latest/download/appcast.xml` shows the new version
- [ ] An installed copy finds the update with Check for Updates…

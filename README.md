# Wisp

**The notch for people who build.** Wisp watches your coding agents from the Mac notch. Claude Code and Codex runs show beside the camera, permission prompts become an Allow or Deny card, and a click on a session brings its terminal forward. Profiles follow what you're doing, and quick toggles, widgets, a file tray and clipboard history sit one click away. Displays without a notch get a drawn notch (or a floating island).

Website: [ayomideodewale.com/wisp](https://ayomideodewale.com/wisp) · Made by [Ayomide Odewale](https://ayomideodewale.com).

## Install

Download `Wisp-<version>.dmg` from [Releases](https://github.com/Maestroharyor/wisp/releases), open it and drag Wisp to Applications.

Builds are not notarised yet, so the first launch is blocked:
1. Open Wisp once. macOS says it can't verify the developer.
2. Go to System Settings › Privacy & Security and click **Open Anyway** next to Wisp.

Or run `xattr -dr com.apple.quarantine /Applications/Wisp.app` once. A first-launch setup then walks you through Accessibility, how the shelf opens and connecting your agents.

With Homebrew, each release also carries a cask file (`wisp.rb`) for a personal tap.

## Updates

Wisp updates itself with [Sparkle](https://sparkle-project.org) from GitHub Releases.

- **Daily check.** On its second launch Wisp asks whether to check for updates automatically; you can change this in Settings › About. When on, it reads `appcast.xml` from the latest release once a day. When there's a newer version, a window shows the release notes with Install, Skip and Remind Me Later.
- **By hand.** Choose **Check for Updates…** from the menu bar icon, from the notch's right-click menu, or from Settings › About.
- **Settings › About › Updates** has two switches: check automatically, and download and install automatically. With the second on, Wisp downloads in the background and installs the next time it quits.
- **Installing.** Sparkle checks the download's EdDSA signature against the key built into Wisp, swaps the app in place and relaunches it. Updates don't need "Open Anyway".
- **Permissions are kept.** Every release is signed with the same certificate, so Accessibility and the other grants carry over. The one exception is moving to the `com.ayomideodewale.wisp` bundle ID (0.2.0): macOS ties permissions to the bundle ID, so grant them once more after that update. Your settings are copied over from the old ID automatically.

## Features

- **Coding agents in the notch**
  - Claude Code and Codex, connected from setup or Settings › Agents. Wisp edits `~/.claude/settings.json` or `~/.codex/hooks.json` and keeps a backup.
  - A pill while a session works, Done when it finishes, and Needs you when it waits.
  - Permission prompts become an Allow, Allow All or Deny card (a bar when the shelf is open), with a soft sound. Several at once queue up ("1 of 2") instead of replacing each other; prompts you leave fall back to the terminal.
  - Each project gets its own colour; each session shows its tokens and estimated cost, read from the transcript.
  - Click a session to bring its terminal or editor forward.
  - Open the Agents widget for each session's timeline, today's estimated spend, and a box to draft the next prompt and paste it into that terminal (it never presses Return for you).
- **Profiles that follow you**: saved Home layouts, start page and surface. Switch with Caps Lock + 1–9 or the notch menu. Rules switch the start page and surface automatically by front app, music or a waiting agent; a Focus rule can swap Home too.
- **Notch shell**
  - One non-activating panel per display. The black shell grows out of the notch into the shelf, like a box resizing, and shrinks back into it when it closes.
  - Opens on hover or click; Caps Lock + Space toggles it. Once open it closes when the pointer leaves, when you click elsewhere, or only with Esc and the shortcut; you choose in Settings › Notch. Right-click the notch to open any page directly.
  - Surfaces: Black, Glass (Liquid Glass) or Tinted.
  - **Themes:** Wisp violet (default), Midnight, Aurora (violet into teal), Ember, Mono or your own two colours. The glow can instead match the desktop picture or the playing album, or drift warmer at sunset and cooler at night.
  - Trackpad swipes on the notch: two fingers down opens the shelf, sideways on the music pill skips tracks.
  - Per display: notch, floating island or hidden, remembered for each screen.
  - **Position:** at the top (the notch), a top corner, the bottom or the left or right edge, for every display or one at a time. Corners sit below the menu bar and the bottom sits above the Dock; on the sides Wisp becomes a notch on its side, and live activities stand upright with the value under the icon.
- **Appearance** (its own Settings pane)
  - **Presets:** Default, Calm, Arcade, Minimal and Neon each set the whole look at once. Save your own, give each profile a look, and share looks as `.wisplook` files.
  - **Shell:** roundness, shadow, opacity, shelf size (compact, standard, roomy), glow strength and reach, grain, a slow shimmer, an outline, and the page switcher as a pill, dots or hidden.
  - **Pills and motion:** a minimal pill (an icon and a dot), the font for numbers, and what the notch does when the pointer arrives: grow, glow, wobble or nothing.
  - **Idle:** small "ears" beside the closed notch (time, date, battery, next meeting, weather or your own text), a breathing glow while something works and a glow that pulses with music (a steady beat; Wisp doesn't listen to the audio).
  - **Fun:** sound packs built from macOS sounds or your own files, confetti when a Pomodoro, a long agent run or a charge finishes, and a small flame pet that peeks out from under the notch.
- **Live activities beside the camera**
  - Volume, brightness and Caps Lock overlays that replace the system ones, with a choice of how long they stay, how many volume steps there are, and whether the bars use the theme accent.
  - Headphones: when AirPods or other Bluetooth headphones take over the sound, a pill shows them with their battery and case levels.
  - Battery: charging, unplugged, low (at a level you pick) and full.
  - Timers and Pomodoro; Now Playing from any app, including browsers. When a browser gives no album art, Wisp finds it on iTunes (only the title and artist are sent; switch it off in Settings › Live Activities).
  - Meetings: a pill while the microphone is on, named after the calendar event, with elapsed time and a mute button. A Join card appears two minutes before a call with a Zoom, Meet, Teams or Webex link.
  - Focus changes, tray count and file-action notices.
  - **Bubbles:** with more than one live activity, the extras pinch off the pill into round bubbles, one on each side, as on iPhone. Click a bubble to swap it into the pill. The first bubble can sit on either side.
- **Notifications** in the notch, with quick replies to iMessage, WhatsApp and Telegram, and the system banner hidden.
- **Shelf**
  - **Home**: up to four widgets, resizable and reorderable.
  - **Widgets**: an icon grid of every widget; click one to open it on its own.
  - Calendar shows the coming week and scrolls.
  - Widgets: Now Playing, Calendar, Timer, Pomodoro, Battery, System Stats, Weather, Notes, Quick Toggles, Shortcuts, Clipboard, Mirror, Day Progress, World Clocks, Agents and Script.
  - **Script widget**: the first lines a command of yours prints, refreshed while the widget is on screen.
  - New timers start at a length you type, such as 10, 1h30m or 90s.
  - **Tray**: drop files on the notch to keep them; each shows its type and size. Drag them out, AirDrop, transform or zip them.
  - **Drop actions**: your own tiles that run a Shortcut or a command on dropped files. Commands run directly, not through a shell; `{file}` runs once per file and `{files}` passes them all.
  - **Pocket**: shake a file mid-drag and drop targets appear by the pointer.
  - **Transform**: convert, compress, resize and combine files.
  - **Media**: the player, with synced lyrics from LRCLIB (optional) and a floating mini player.
- **Lock screen player**: while the screen is locked and music plays, a player shows where macOS allows it.
- **Clipboard history**: a bottom panel with type tabs, search and pinning. Return pastes into the app in front; concealed (password) items are skipped.
- **Settings**: a searchable sidebar with a live notch preview and a setup check that flags missing permissions. The menu bar icon can be hidden; open Wisp again to reach Settings.

## Requirements

- macOS 14 or later (Glass needs macOS 26). Developed on macOS 27 with Xcode 27.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build

```sh
make build   # generate the Xcode project and build
make test    # unit tests (WispCore)
make lint    # swift-format --strict
make run     # build and launch
make release # universal Release DMG and Sparkle zip in build/release
make hooks   # install the lefthook git hooks
```

`scripts/release.sh` builds a universal Release and writes a DMG, the zip Sparkle installs, checksums, a Homebrew cask and (with a Sparkle key) `appcast.xml`. It signs with "Wisp Dev" without the hardened runtime, or with a Developer ID plus hardened runtime and notarisation when `DEVELOPER_ID` and `NOTARY_PROFILE` are set. See the comments at the top of the script.

GitHub Actions:
- `ci.yml` lints and tests every push to `main` and every pull request (the `test` check).
- `pr-title.yml` checks that a pull request's title is a conventional commit (the `pr-title` check).
- `release.yml` runs release-please on every push to `main` and builds and publishes a release when its release PR is merged. See [Releasing](#releasing).

The app icon comes from `design/logo/wisp-icon.svg`; `design/logo/export.sh` renders it into the asset catalog.

Signing:
- Without a "Wisp Dev" code-signing certificate, builds are ad-hoc signed.
- That means macOS asks for Accessibility again after every rebuild.
- Create a self-signed "Wisp Dev" certificate in Keychain Access to keep the grant.

## Contributing

`main` is protected: every change goes through a pull request, and the `test` and `pr-title` checks must pass. Pull requests are squash merged.

1. Install the git hooks once:
   ```sh
   brew install lefthook
   make hooks
   ```
2. Work on a branch: `feat/short-description` or `fix/short-description`.
3. Commit with conventional messages (`feat: ...`, `fix: ...`, `docs: ...`).
4. Push the branch and open a pull request. The template asks for a summary, how you tested and a one-line release note.
5. Give the pull request a conventional title. Squash merging keeps only the title on `main`, and that title decides the next version: `fix:` and `feat:` bump the patch, and `!` (as in `feat!:`) marks a breaking change, which bumps the minor version.

The hooks (`lefthook.yml`):

| Hook | What it does |
|---|---|
| pre-commit | Formats the staged Swift files with swift-format, adds the fixes to the commit, then lints them with `--strict` |
| commit-msg | Rejects messages that aren't conventional commits (`scripts/check-commit-msg.sh`). Merge and revert messages pass |
| pre-push | Refuses any push to `main` (`scripts/block-main-push.sh`), then runs `make test` |

`git commit --no-verify` and `git push --no-verify` skip the hooks, but CI runs the same lint and tests, and GitHub refuses direct pushes to `main` anyway.

## Releasing

Releases come from `main` through [release-please](https://github.com/googleapis/release-please).

1. **Release PR.** Every merge to `main` updates an open "chore(main): release x.y.z" pull request. It bumps `MARKETING_VERSION` in `project.yml` and adds the merged PR titles to `CHANGELOG.md`.
2. **Version.** Below 1.0, `feat` and `fix` bump the patch (0.1.0 → 0.1.1) and `!` bumps the minor version (0.1.3 → 0.2.0). `docs`, `chore`, `ci` and `test` alone don't make a release. The first release is pinned to 0.1.0 with `release-as` in `release-please-config.json`; remove that line once v0.1.0 is out, or every release stays 0.1.0.
3. **Merge to release.** When you're ready to ship, check the release PR (there's a checklist in `.github/PULL_REQUEST_TEMPLATE/release.md`) and merge it. release-please tags `vX.Y.Z` and creates a **draft** GitHub release with the notes.
4. **Build and publish.** The `build` job in `release.yml` checks out the tag and runs `scripts/release.sh`, which signs the app and the Sparkle zip and writes `appcast.xml`. It uploads the DMG, zip, checksums, appcast and cask, and only then publishes the release, marking it Latest when it is the newest version. Installed copies find the update through `releases/latest/download/appcast.xml`, which never points at a release without its files.
5. **Re-running.** If the build fails, fix the cause and run Actions › Release › Run workflow with the tag (for example `v0.2.0`). It rebuilds and replaces the files.

The build number (`CFBundleVersion`) is `major × 10000 + minor × 100 + patch`, so 0.2.0 is 200 and 1.0.3 is 10003. Sparkle compares this number, so minor and patch stay below 100.

### Pulling a bad release

1. Stop new installs: in GitHub Releases, mark the previous good release as Latest (`gh release edit v0.2.0 --latest`), or delete the bad release. The appcast URL then points back at the good one.
2. Ship a fix as a new, higher version. Sparkle never downgrades, so people who already installed the bad build stay on it until the fix arrives.
3. Merge the fix and its release PR as usual; the new release becomes Latest again.

### Maintainer setup (once)

These secrets live in the repository settings (Settings › Secrets and variables › Actions). Run the commands yourself so keys never pass through anyone else.

1. **Signing certificate.** Export "Wisp Dev" from Keychain Access (right-click › Export, `.p12`, with a password), then:
   ```sh
   base64 -i WispDev.p12 | gh secret set WISP_DEV_P12
   gh secret set WISP_DEV_P12_PASSWORD
   ```
   Every release must use this same certificate, or installed copies lose their permissions.
2. **Sparkle key.** The EdDSA key is in your login Keychain under the account `wisp`. Its public half is `SUPublicEDKey` in `project.yml`. Get Sparkle's tools from its [releases](https://github.com/sparkle-project/Sparkle/releases) (same version as in `project.yml`), then:
   ```sh
   ./bin/generate_keys --account wisp -x sparkle-key.txt
   gh secret set SPARKLE_PRIVATE_KEY < sparkle-key.txt
   ```
   Keep a backup of `sparkle-key.txt` somewhere safe, such as a password manager, then delete the file. **If this key is lost, installed copies can never verify another update.**
3. **release-please token.** Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) for this repository only, with Contents, Pull requests and Issues set to Read and write. Then `gh secret set RELEASE_PLEASE_TOKEN`. release-please opens its PR as you, so CI runs on it; the default `GITHUB_TOKEN` would not trigger CI. Leave "Allow GitHub Actions to create and approve pull requests" off. If you give the token an expiry, set a reminder before it lapses: an expired token makes release PRs stop updating without any error you'd notice. Revoke it if it ever leaks.
4. **Notarisation (optional, later).** With a paid Apple Developer account, add `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `DEVELOPER_ID`, `APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`. The workflow then signs with the Developer ID, turns on the hardened runtime and notarises, and the first install no longer needs "Open Anyway".

**Switching to a Developer ID later:** Sparkle accepts an update signed with a new certificate as long as the EdDSA key stays the same. Change the certificate or the Sparkle key in a release, never both at once. People grant Accessibility once more after that update, because the signing identity changes.

## Permissions

| Permission | Used for |
|---|---|
| Accessibility | Caps Lock as Hyper, volume and brightness keys, pasting, hiding system banners, Lock Screen |
| Full Disk Access | Reading notifications, Messages chats and Focus status |
| Automation | Replying in Messages, Dark Mode and Empty Trash toggles, Music fallback |
| Calendars | Calendar and Day Progress widgets |
| Contacts | Photos and names on notifications |
| Camera | Mirror widget |
| Location | Weather widget (Open-Meteo, no account) |

Settings › Permissions shows each one's status, and General warns when a feature you use is missing one.

## Privacy

Wisp has no account, no analytics and no server of its own. It only goes online for these:

| Service | What's sent | When | Off switch |
|---|---|---|---|
| [LRCLIB](https://lrclib.net) | Song title, artist, album and length | Lyrics are on screen (Media page or mini player) | Settings › Live Activities › "Lyrics from LRCLIB" |
| [iTunes Search](https://performance-partners.apple.com/search-api) | Song title and artist | A song is playing and its app gave no album art | Settings › Live Activities › "Find missing album art on iTunes" |
| [Open-Meteo](https://open-meteo.com) | Your location, rounded to about 100 m | The Weather widget or ear is shown, at most every 30 minutes | Remove the Weather widget and ear |
| Apple (Core Location) | Your location, to name the town under the weather | Along with the weather | Same as above |
| Spotify | Nothing new: Wisp loads the cover from the URL the Spotify app gives it | Spotify is playing | Quit Spotify |
| GitHub | A request for `appcast.xml` | Update checks; Wisp asks before checking automatically | Settings › About › "Check for updates automatically" |

Lyrics and artwork are on by default because the Now Playing feature looks broken without them. They follow the "feature lookups" rule in [AGENTS.md](AGENTS.md): visible feature only, minimum data, public endpoint, cached, own switch, listed here. Everything else that goes online stays off until you turn it on.

## Layout

| Path | Contents |
|---|---|
| `WispCore/` | Pure logic, unit-tested: geometry, sizing, motion, the state machine, activity queue, widget grid, notifications, agent events and sessions, hook installer, profiles and context rules, settings search |
| `Wisp/App` | App entry, delegate, shared services |
| `Wisp/Notch` | Panels, controller, coordinator, notch view, nav pill, menu |
| `Wisp/Activities` | Activity model and views, notification and agent cards |
| `Wisp/Shelf` | Home, Widgets page, widgets, tray, drop tiles |
| `Wisp/Transform` | Transform window and the pocket |
| `Wisp/Clipboard` | Clipboard panel |
| `Wisp/Services` | System integrations: CoreAudio, IOKit, EventKit, notifications, Claude Code hub, camera, Shortcuts, context engine |
| `Wisp/Input` | Hyper key, hotkeys, pointer monitor |
| `Wisp/Settings` | Preferences, the Settings window and its panes (`Panes/`) |
| `Wisp/Onboarding` | First-launch setup |
| `WispAgent/` | `wisp-agent`, the Claude Code and Codex hook command that tags events with the agent and terminal and forwards them to Wisp over a Unix socket |
| `scripts/` | Release and appcast scripts, git hook scripts and the cask template |
| `design/logo/` | Icon and menu bar glyph sources |
| `WispMediaBridge/` | Objective-C library run inside `/usr/bin/perl` to read system-wide Now Playing; macOS only answers that query for Apple-signed processes |

## Credits

Made by [Ayomide Odewale](https://ayomideodewale.com). See `ACKNOWLEDGEMENTS.md` for services and inspiration.

## License

MIT. See `LICENSE` and `ACKNOWLEDGEMENTS.md`.

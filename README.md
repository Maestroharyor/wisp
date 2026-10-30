# Wisp

**The notch for people who build.** Wisp watches your coding agents from the Mac notch. Claude Code and Codex runs show beside the camera, permission prompts become an Allow or Deny card, and a click on a session brings its terminal forward. Profiles follow what you're doing, and quick toggles, widgets, a file tray and clipboard history sit one click away. Displays without a notch get a drawn notch (or a floating island).

Website: [ayomideodewale.com/wisp](https://ayomideodewale.com/wisp) · Made by [Ayomide Odewale](https://ayomideodewale.com).

## Install

Download `Wisp-<version>.dmg` from [Releases](https://github.com/Maestroharyor/wisp/releases), open it and drag Wisp to Applications.

Builds are not notarised yet, so the first launch is blocked:
1. Open Wisp once. macOS says it can't verify the developer.
2. Go to System Settings › Privacy & Security and click **Open Anyway** next to Wisp.

Or run `xattr -dr com.apple.quarantine /Applications/Wisp.app` once. A first-launch setup then walks you through Accessibility, how the shelf opens and connecting your agents.

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
make release # universal Release DMG in build/release
```

`scripts/release.sh` signs with a Developer ID and notarises when `DEVELOPER_ID` and `NOTARY_PROFILE` are set (see the script). Without them it signs with "Wisp Dev" or ad-hoc. It also writes a Homebrew cask for a personal tap.

GitHub Actions:
- `ci.yml` lints and tests every push to `main` and every pull request.
- `release.yml` runs on a `v*` tag, builds the DMG and attaches it to a GitHub release. Add the secrets listed at the top of that file to sign and notarise; without them the DMG is signed ad-hoc.

The app icon comes from `design/logo/wisp-icon.svg`; `design/logo/export.sh` renders it into the asset catalog.

Signing:
- Without a "Wisp Dev" code-signing certificate, builds are ad-hoc signed.
- That means macOS asks for Accessibility again after every rebuild.
- Create a self-signed "Wisp Dev" certificate in Keychain Access to keep the grant.

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
| `scripts/` | Release script and the cask template |
| `design/logo/` | Icon and menu bar glyph sources |
| `WispMediaBridge/` | Objective-C library run inside `/usr/bin/perl` to read system-wide Now Playing; macOS only answers that query for Apple-signed processes |

## Credits

Made by [Ayomide Odewale](https://ayomideodewale.com). See `ACKNOWLEDGEMENTS.md` for services and inspiration.

## License

MIT. See `LICENSE` and `ACKNOWLEDGEMENTS.md`.

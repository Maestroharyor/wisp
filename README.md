# Wisp

A Dynamic Island for the Mac notch, built for people who make things. Wisp turns the camera housing into a live surface: system overlays, notifications and your Claude Code sessions grow out of it, and a click opens a shelf with widgets, a file tray and clipboard history. Displays without a notch get a drawn notch (or a floating island).

Made by [Ayomide Odewale](https://ayomideodewale.com).

## Features

- **Notch shell**
  - One non-activating panel per display, morphing with tuned springs.
  - Opens on hover or click; Caps Lock + Space toggles it.
  - Surfaces: Black, Glass (Liquid Glass) or Tinted, optionally tinted with the playing album's colour.
- **Live activities beside the camera**
  - Volume, brightness and Caps Lock overlays that replace the system ones.
  - Battery: charging, unplugged, low and full.
  - Timers and Pomodoro; Now Playing from any app, including browsers.
  - Focus changes, tray count and file-action notices.
- **Notifications** in the notch, with quick replies to iMessage, WhatsApp and Telegram, and the system banner hidden.
- **Claude Code in the notch**
  - A pill while a session works, Done when it finishes, and Needs you when it waits.
  - Permission prompts become an Allow or Deny card; prompts you leave fall back to the terminal.
  - Connect or disconnect from Settings › Agents; Wisp edits `~/.claude/settings.json` and keeps a backup.
- **Shelf**
  - **Home**: up to four widgets, resizable and reorderable.
  - **Widgets**: an icon grid of every widget; click one to open it on its own.
  - Widgets: Now Playing, Calendar, Timer, Pomodoro, Battery, System Stats, Weather, Notes, Quick Toggles, Shortcuts, Clipboard, Mirror, Day Progress, World Clocks and Claude Code.
  - **Tray**: drop files on the notch to keep them, then drag them out, AirDrop or zip them.
  - **Pocket**: shake a file mid-drag and drop targets appear by the pointer.
  - **Transform**: convert, compress, resize and combine files.
- **Profiles**: saved Home layouts, start page and surface. Switch with Caps Lock + 1–9, the notch menu, or automatically by front app, music, Focus or a waiting agent.
- **Clipboard history**: a bottom panel with type tabs, search and pinning. Return pastes into the app in front; concealed (password) items are skipped.
- **Settings**: a searchable sidebar with a live notch preview and a setup check that flags missing permissions.

## Requirements

- macOS 14 or later (Glass needs macOS 26). Developed on macOS 27 with Xcode 27.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

## Build

```sh
make build   # generate the Xcode project and build
make test    # unit tests (WispCore)
make lint    # swift-format --strict
make run     # build and launch
```

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
| `WispAgent/` | `wisp-agent`, the Claude Code hook command that forwards events to Wisp over a Unix socket |
| `WispMediaBridge/` | Objective-C library run inside `/usr/bin/perl` to read system-wide Now Playing; macOS only answers that query for Apple-signed processes |

## Credits

Made by [Ayomide Odewale](https://ayomideodewale.com). See `ACKNOWLEDGEMENTS.md` for services and inspiration.

## License

MIT. See `LICENSE` and `ACKNOWLEDGEMENTS.md`.

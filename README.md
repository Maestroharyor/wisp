# Wisp

A Dynamic Island for the Mac notch. Wisp turns the camera housing into a live surface: system overlays and live activities grow out of it, and a click opens a shelf with widgets, a file tray and clipboard history. Displays without a notch get a drawn notch (or a floating island).

## Features

- **Notch shell**:
  - One non-activating panel per display; the notch morphs with measured springs.
  - Opens on hover or click.
  - Caps Lock + Space toggles it.
- **Live activities beside the camera**:
  - volume, brightness and Caps Lock overlays
  - charging, unplugged, low and full battery
  - running timers and Pomodoro
  - Now Playing from any app, including browsers (artwork and a tinted waveform)
  - tray count, and file-action notices
- **Shelf**:
  - **Home**: configurable widgets (Now Playing, Calendar, Timer, Pomodoro, Battery, System Stats, Weather, Notes), with a customise mode to add, remove and reorder them.
  - **Tray**: drop files on the notch to keep them, then drag them out again, AirDrop or zip them.
- **Clipboard history**:
  - A bottom panel with type tabs, search and pinning.
  - Return pastes into the app in front.
  - Concealed (password) items are skipped.
- **Settings**: from the menu bar icon, from right-clicking the notch, or by launching Wisp again.

## Requirements

- macOS 14 or later. Developed on macOS 27 with Xcode 27.
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
| Accessibility | Caps Lock as Hyper, volume and brightness keys, pasting from clipboard history |
| Automation (Music, Spotify) | Fallback Now Playing, only if the media bridge cannot run |
| Calendars | Calendar widget |
| Location | Weather widget (Open-Meteo, no account) |

## Layout

| Path | Contents |
|---|---|
| `WispCore/` | Pure logic, unit-tested. Covers geometry, metrics, sizing, the state machine, the activity queue, timers, clipboard history, the media-key decoder, the Now Playing parser, battery alerts, the tray list and widget maths. |
| `Wisp/App` | App entry, delegate, shared services |
| `Wisp/Notch` | Panels, controller, coordinator, notch view, motion, nav pill, menu |
| `Wisp/Activities` | Activity model, centre and views |
| `Wisp/Shelf` | Home, widgets, tray, drop tiles |
| `Wisp/Clipboard` | Clipboard panel |
| `Wisp/Services` | System integrations: CoreAudio, DisplayServices, IOKit power, AppleScript, EventKit, CoreLocation, QuickLook |
| `Wisp/Input` | Hyper key, hotkeys, pointer monitor |
| `Wisp/Settings` | Preferences and the Settings window |
| `WispMediaBridge/` | Objective-C library run inside `/usr/bin/perl` to read system-wide Now Playing; macOS only answers that query for Apple-signed processes |

## License

MIT. See `LICENSE` and `ACKNOWLEDGEMENTS.md`.

# Wisp plan and status

The status below is as of 2026-10-29. Testing approach: decision logic lives in `WispCore` and is written test-first. The app layer only wraps system APIs and SwiftUI. The current suite is 93 tests.

## Done

| Phase | Scope |
|---|---|
| N0 Shell | Panels per display; hover or click open; Hyper key (Caps Lock → F18 via hidutil, plus an event tap); Settings; launch at login |
| N0.5 Surface | Droppy-measured metrics and springs; content-driven surface sizes; drawn notch on external displays (island optional); glass edge; nav pill; right-click menu; staggered reveal; Reduce Motion |
| Live activities | Queue with priorities and expiry. Volume, brightness and Caps Lock overlays (the system HUD is suppressed). Battery events, timers, media and tray notices |
| N1 Tray | Drop tiles (Keep, AirDrop, Zip, Open); tray page with thumbnails, selection, drag-out and context menu; badge on the nav pill |
| N2 Now Playing | Any app, including browsers, via the media bridge (`WispMediaBridge`, hosted by `/usr/bin/perl`); AppleScript fallback for Music and Spotify; compact artwork plus waveform; Home widget with progress, seeking and controls |
| N4 Widgets | Calendar, Timer, Pomodoro (ruler scrubber), Battery, System Stats, Weather, Notes. Customise mode: add, remove, reorder, cancel or confirm |
| N5 Clipboard | History with de-duplication, pinning and cap; concealed types skipped; image storage; bottom panel with tabs, search, keyboard navigation and paste |

## Not done, and why

- **Notifications (N6).** macOS has no public API for reading other apps' notifications. Reading the private notification database needs Full Disk Access, and the format changes between releases. Not built.
- **Keyboard backlight overlay.** This needs the private CoreBrightness framework through Objective-C runtime calls. The keys are passed to the system instead.
- **Brightness on external displays.** This would need DDC/CI. The system handles it, and Wisp shows its overlay on the built-in display only.
- **Later:**
  - the Transform/convert window
  - lock-screen player
  - floating player and lyrics
  - AirPods card
  - VPN, call and recording activities
  - Sparkle updates

## Verify by hand

1. **Animation and shape.** Click the notch: it opens to 451 pt, the content blurs in, then the nav pill drops in. Compare against Droppy.
2. **External display.** A drawn notch sits flush with the top edge (no margin). Switch to the island style in Settings › Notch.
3. **System overlays.** Volume keys show a wing with a green bar. Brightness shows yellow. Caps Lock shows On/Off.
4. **Tray.** Drag a file from Finder onto the notch: four tiles appear. Drop on Keep, then open the Tray tab.
5. **Clipboard.** Copy a few texts, links and images, then press Caps Lock + V (or ⌥⇧⌘V).
6. **Now Playing.** Play in a browser (YouTube Music) or Music: artwork and a waveform show beside the notch.
7. **Closing.** The shelf content blurs and shrinks into the notch with the surface, and the nav pill rides up into it.
8. **Clicks outside the shelf** reach the app underneath.

# Wisp plan and status

The status below is as of 2026-10-29. Testing approach: decision logic lives in `WispCore` and is written test-first. The app layer only wraps system APIs and SwiftUI. The current suite is 250 tests. For what comes next, see `docs/REVIEW.md`.

## Done

| Phase | Scope |
|---|---|
| N0 Shell | Panels per display; hover or click open; Hyper key (Caps Lock → F18 via hidutil, plus an event tap); Settings; launch at login |
| N0.5 Surface | Metrics and springs; content-driven surface sizes; drawn notch on external displays (island optional); glass edge; nav pill; right-click menu; staggered reveal; Reduce Motion |
| Live activities | Queue with priorities and expiry. Volume, brightness and Caps Lock overlays (the system HUD is suppressed). Battery events, timers, media, Focus and tray notices |
| N1 Tray | Drop tiles (Keep, AirDrop, Zip, Open); tray page with thumbnails, selection, drag-out and context menu; the pocket; Transform window |
| N2 Now Playing | Any app, including browsers, via the media bridge (`WispMediaBridge`, hosted by `/usr/bin/perl`); AppleScript fallback for Music and Spotify |
| N4 Widgets | Home layout (up to four, resizable) and the Widgets icon grid with solo view. Now Playing, Calendar, Timer, Pomodoro, Battery, System Stats, Weather, Notes, Quick Toggles, Shortcuts, Clipboard, Mirror, Day Progress, World Clocks, Claude Code |
| N5 Clipboard | History with de-duplication, pinning and cap; concealed types skipped; image storage; bottom panel with tabs, search, keyboard navigation and paste |
| N6 Notifications | Read from the notification database (Full Disk Access); system banner hidden; replies to iMessage, WhatsApp and Telegram |
| Agent hub | `wisp-agent` hook helper, session pills, Allow/Deny cards (also inside an open shelf), hooks install/remove |
| Look and profiles | Black, Glass and Tinted surfaces in Wisp violet (album tint optional, off by default); profiles with Hyper+1–9 and context rules |
| Settings | Sidebar window with search, live preview, setup health and About |
| Agents, media and meetings | Agent timeline, daily spend, Allow All, request sound, prompt drafts pasted into the terminal; approval queue; lyrics (LRCLIB) and a mini player; meeting pill and Join card; lock screen player; scrolling week calendar; CI and release workflows |
| Identity (review A to I) | Flame icon and menu bar glyph; rounder corners (the expanding open and close stays); one violet accent; context rules keep Home; first-launch setup; Codex hooks, jump to terminal, tokens and cost, project colours; tray redesign; release script with DMG and cask |
| Activity motion and bubbles | Compact content is clipped to the growing shell and resolves out of a blur after it, contracting toward the camera on the way out; extra live activities pinch off into up to two round bubbles (gooey split and merge), and clicking one swaps it into the pill |

## Not done

- **HUD extras:** keyboard backlight (private CoreBrightness), DDC brightness and volume on external displays, AirPods card, VPN pill.
- **Screen recorder.**
- **Lock screen player:** built with public APIs only; whether macOS shows it over the lock screen is untested.
- **Distribution:** a GitHub Actions workflow that runs `scripts/release.sh` on each tag. Notarisation needs a Developer ID (the script already supports it). No Sparkle; updates go through Releases and Homebrew.

## Verify by hand

1. **Animation and shape.** Click the notch: it opens to 451 pt, the content expands out of the notch with the surface, then the nav pill settles in.
2. **External display.** A drawn notch sits flush with the top edge (no margin). Switch to the island style in Settings › Notch.
3. **System overlays.** Volume keys show a wing with a green bar. Brightness shows yellow. Caps Lock shows On/Off.
4. **Tray.** Drag a file from Finder onto the notch: four tiles appear. Drop on Keep, then open the Tray tab.
5. **Clipboard.** Copy a few texts, links and images, then press Caps Lock + V (or ⌥⇧⌘V).
6. **Now Playing.** Play in a browser (YouTube Music) or Music: artwork and a waveform show beside the notch.
7. **Closing.** The shelf content shrinks into the notch with the surface, and the nav pill rides up into it.
9. **Bubbles.** Play music, then start a timer: the music pinches off into a bubble right of the pill. Start a Claude Code prompt too: it splits off on the left. Click a bubble: it swaps into the pill.
8. **Clicks outside the shelf** reach the app underneath.

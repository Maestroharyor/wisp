# Wisp plan and status

The status below is as of 2026-11-01. Testing approach: decision logic lives in `WispCore` and is written test-first. The app layer only wraps system APIs and SwiftUI. The current suite is 519 tests. For what comes next, see `docs/REVIEW.md`.

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
| Review fixes (2026-10-30) | Drag-opened shelf closes when the drag leaves; SIGPIPE ignored; media bridge pipes cleared and read in order; Caps Lock remap undone when the tap fails; AppleScript fallback and multi-file zip moved off the main thread; notifications held during a reply; lyrics and artwork retry rules; Esc on click-opened shelves; less idle polling; tray prunes moved files; VoiceOver labels on icon buttons |
| Customisation and themes | Theme presets and custom colours, wallpaper-matched glow, outline; per-display style; HUD duration, volume steps, accent bars; battery threshold; typed default timer; bubble side; hide menu bar icon; trackpad swipes |
| Extras | Drop actions (Shortcut or command, no shell); Script widget; headphones pill with battery from `system_profiler` |
| Position | Top, top-left, top-right, bottom, left or right edge, globally or per display. Corners sit under the menu bar and bottom sits above the Dock as islands; left and right attach a notch on its side with upright pills (glyph over value) and bubbles stacked along the edge. Swipes, nav pill, hit regions and gradients follow the edge |
| Appearance | Its own Settings pane over one `Appearance` value (migrated from the old look keys). Presets (Default, Calm, Arcade, Minimal, Neon), saved looks, a look per profile, `.wisplook` import and export, reset. Roundness, shadow, opacity, shelf size (content zoom), glow strength and reach, grain, shimmer, outline width, page switcher style, minimal pill, number font, hover grow/glow/wobble with strength, idle ears, breathing and music glow (simulated beat), time-of-day accent, sound packs (macOS sounds or your files), confetti, notch pet |
| Activity motion and bubbles | Compact content is clipped to the growing shell and resolves out of a blur after it, contracting toward the camera on the way out; extra live activities pinch off into up to two round bubbles (gooey split and merge), and clicking one swaps it into the pill |

## In progress: Agent Bar

Live status for coding agents: a Claude Code `statusLine` bar in the terminal, live session data, context window %, tool activity, git branch, a `wisp` CLI and alerts. Each phase is its own PR. Phase A shipped in #12; Phase B is on `feat/agent-widget-privacy`.

| Phase | Scope | Status |
|---|---|---|
| A | Also pulled in from B at review: Code profile is one Wide Agents widget (sessions left, details right, every figure Claude Code reports); new Stats profile for System Stats, Timer and Day Progress; saved profiles and Home upgraded once when untouched. `wisp-agent statusline` (Wisp's bar by default; an existing bar is chained, never replaced; "Keep my bar" and "Off" restore it exactly). Snapshots forwarded fire-and-forget to Wisp: model, real cost, lines +/−, durations, context %. Context ring in the pill, context alert (default 80%), "Compacting…" via PreCompact/PostCompact. Versioned socket envelope (`docs/agent-protocol.md`). `GitHead` branch parsing. "Update hooks" card for existing installs | Done |
| B | Transcript (shown in Finder), today's spend with a 7-day sparkline, private mode: commands, file paths, session names, session IDs and prompt drafts hidden during calls (mic held by a call app or a browser, or in use during a calendar meeting), always, or with the eye button; approval cards hide the command until Show is pressed. Screen sharing alone has no public API, so it's covered by the eye button and Always (session cards, folder and copy ID landed in A) | Done |
| C | Opt-in tool activity: PreToolUse/PostToolUse/SubagentStop (`async` for Claude), `ToolLabel` with secret masking, pill label, most-urgent session wins the pill with a count badge | Not started |
| D | `wisp status`, `--json`, `watch`, `spend` over a `query` message; `~/.local/bin/wisp` symlink install/uninstall; per-project `DailySpend` | Not started |
| E | Alerts: long-running tool, re-nudge, daily budget (USD) at 80% and 100%. Notices only, never blocking | Not started |
| F | Codex parity: context % from rollout `token_count` (`model_context_window`), OpenAI prices for estimates, compaction and tool hooks, verified parity table | Not started |

Untested: `WispAgent/SocketSend.swift` (the helper's fire-and-forget send) has no automated test because the helper target isn't in the test bundle; it was checked by hand against Wisp Dev. Everything the helper renders is tested in `StatusBarRenderer`.

Decided against the original brief: no `ModelLimits` table (Claude Code's snapshot and Codex's rollouts both report the window size); no current-tool segment in the terminal bar (the helper is stateless); Codex gets no terminal bar (it has no external status line command, openai/codex#17827).

## Not done

- **HUD extras:** keyboard backlight (private CoreBrightness) and DDC brightness and volume on external displays both need private APIs, so they wait for a decision. VPN pill.
- **Shelf size:** done as a zoom of the shelf content; widgets keep fixed layouts rather than reflowing.
- **Screen recorder.**
- **Lock screen player:** built with public APIs only; whether macOS shows it over the lock screen is untested.
- **Distribution:** release-please keeps a release PR on `main`; merging it tags a draft release, and `release.yml` builds the DMG, the Sparkle zip and `appcast.xml`, uploads them and publishes. Wisp updates itself with Sparkle. Releases are signed with the self-signed "Wisp Dev" certificate until there's a Developer ID (the script already supports notarisation).

## Verify by hand

1. **Animation and shape.** Click the notch: it opens to 451 pt, the content expands out of the notch with the surface, then the nav pill settles in.
2. **External display.** A drawn notch sits flush with the top edge (no margin). Switch to the island style in Settings › Notch.
3. **System overlays.** Volume keys show a wing with a green bar. Brightness shows yellow. Caps Lock shows On/Off.
4. **Tray.** Drag a file from Finder onto the notch: four tiles appear. Drop on Keep, then open the Tray tab.
5. **Clipboard.** Copy a few texts, links and images, then press Caps Lock + V (or ⌥⇧⌘V).
6. **Now Playing.** Play in a browser (YouTube Music) or Music: artwork and a waveform show beside the notch.
7. **Closing.** The shelf content shrinks into the notch with the surface, and the nav pill rides up into it.
8. **Clicks outside the shelf** reach the app underneath.
9. **Bubbles.** Play music, then start a timer: the music pinches off into a bubble right of the pill. Start a Claude Code prompt too: it splits off on the left. Click a bubble: it swaps into the pill.
10. **Drag out.** Drag a file over the notch, then away without dropping: the shelf closes.
11. **Themes.** Settings › Appearance › Theme: Aurora shows violet into teal on the Tinted surface; Outline draws a rim on the open shelf.
12. **Swipes.** Two fingers down on the closed notch opens it; sideways on the music pill skips. Scrolling lists inside the open shelf never closes it.
13. **Headphones.** Connect AirPods: a pill shows them with battery levels.
14. **Position.** Settings › Notch › Position. Try each: the shelf grows out of that edge, the bottom island stays above the Dock, and on the left or right a timer shows upright (ring over time) with bubbles above and below. The menu bar stays clickable with a top-corner island.
15. **Mini player.** Drag it by its background anywhere, including onto another display; reopen it and it is where you left it.
16. **Appearance.** Settings › Appearance: each preset changes the preview and the shell together. Ears show beside the idle notch and hide behind a live activity. Try confetti. Turn on the pet and leave the Mac idle two minutes: it dozes. Export a look, change it, import it back. Give a profile a look and switch to it.

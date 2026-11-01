# Making Wisp its own thing

A review from 2026-10-29: what still ties Wisp to the app it started from, and what would make it distinct. Bugs found during the review were fixed right away (listed at the end).

## Identity

### A. An app icon

Wisp ships without one, so About and Finder show the generic placeholder.

**Proposal:** a wisp of violet smoke curling out of a black notch. A single shape that also works at 16 px in the menu bar.

### B. Its own motion and proportions

`WispCore/ShellMetrics.swift` and `WispCore/SpringTuning.swift` hold numbers measured from the original reference app, and their comments say so. The shell is the same shape, opens to the same width and moves with the same springs. Wisp feels like a re-skin until this changes.

**Proposal:** a signature "materialise" motion:
- Content condenses out of a soft blur and a slight upward drift, like smoke settling, instead of scaling up from the notch.
- Corners are rounder.
- The spring is a touch slower and softer.

Retune the metrics by eye, then rewrite the comments so they stand alone.

### C. One accent everywhere

Wisp violet is already the fallback accent. Use it for these, so a glance says "Wisp":
- selection
- progress bars
- the active nav-pill item
- toggles that are on
- the Settings icon tiles

## Positioning

### D. "The notch for people who build"

Lead the README, the GitHub description and any site with what nobody else has together:
- Claude Code sessions and approvals
- profiles that follow what you're doing
- quick toggles

File handling is table stakes; don't lead with it.

## Product

### E. Context rules are too eager

The "coding app in front" rule switches to the Code profile, which replaces Home every time the terminal comes forward.

**Proposal:**
- Context rules change only the start page and surface.
- Home changes only on a manual or Focus switch.
- Alternatively, ship that rule off by default.

### F. The agent pill hides music

The Claude Code pill outranks the music pill, so the waveform disappears for a whole run.

**Proposal:** a split pill, with the agent left of the camera and the waveform right of it.

### G. First-launch setup

A new user gets permission prompts with no context.

**Proposal:** three steps.
1. Grant Accessibility, with a live check.
2. Choose hover or click, with the preview.
3. Optionally connect Claude Code.

### H. A deeper agent hub

- Codex lifecycle hooks, now that Codex has them.
- "Jump to terminal" on a session.
- Token and cost readout from the transcript.
- A per-project colour.
- Live figures from Claude Code's status bar (real cost, model, context window, lines changed), a terminal bar of Wisp's own and compaction in the pill. Transcripts, a 7-day spend trend and a private mode that hides commands and file names during calls. The rest of the Agent Bar (tool activity, CLI, alerts, Codex parity) is tracked in `PLAN.md`.

### I. Distribution

Developer ID signing and notarisation, Sparkle updates and a Homebrew cask, so other people can install it.

## Status (2026-10-29)

Built: A (flame icon, picked from six drafts), B, C, D, E, F, G, H (all four parts) and I (release script, DMG and a cask template, no Sparkle). The tray page was also redesigned. For B, the blur-and-drift "materialise" motion was tried and dropped at Ayomide's request: the shelf keeps expanding out of the notch and closing back into it, with rounder corners and comments that stand alone. Still open from I: notarisation, which needs a paid Developer ID, and a GitHub Actions release workflow.

Since then: the agent timeline and spend, Allow All, prompt drafts, lyrics and the mini player, the meeting pill, the lock screen player (public APIs only) and the GitHub workflows.

## Still planned

From plan revision 3:
- **HUD extras:** keyboard backlight, DDC on external displays, AirPods, VPN.
- The screen recorder.

## Fixed during this review

- **Approvals while the shelf is open:** a Claude Code permission request now shows as a bar at the bottom of the open shelf. Before, nothing showed until the shelf closed.
- **Approval card in Hover mode:** moving onto the card no longer opens the shelf over its buttons.
- **"Basket" renamed to "Pocket":** that name came from the reference app. The old setting carries over.
- **Out-of-date docs:** the README, the permissions table and the plan status now match what Wisp does.

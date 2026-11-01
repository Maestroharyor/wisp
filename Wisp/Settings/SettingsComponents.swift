import AppKit
import Observation
import SwiftUI
import WispCore

extension SettingsPaneID {
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .notch: "capsule.portrait.fill"
        case .appearance: "paintpalette.fill"
        case .activities: "waveform"
        case .widgets: "square.grid.2x2.fill"
        case .profiles: "rectangle.stack.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .notifications: "bell.badge.fill"
        case .agents: "sparkle"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        // One violet family: darker for the app itself, lighter for connections.
        switch self {
        case .general, .about, .permissions: Color(red: 0.32, green: 0.27, blue: 0.62)
        case .notch, .appearance, .activities, .widgets, .profiles, .clipboard: .wispViolet
        case .notifications, .agents: Color(red: 0.6, green: 0.53, blue: 1)
        }
    }
}

/// Selection, search and setup health for the Settings window.
@MainActor
@Observable
final class SettingsModel {
    var selection: SettingsPaneID? {
        didSet { if let selection { preferences.lastSettingsPane = selection } }
    }
    var query = "" {
        didSet {
            let matches = visiblePanes
            if let selection {
                if !matches.contains(selection) { self.selection = matches.first }
            } else {
                // A search that matched nothing cleared the selection; pick one again as
                // soon as something matches, the last pane shown if it's among them.
                let last = preferences.lastSettingsPane
                self.selection = matches.contains(last) ? last : matches.first
            }
        }
    }
    private(set) var missing: [Permission] = []
    /// Every permission's status by id, read once per check and shared by the sidebar badge
    /// and the Permissions pane.
    private(set) var statuses: [String: Bool?] = [:]

    let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        selection = preferences.lastSettingsPane
        refreshHealth()
    }

    var visiblePanes: [SettingsPaneID] { SettingsIndex.panes(matching: query) }

    /// Permissions are granted in System Settings, so this is re-read while the window shows.
    func refreshHealth() {
        let now = Permission.statuses
        if now != statuses { statuses = now }
        let widgets = preferences.enabledWidgets
        let needed = SetupHealth.needed(
            notifications: preferences.notificationsEnabled,
            calendarWidgets: widgets.contains(.calendar) || widgets.contains(.dayProgress),
            mirror: widgets.contains(.mirror))
        let ids = SetupHealth.missing(granted: now, needed: needed)
        let next = ids.compactMap(Permission.init(rawValue:))
        if next != missing { missing = next }
    }
}

/// A coloured rounded square with a white symbol, as in System Settings.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(tint.gradient)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            )
    }
}

/// Title block at the top of each pane.
struct PaneHeader: View {
    let pane: SettingsPaneID

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: pane.symbol, tint: pane.tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title).font(.system(size: 20, weight: .bold))
                Text(pane.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }
}

/// Amber strip listing permissions Wisp needs, with a button to fix them.
struct HealthBanner: View {
    let missing: [Permission]
    let fix: () -> Void

    var body: some View {
        if !missing.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(missing.count == 1 ? "Wisp needs 1 permission" : "Wisp needs \(missing.count) permissions")
                        .font(.system(size: 13, weight: .semibold))
                    Text(missing.map(\.title).joined(separator: ", "))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fix", action: fix).controlSize(.small)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange.opacity(0.3)))
        }
    }
}

/// The open shelf in miniature over the real wallpaper, drawn with the notch's own
/// shape and surface so the surface style and accent look as they will.
struct NotchPreview: View {
    let preferences: Preferences
    let accent: Color
    var glow: Color?
    @State private var wallpaper: NSImage?

    var body: some View {
        let placement = preferences.placement
        ZStack(alignment: Self.alignment(for: placement)) {
            backdrop
            VStack(spacing: 8) {
                if placement == .bottom { navPill }
                shell(placement)
                if placement != .bottom { navPill }
            }
            .padding(Self.inset(for: placement))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: preferences.appearance)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: placement)
        .task { wallpaper = Self.loadWallpaper() }
    }

    private func shell(_ placement: Placement) -> some View {
        ZStack(alignment: .top) {
            SurfaceBackground(
                style: look.surface, glass: look.glassEdge, accent: accent, glow: glow, edge: placement.edge,
                intensity: look.glowIntensity, spread: look.glowSpread
            )
            .overlay {
                if look.grain != .off { GrainTexture().opacity(look.grain.opacity) }
            }
            .opacity(look.surface == .glass ? 1 : look.opacity)
            .clipShape(PreviewShellShape(placement: placement, roundness: look.roundness))
            .overlay {
                if look.outline != .off {
                    PreviewShellShape(placement: placement, roundness: look.roundness)
                        .stroke(accent.opacity(0.55), lineWidth: look.outline.lineWidth)
                }
            }
            VStack(spacing: 8) {
                if placement == .top {
                    Capsule().fill(.black).frame(width: 64, height: 12)
                }
                player
                    .padding(.top, placement == .top ? 0 : 14)
            }
        }
        .frame(width: 210 * look.shelfSize.scale, height: 78)
        .shadow(color: .black.opacity(look.shadow.opacity * 0.8), radius: look.shadow.radius / 2, y: 4)
    }

    private var look: Appearance { preferences.appearance }

    /// A tiny Now Playing row: the accent shows in the artwork and progress bar even on
    /// the Black surface, and the time uses the chosen number font.
    private var player: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 6 * look.roundness, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent, glow ?? accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(.white.opacity(0.85)).frame(width: 74, height: 4)
                Capsule().fill(.white.opacity(0.35)).frame(width: 48, height: 3)
                HStack(spacing: 5) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18)).frame(width: 84, height: 3)
                        Capsule().fill(accent).frame(width: 52, height: 3)
                    }
                    Text("1:32")
                        .font(.system(size: 8, weight: .semibold, design: look.valueFont.design))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    @ViewBuilder private var navPill: some View {
        switch look.navPill {
        case .pill: navTabs
        case .dots: navDots
        case .hidden: Color.clear.frame(height: 16)
        }
    }

    private var navDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { index in
                Circle().fill(index == 0 ? accent : .white.opacity(0.4)).frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 12)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    private var navTabs: some View {
        HStack(spacing: 4) {
            ForEach(["house.fill", "tray.fill", "music.note", "square.grid.2x2.fill"], id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.system(size: 8))
                    .frame(width: 18, height: 12)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(accent.opacity(symbol == "house.fill" ? 0.85 : 0)))
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(height: 16)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    private static func alignment(for placement: Placement) -> Alignment {
        switch placement {
        case .top: .top
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// Islands float a little off their edge; notches touch it.
    private static func inset(for placement: Placement) -> EdgeInsets {
        switch placement {
        case .top, .left, .right: EdgeInsets()
        case .topLeft, .topRight: EdgeInsets(top: 6, leading: 10, bottom: 0, trailing: 10)
        case .bottom: EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0)
        }
    }

    @ViewBuilder private var backdrop: some View {
        if let wallpaper {
            Image(nsImage: wallpaper).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 124)
                .clipped()
        } else {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.1, blue: 0.25), .wispViolet], startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }
    }

    private static func loadWallpaper() -> NSImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// The preview shell for each position: the notch at the top, a shape flat against the
/// edge on the sides, and a floating island at the corners and bottom.
private struct PreviewShellShape: Shape {
    let placement: Placement
    var roundness: Double = 1

    func path(in rect: CGRect) -> Path {
        let radius = 18 * roundness
        switch placement {
        case .top:
            return NotchShape(topRadius: 8, bottomRadius: radius).path(in: rect)
        case .left:
            return UnevenRoundedRectangle(
                bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous
            ).path(in: rect)
        case .right:
            return UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius, style: .continuous)
                .path(in: rect)
        case .topLeft, .topRight, .bottom:
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
    }
}

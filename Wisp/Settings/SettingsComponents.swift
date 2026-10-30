import AppKit
import Observation
import SwiftUI
import WispCore

extension SettingsPaneID {
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .notch: "capsule.portrait.fill"
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
        case .notch, .activities, .widgets, .profiles, .clipboard: .wispViolet
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
            if let selection, !matches.contains(selection) { self.selection = matches.first }
        }
    }
    private(set) var missing: [Permission] = []

    let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        selection = preferences.lastSettingsPane
        refreshHealth()
    }

    var visiblePanes: [SettingsPaneID] { SettingsIndex.panes(matching: query) }

    /// Permissions are granted in System Settings, so this is re-read while the window shows.
    func refreshHealth() {
        let widgets = preferences.enabledWidgets
        let needed = SetupHealth.needed(
            notifications: preferences.notificationsEnabled,
            calendarWidgets: widgets.contains(.calendar) || widgets.contains(.dayProgress),
            mirror: widgets.contains(.mirror))
        let granted = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0.rawValue, $0.isGranted) })
        let ids = SetupHealth.missing(granted: granted, needed: needed)
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
    @State private var wallpaper: NSImage?

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            ZStack(alignment: .top) {
                SurfaceBackground(style: preferences.surfaceStyle, glass: preferences.glassEdge, accent: accent)
                    .clipShape(NotchShape(topRadius: 8, bottomRadius: 18))
                VStack(spacing: 6) {
                    Capsule().fill(.black).frame(width: 64, height: 12)
                    HStack(spacing: 14) {
                        ForEach([WidgetKind.nowPlaying, .calendar, .quickToggles, .agents], id: \.self) { kind in
                            VStack(spacing: 3) {
                                IconTile(symbol: kind.symbol, tint: kind.tint, size: 22)
                                Capsule().fill(.white.opacity(0.35)).frame(width: 20, height: 2)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(width: 210, height: 78)
            .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
            HStack(spacing: 10) {
                ForEach(["house.fill", "tray.fill", "music.note", "square.grid.2x2.fill"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 8))
                }
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 16)
            .background(Capsule().fill(.black.opacity(0.55)))
            .padding(.top, 86)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: preferences.surfaceStyle)
        .task { wallpaper = Self.loadWallpaper() }
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

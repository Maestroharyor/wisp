import AppKit
import SwiftUI
import WispCore

/// The window's sidebar as a panel floating inside it: room for the window's buttons and a
/// hide button at the top, the rows in folding sections, and a drawn scene at the foot with a
/// line for the page that's open.
struct WindowSidebarPanel: View {
    let model: NotchModel
    let navigation: WindowNavigation
    let selection: WindowDestination

    private var services: AppServices { model.services }
    private var preferences: Preferences { model.preferences }

    var body: some View {
        let sections = navigation.sections(services: services)
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            sectionRows(section)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.never)
                // The scene gives way first on a short window, so the rows always fit.
                let art = min(WindowShell.artHeight, max(proxy.size.height - 420, 0))
                if art > 60 { scene.frame(height: art) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WindowShell.panelRadius, style: .continuous))
        .wispSurface(cornerRadius: WindowShell.panelRadius)
        // For the overdue badge; a stale list would miss reminders that fell due meanwhile.
        .onAppear { services.reminders.refreshIfStale() }
    }

    /// The window's own buttons sit at the leading end; the rest of the strip moves the window.
    private var header: some View {
        HStack {
            Spacer()
            Button {
                withWispAnimation(.wispSmooth) { navigation.perform(.toggleSidebar) }
            } label: {
                Image(systemName: "sidebar.left")
                    .wispFont(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wispHover()
            .help("Hide sidebar (⌘0)")
            .accessibilityLabel("Hide sidebar")
        }
        .padding(.horizontal, 8)
        .frame(height: WindowShell.barHeight)
        .background(WindowDragArea())
    }

    @ViewBuilder private func sectionRows(_ section: WindowSidebarSection) -> some View {
        let folded = preferences.windowFoldedSections.contains(section.kind.rawValue)
        Button {
            withWispAnimation(.wispSmooth) { toggleFold(section.kind) }
        } label: {
            HStack(spacing: 4) {
                Text(section.title)
                    .wispFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .wispFont(.caption2, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(folded ? -90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityValue(folded ? "Collapsed" : "Expanded")
        .accessibilityHint(folded ? "Shows the section's rows" : "Hides the section's rows")
        if !folded {
            ForEach(section.rows, id: \.self) { row in
                WindowSidebarButton(
                    row: row, selected: row == selection, badge: badge(of: row), services: services
                ) { navigation.select(row) }
            }
        }
    }

    private func toggleFold(_ kind: WindowSidebarSection.Kind) {
        if let index = preferences.windowFoldedSections.firstIndex(of: kind.rawValue) {
            preferences.windowFoldedSections.remove(at: index)
        } else {
            preferences.windowFoldedSections.append(kind.rawValue)
        }
    }

    private var scene: some View {
        ZStack(alignment: .bottomLeading) {
            NightRidgeArt()
            if preferences.windowTagline {
                Text(WindowTaglines.phrase(for: selection))
                    .wispFont(.callout)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .id(selection)
                    .wispTransition(.opacity)
            }
        }
        .wispAnimation(.wispSmooth, value: selection)
    }

    private func badge(of row: WindowDestination) -> Int {
        switch row {
        case .page(.tray): services.tray.count
        case .widget(WidgetKind.agents.rawValue): services.agents.approvals.count
        case .widget(WidgetKind.clipboard.rawValue): services.clipboard.history.items.filter(\.pinned).count
        case .widget(WidgetKind.reminders.rawValue): overdueReminders
        default: 0
        }
    }

    /// Open reminders past their due time, once Reminders has been read with full access.
    private var overdueReminders: Int {
        let reminders = services.reminders
        guard reminders.loaded, reminders.access == .fullAccess else { return 0 }
        let now = Date.now
        return reminders.items.filter { ReminderList.isOverdue($0, now: now) }.count
    }
}

/// One sidebar row: its icon, title and count, with a violet pill when it's open.
private struct WindowSidebarButton: View {
    let row: WindowDestination
    let selected: Bool
    let badge: Int
    let services: AppServices
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                icon.frame(width: 20)
                Text(WindowRow.title(of: row, services: services))
                    .wispFont(.body, weight: selected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text(badge, format: .number)
                        .wispFont(.caption, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous)
                        .fill(Color.wispViolet.opacity(0.2))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .wispHover()
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(badge > 0 ? "\(badge)" : "")
    }

    // Tinted symbols, as Notes and Reminders list theirs; a live activity keeps a filled tile so
    // it stands out while it runs.
    @ViewBuilder private var icon: some View {
        if case .live = row {
            IconTile(symbol: WindowRow.symbol(of: row, services: services), tint: WindowRow.tint(of: row), size: 20)
        } else {
            Image(systemName: WindowRow.symbol(of: row, services: services))
                .wispFont(.body)
                .foregroundStyle(WindowRow.tint(of: row))
        }
    }
}

/// Sizes the window's shell shares between the sidebar, the top bar and the window's buttons.
enum WindowShell {
    /// Space between the window's edge and its panels.
    static let inset: CGFloat = 12
    static let panelRadius: CGFloat = 18
    /// The sidebar header and the top bar, which line up with the window's buttons.
    static let barHeight: CGFloat = 36
    static let sidebarWidth: CGFloat = 236
    /// The sidebar's width in a narrow window, so the page keeps its room.
    static let compactSidebarWidth: CGFloat = 200
    /// Below this window width the sidebar narrows.
    static let compactBelow: CGFloat = 960
    static let artHeight: CGFloat = 150
    /// Where the close button's centre sits, from the window's top-left corner: in the middle
    /// of the bars, inside the sidebar panel.
    static var trafficLightCentre: CGPoint { CGPoint(x: inset + 20, y: inset + barHeight / 2) }
    /// Room the window's three buttons take, for the top bar when the sidebar is hidden.
    static let trafficLightRoom: CGFloat = 88
}

/// A clear strip that moves the window when dragged, for the parts of the bars with no
/// controls. The titlebar is transparent, so the window has no other handle up there.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard event.clickCount == 2 else { return window?.performDrag(with: event) ?? () }
            // A double click does what System Settings › Desktop & Dock says, as a titlebar does.
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window?.performMiniaturize(nil)
            case "None": break
            default: window?.performZoom(nil)
            }
        }
    }
}

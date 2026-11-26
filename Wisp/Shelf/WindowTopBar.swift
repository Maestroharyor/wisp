import SwiftUI
import WispCore

/// The strip across the top of the window's content: the field that opens the command bar,
/// the day's line, and round buttons for Home's cards, the form and Settings.
struct WindowTopBar: View {
    let model: NotchModel
    let navigation: WindowNavigation
    let selection: WindowDestination

    private var preferences: Preferences { model.preferences }

    var body: some View {
        HStack(spacing: 10) {
            if navigation.columns == .detailOnly {
                // Clear of the window's own buttons, which stay at the corner.
                Color.clear.frame(width: WindowShell.trafficLightRoom - WindowShell.inset)
                RoundButton(symbol: "sidebar.left", help: "Show sidebar (⌘0)") {
                    withWispAnimation(.wispSmooth) { navigation.perform(.toggleSidebar) }
                }
            }
            // The field keeps its room; the day's line gives way first.
            searchField.layoutPriority(1)
            ViewThatFits(in: .horizontal) {
                tagline
                Color.clear.frame(width: 0)
            }
            .frame(maxWidth: .infinity)
            buttons
        }
        .frame(height: WindowShell.barHeight)
        .background(WindowDragArea())
    }

    private var searchField: some View {
        Button {
            navigation.showsCommandBar = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("Ask, create, find anything\u{2026}")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\u{2318}K")
                    .wispFont(.caption, weight: .medium)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary))
            }
            .wispFont(.body)
            .padding(.horizontal, 12)
            .frame(height: WindowShell.barHeight)
            .frame(minWidth: 220, idealWidth: 340, maxWidth: 380)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .wispSurface(Capsule(), role: .card)
        .wispHover(shape: Capsule())
        .help("Find pages, clips, notes and apps, or add a timer, reminder or event")
        .accessibilityLabel("Ask, create, find anything")
        .accessibilityHint("Opens the command bar")
    }

    @ViewBuilder private var tagline: some View {
        if preferences.windowTagline {
            TimelineView(.everyMinute) { context in
                Text(WindowTaglines.line(for: context.date, calendar: .autoupdatingCurrent))
                    .wispFont(.callout)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 12)
        } else {
            Color.clear.frame(width: 0)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            if selection == .home {
                RoundButton(symbol: "square.grid.2x2", help: "Choose the cards on Home") {
                    navigation.customisingHome = true
                }
                .accessibilityLabel("Customise Home")
            }
            Menu {
                FormMenuItems(model: model)
            } label: {
                Image(systemName: model.form.symbol)
                    .wispFont(.body)
                    .frame(width: WindowShell.barHeight, height: WindowShell.barHeight)
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .wispSurface(Circle(), role: .card)
            .wispHover(shape: Circle())
            .help("Change form")
            .accessibilityLabel("Form")
            RoundButton(symbol: "gearshape", help: "Settings") { model.services.openSettings() }
                .accessibilityLabel("Settings")
        }
    }
}

/// A round glass button in the top bar.
struct RoundButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .wispFont(.body)
                .foregroundStyle(.primary)
                .frame(width: WindowShell.barHeight, height: WindowShell.barHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .wispSurface(Circle(), role: .card)
        .wispHover(shape: Circle())
        .help(help)
    }
}

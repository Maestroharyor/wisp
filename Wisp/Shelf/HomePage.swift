import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Home: up to four widgets side by side, separated by hairlines. Customise mode
/// adds, removes, resizes and reorders them.
struct HomePage: View {
    let model: NotchModel

    private var preferences: Preferences { model.preferences }

    var body: some View {
        let widgets = preferences.homeWidgets
        let rowHeight = SurfaceSizing.shelfContentHeight

        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                if widgets.isEmpty {
                    emptyHint.frame(height: rowHeight)
                }
                ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                    if index > 0 { WidgetDivider(height: rowHeight) }
                    WidgetCard(kind: kind, model: model)
                        // In Customise mode the content sits inside the dashed outline,
                        // clear of the remove badge (top right) and size chip (bottom).
                        .padding(
                            model.editingHome
                                ? EdgeInsets(top: 14, leading: 14, bottom: 30, trailing: 18) : EdgeInsets()
                        )
                        .frame(width: preferences.size(of: kind).width, height: rowHeight)
                        .clipped()
                        .overlay { if model.editingHome { editOverlay(kind) } }
                        .onDrag { NSItemProvider(object: NSString(string: kind.rawValue)) }
                        .onDrop(of: [.plainText], isTargeted: nil) { providers in
                            reorder(providers, onto: kind)
                        }
                }
            }
            if model.editingHome {
                pickerRow.transition(model.motion.expands ? .opacity.combined(with: .move(edge: .bottom)) : .opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: preferences.homeLayout)
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.2x2").font(.system(size: 18))
            Text("Right-click the notch and choose Customise Home")
                .font(.system(size: 11)).foregroundStyle(Color.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editOverlay(_ kind: WidgetKind) -> some View {
        RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .padding(.horizontal, 4)
            .overlay(alignment: .topTrailing) {
                Button {
                    preferences.homeLayout.remove(kind.rawValue)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(kind.title) from Home")
                .offset(x: -2, y: -4)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    preferences.homeLayout.resize(kind.rawValue, to: preferences.size(of: kind).next)
                } label: {
                    Label(preferences.size(of: kind).rawValue.capitalized, systemImage: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .padding(.bottom, 6)
                .help("Change size")
            }
    }

    private var pickerRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WidgetKind.allCases) { kind in pickerTile(kind) }
                }
                // Room for the corner ticks and the first tile's edge.
                .padding(.horizontal, 6)
                .padding(.top, 6)
            }
            Button {
                // After a profile switch the snapshot belongs to the old profile; restoring it
                // would save it into the new one.
                if let snapshot = model.homeSnapshot, snapshot.profile == preferences.homeProfile {
                    preferences.homeLayout = snapshot.layout
                    preferences.enabledWidgets = snapshot.enabled
                }
                endEditing()
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            .help("Cancel")
            Button(action: endEditing) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28).background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .help("Done")
        }
        .frame(height: SurfaceSizing.pickerRowHeight - 12)
    }

    /// Tap toggles a widget on Home (switching it on if needed). Blue check: on Home.
    private func pickerTile(_ kind: WidgetKind) -> some View {
        let onHome = preferences.homeLayout.contains(kind.rawValue)
        let full = preferences.homeLayout.isFull
        return Button {
            if onHome {
                preferences.homeLayout.remove(kind.rawValue)
            } else if !full {
                preferences.enable(kind)
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: kind.symbol).font(.system(size: 16))
                Text(kind.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(width: 74, height: 54)
            .card(highlighted: onHome)
            .opacity(!onHome && full ? 0.45 : 1)
            .overlay(alignment: .topTrailing) {
                if onHome {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .help(!onHome && full ? "Home holds four widgets; remove one first" : kind.title)
    }

    private func endEditing() {
        model.editingHome = false
        model.homeSnapshot = nil
    }

    private func reorder(_ providers: [NSItemProvider], onto target: WidgetKind) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: String.self) { raw, _ in
            Task { @MainActor in
                guard let raw else { return }
                preferences.homeLayout.move(raw, before: target.rawValue)
            }
        }
        return true
    }
}

/// Hairline between widgets.
struct WidgetDivider: View {
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: max(height - 18, 0))
            .frame(width: HomeLayout.dividerSpacing, height: height)
    }
}

/// Every switched-on widget in one row at its own size, scrolling sideways when
/// they don't all fit. Same height as every other page.
/// The Widgets page: an icon grid of every switched-on widget. Clicking an icon
/// opens that widget on its own; dragging an icon onto another reorders the grid.
struct WidgetsPage: View {
    let model: NotchModel
    /// Ties each icon tile to its solo card, so opening one grows the tile into the card.
    @Namespace private var zoom

    var body: some View {
        ZStack {
            if let solo = model.soloWidget {
                SoloWidgetView(kind: solo, model: model, zoom: zoomSpace)
                    .transition(.opacity)
            } else {
                WidgetGridView(model: model, zoom: zoomSpace)
                    .transition(.opacity)
            }
        }
        .animation(model.surfaceAnimation, value: model.soloWidget)
    }

    /// No zoom from tile to card with Reduce Motion; the pages just cross-fade.
    private var zoomSpace: Namespace.ID? { model.motion.expands ? zoom : nil }
}

private struct WidgetGridView: View {
    let model: NotchModel
    let zoom: Namespace.ID?

    var body: some View {
        let preferences = model.preferences
        let widgets = preferences.gridWidgets
        let rowCount = WidgetGrid.rows(count: widgets.count, preferred: preferences.widgetGridRows)
        let metrics = WidgetGrid.metrics(rows: rowCount)
        let columns = WidgetGrid.columns(count: widgets.count, rows: rowCount)
        let rows = Array(repeating: GridItem(.fixed(metrics.cellHeight), spacing: metrics.rowSpacing), count: rowCount)

        if widgets.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2").font(.system(size: 18))
                Text("Switch widgets on in Settings › Widgets")
                    .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { proxy in
                LazyHGrid(
                    rows: rows,
                    spacing: WidgetGrid.spreadSpacing(columns: columns, available: proxy.size.width)
                ) {
                    ForEach(widgets) { kind in
                        WidgetIconCell(kind: kind, metrics: metrics, zoom: zoom) {
                            model.soloWidget = kind
                        }
                        .draggable(kind.rawValue) { WidgetIconTile(kind: kind, size: metrics.tileSize) }
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first, let moved = WidgetKind(rawValue: id) else { return false }
                            withAnimation(model.surfaceAnimation) { preferences.moveGridWidget(moved, before: kind) }
                            return true
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// One grid entry: a tinted rounded tile and the widget's name.
private struct WidgetIconCell: View {
    let kind: WidgetKind
    let metrics: WidgetGrid.Metrics
    let zoom: Namespace.ID?
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: metrics.captionGap) {
                WidgetIconTile(kind: kind, size: metrics.tileSize)
                    .zoomSource(id: kind, in: zoom)
                    .scaleEffect(hovering ? 1.05 : 1)
                Text(kind.title)
                    .font(.system(size: metrics.captionSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: WidgetGrid.cellWidth, height: metrics.cellHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .help(kind.title)
    }
}

private struct WidgetIconTile: View {
    let kind: WidgetKind
    let size: CGFloat

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(kind.tint.gradient)
            )
    }
}

/// One widget opened from the grid, at the solo card width, with a way back.
private struct SoloWidgetView: View {
    let kind: WidgetKind
    let model: NotchModel
    let zoom: Namespace.ID?

    var body: some View {
        Group {
            if kind == .agents {
                AgentsDetail(hub: model.services.agents, model: model)
            } else {
                WidgetCard(kind: kind, model: model)
            }
        }
        .frame(
            width: kind.hasDetailPage
                ? SurfaceSizing.wideSoloWidth : ShellMetrics.soloCardWidth(notchStyle: model.isNotchStyle),
            height: SurfaceSizing.shelfContentHeight
        )
        .zoomSource(id: kind, in: zoom)
        .overlay(alignment: .topLeading) {
            Button {
                model.soloWidget = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .offset(x: -26, y: 2)
            .accessibilityLabel("Back to widgets")
            .help("Back to widgets")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension WidgetKind {
    /// Opened on its own, this widget gets the wide page with a list and details.
    var hasDetailPage: Bool { self == .agents || self == .calendar }

    /// Icon tint on the Widgets page grid.
    var tint: Color {
        switch self {
        case .nowPlaying: .pink
        case .calendar: .red
        case .timer: .orange
        case .pomodoro: .mint
        case .battery: .green
        case .systemStats: .cyan
        case .weather: .blue
        case .notes: .yellow
        case .quickToggles: .indigo
        case .shortcuts: .purple
        case .clipboard: .gray
        case .mirror: .teal
        case .dayProgress: .orange
        case .worldClocks: .cyan
        case .agents: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .script: .green
        }
    }
}

/// A large player on its own page.
struct MediaPage: View {
    let model: NotchModel

    var body: some View {
        let services = model.services
        let showsLyrics = model.showsLyrics
        HStack(spacing: 6) {
            Group {
                if showsLyrics, services.nowPlaying.info != nil {
                    HStack(spacing: 12) {
                        ArtworkView(image: services.nowPlaying.artwork, size: 50, radius: 11)
                        LyricLines(monitor: services.nowPlaying, lyrics: services.lyrics)
                    }
                    .transition(.opacity)
                } else {
                    NowPlayingWidget(monitor: services.nowPlaying).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 6) {
                if model.preferences.lyrics {
                    ShelfButton(
                        symbol: showsLyrics ? "quote.bubble.fill" : "quote.bubble", size: 12,
                        tint: showsLyrics ? .accentColor : .white
                    ) { withAnimation(.easeOut(duration: 0.2)) { model.showsLyrics.toggle() } }
                    .help("Lyrics (from LRCLIB)")
                }
                ShelfButton(symbol: "pip", size: 12) { services.miniPlayer.toggle() }
                    .help("Mini player")
            }
        }
        .frame(width: SurfaceSizing.mediaPageWidth, height: SurfaceSizing.shelfContentHeight)
    }
}

extension View {
    /// The tile-to-card zoom, left out when there's no namespace (Reduce Motion).
    @ViewBuilder
    fileprivate func zoomSource(id: WidgetKind, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: id, in: namespace) } else { self }
    }
}

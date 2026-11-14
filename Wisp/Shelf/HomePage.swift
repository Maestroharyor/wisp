import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Home: up to four widgets side by side, separated by hairlines. Customise mode
/// adds, removes, resizes and reorders them.
struct HomePage: View {
    let model: NotchModel

    @Environment(\.shelfHost) private var host
    @Environment(\.openWindowRow) private var openRow

    private var preferences: Preferences { model.preferences }

    var body: some View {
        switch host {
        case .notch: notchBody
        case .window: windowBody
        }
    }

    /// In the window: a grid of cards, each opening its own sidebar row.
    private var windowBody: some View {
        let widgets = preferences.homeWidgets
        return ScrollView(.vertical) {
            VStack(spacing: 16) {
                if widgets.isEmpty {
                    emptyHint.frame(height: Self.windowCardHeight)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                    ForEach(widgets) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            windowCardHeader(kind)
                            WidgetCard(kind: kind, model: model)
                        }
                        .padding(
                            model.editingHome
                                ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 18) : Self.cardInsets
                        )
                        .frame(height: Self.windowCardHeight)
                        .card()
                        .overlay { if model.editingHome { editOverlay(kind) } }
                        .onDrag { NSItemProvider(object: NSString(string: kind.rawValue)) }
                        .onDrop(of: [.plainText], isTargeted: nil) { providers in
                            reorder(providers, onto: kind)
                        }
                    }
                }
                if model.editingHome { pickerRow }
            }
            .padding(20)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: preferences.homeLayout)
    }

    private static let windowCardHeight: CGFloat = 200
    private static let cardInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)

    private func windowCardHeader(_ kind: WidgetKind) -> some View {
        Button {
            openRow(.widget(kind.rawValue))
        } label: {
            HStack(spacing: 6) {
                IconTile(symbol: kind.symbol, tint: kind.tint, size: 16)
                Text(kind.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.secondaryText)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.editingHome)
        .help("Open \(kind.title)")
        .accessibilityLabel("Open \(kind.title)")
    }

    @ViewBuilder private var notchBody: some View {
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
            Text(
                host == .window
                    ? "Choose Customise Home in the toolbar" : "Right-click the notch and choose Tools › Customise Home"
            )
            .font(.system(size: 11)).foregroundStyle(Color.secondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editOverlay(_ kind: WidgetKind) -> some View {
        RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous)
            .strokeBorder(.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
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
                .hoverHint("Remove from Home")
                .offset(x: -2, y: -4)
            }
            .overlay(alignment: .bottomTrailing) {
                // Sizes are widths in the notch's row; the window's grid has none to change.
                if host == .notch {
                    Button {
                        preferences.homeLayout.resize(
                            kind.rawValue, to: preferences.size(of: kind).next(in: kind.sizes))
                    } label: {
                        Label(preferences.size(of: kind).rawValue.capitalized, systemImage: "arrow.left.and.right")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.ink.opacity(0.18)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10)
                    .padding(.bottom, 6)
                    .help("Change size")
                }
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
                model.cancelHomeEditing()
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28).background(Circle().fill(.ink.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")
            .hoverHint("Cancel")
            Button(action: endEditing) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28).background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            .hoverHint("Done")
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
            .contentShape(RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous))
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

    private func endEditing() { model.endHomeEditing() }

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
            .fill(.ink.opacity(0.12))
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
            if let detail = model.activityDetail {
                ActivityDetailView(detail: detail, model: model)
                    .transition(.opacity)
            } else if let solo = model.soloWidget {
                SoloWidgetView(kind: solo, model: model, zoom: zoomSpace)
                    .transition(.opacity)
            } else {
                WidgetGridView(model: model, zoom: zoomSpace)
                    .transition(.opacity)
            }
        }
        .animation(model.surfaceAnimation, value: model.soloWidget)
        .animation(model.surfaceAnimation, value: model.activityDetail)
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
                Text("Switch widgets on in Settings › Shelf")
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
                    .foregroundStyle(.ink.opacity(hovering ? 0.9 : 0.7))
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
                AgentsDetail(hub: model.services.agents, cloud: model.services.cloud, model: model)
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
            SoloBackButton(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A pill's own view, at the solo card width, with the same back chevron.
private struct ActivityDetailView: View {
    let detail: ActivityDetail
    let model: NotchModel

    var body: some View {
        Group {
            switch detail {
            case .regionWatch: RegionWatchDetail(watch: model.services.regionWatch)
            case .downloads: DownloadsDetail(monitor: model.services.downloads)
            case .external: ExternalActivityDetail(automation: model.services.automation)
            case .sessionSwitcher: SessionSwitcherView(model: model)
            }
        }
        .padding(.vertical, 4)
        .frame(
            width: ShellMetrics.soloCardWidth(notchStyle: model.isNotchStyle),
            height: SurfaceSizing.shelfContentHeight, alignment: .topLeading
        )
        .overlay(alignment: .topLeading) {
            SoloBackButton(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The chevron left of a solo card: back to the Widgets grid, or to the page a pill's view
/// came from.
private struct SoloBackButton: View {
    let model: NotchModel

    var body: some View {
        let label = model.soloFromPill ? "Back" : "Back to widgets"
        Button {
            model.leaveSolo()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.ink.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverHint(label)
        .offset(x: -26, y: 2)
        .accessibilityLabel(label)
    }
}

extension WidgetKind {
    /// Opened on its own, this widget gets the wide page with a list and details.
    var hasDetailPage: Bool { self == .agents || self == .calendar }

    /// Sizes the resize button offers. Agents can also fill the shelf.
    var sizes: [WidgetSize] { self == .agents ? WidgetSize.allCases : WidgetSize.standard }

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
        case .quickInput: .purple
        }
    }
}

/// A large player on its own page.
struct MediaPage: View {
    let model: NotchModel

    @Environment(\.shelfHost) private var host

    var body: some View {
        switch host {
        case .notch: notchBody
        case .window: WindowMediaPage(model: model)
        }
    }

    @ViewBuilder private var notchBody: some View {
        let services = model.services
        let showsLyrics = model.showsLyrics
        let showsVolume = model.showsAppVolume && model.preferences.appVolume
        HStack(spacing: 6) {
            Group {
                if showsVolume {
                    AppVolumeMixer(store: services.appVolume, compact: true).transition(.opacity)
                } else if showsLyrics, services.nowPlaying.info != nil {
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
                        tint: showsLyrics ? .accentColor : .ink, hint: "Lyrics (from LRCLIB)"
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            model.showsLyrics.toggle()
                            model.showsAppVolume = false
                        }
                    }
                }
                if model.preferences.appVolume {
                    ShelfButton(
                        symbol: "slider.horizontal.3", size: 12, tint: showsVolume ? .accentColor : .ink,
                        hint: "App volume"
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            model.showsAppVolume.toggle()
                            model.showsLyrics = false
                        }
                    }
                }
                ShelfButton(symbol: "pip", size: 12) { services.miniPlayer.toggle() }
            }
        }
        .frame(width: SurfaceSizing.mediaPageWidth, height: SurfaceSizing.shelfContentHeight)
    }
}

/// The Media page in the window: large artwork with the controls under it and lyrics beside it.
/// The Now Playing row shows it too.
struct WindowMediaPage: View {
    let model: NotchModel
    @State private var showsAppVolume = false

    var body: some View {
        let monitor = model.services.nowPlaying
        GeometryReader { proxy in
            // Room under the artwork for the title and controls, and Up Next when Music plays.
            let below: CGFloat = model.preferences.upNext && UpNext.applies(to: monitor.info) ? 300 : 190
            let art = min(max(min(proxy.size.height - below, proxy.size.width * 0.45), 160), 340)
            HStack(alignment: .center, spacing: 36) {
                VStack(alignment: .leading, spacing: 14) {
                    ArtworkView(image: monitor.artwork, size: art, radius: 16)
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                        .onTapGesture { monitor.openPlayer() }
                    if let info = monitor.info {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(info.title).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                            Text(info.artist.isEmpty ? (info.appName ?? "") : info.artist)
                                .font(.system(size: 14)).foregroundStyle(Color.secondaryText).lineLimit(1)
                        }
                        NowPlayingProgress(monitor: monitor, info: info)
                        HStack(spacing: 12) {
                            NowPlayingTransport(monitor: monitor, info: info)
                            ShelfButton(symbol: "pip", size: 12, hint: "Mini player") {
                                model.services.miniPlayer.toggle()
                            }
                            appVolumeButton
                        }
                        if model.preferences.upNext {
                            UpNextList(monitor: monitor, store: model.services.upNext)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nothing playing").font(.system(size: 20, weight: .semibold))
                            Text("Play something in any app or browser")
                                .font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                        }
                        appVolumeButton
                    }
                }
                .frame(width: art)
                if model.preferences.lyrics, monitor.info != nil {
                    LyricLines(monitor: monitor, lyrics: model.services.lyrics, size: 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }
            .padding(32)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder private var appVolumeButton: some View {
        if model.preferences.appVolume {
            ShelfButton(symbol: "slider.horizontal.3", size: 12, hint: "App volume") { showsAppVolume.toggle() }
                .popover(isPresented: $showsAppVolume, arrowEdge: .bottom) {
                    AppVolumeMixer(store: model.services.appVolume).padding(14).frame(width: 340, height: 240)
                }
        }
    }
}

extension View {
    /// The tile-to-card zoom, left out when there's no namespace (Reduce Motion).
    @ViewBuilder
    fileprivate func zoomSource(id: WidgetKind, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedGeometryEffect(id: id, in: namespace) } else { self }
    }
}

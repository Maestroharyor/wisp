import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Files parked in the tray: a summary with labelled actions above a row of file cards.
struct TrayPage: View {
    let model: NotchModel

    @State private var targeted = false
    @State private var quickLook: URL?
    @Environment(\.shelfHost) private var host

    private var tray: TrayStore { model.services.tray }

    var body: some View {
        if host == .window {
            windowBody
        } else {
            notchBody
        }
    }

    /// In the window: a header with the tray's actions, then the files as cards, or a large
    /// place to drop them.
    private var windowBody: some View {
        let list = tray.list
        let allSelected = !list.urls.isEmpty && list.selected.count == list.urls.count
        return WindowPageFrame {
            WindowPageHeader(
                symbol: "tray.fill", tint: .blue, title: "Tray",
                subtitle: "Park files here, then AirDrop, zip or convert them in one go",
                count: list.urls.isEmpty ? nil : tray.header
            ) {
                Button("Choose files…", systemImage: "plus") { chooseFiles() }
                    .labelStyle(.iconOnly)
                    .help("Choose files to add")
                if !list.urls.isEmpty {
                    Button(
                        allSelected ? "Deselect all" : "Select all",
                        systemImage: allSelected ? "checkmark.circle.fill" : "checkmark.circle"
                    ) { tray.toggleSelectAll() }
                    .labelStyle(.iconOnly)
                    .help(allSelected ? "Deselect all" : "Select all")
                    Button(list.selected.isEmpty ? "Clear tray" : "Remove selected", systemImage: "trash") {
                        tray.removeSelectedOrAll()
                    }
                    .labelStyle(.iconOnly)
                    .help(list.selected.isEmpty ? "Clear tray" : "Remove selected")
                    // ⌘⌫ only removes a selection; clearing the whole tray stays a click.
                    .keyboardShortcut(list.selected.isEmpty ? nil : KeyboardShortcut(.delete, modifiers: .command))
                    Button("Zip", systemImage: "doc.zipper") { tray.zip(list.actionTargets) }
                    Button("Transform", systemImage: "wand.and.stars") {
                        model.services.openTransform(list.actionTargets)
                    }
                    WindowPrimaryButton(title: "AirDrop", symbol: AirDropGlyph.symbol) {
                        tray.airDrop(list.actionTargets)
                    }
                }
            }
        } content: {
            Group {
                if list.urls.isEmpty {
                    WindowEmptyState(
                        symbol: "tray.and.arrow.down", title: "Drop files here",
                        message:
                            "Drag files from Finder or any app to keep them handy. They stay put until you clear the tray, and you can drag them out again anywhere."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous)
                            .fill(targeted ? Color.wispViolet.opacity(0.12) : .primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous)
                            .strokeBorder(
                                targeted ? Color.wispViolet : .primary.opacity(0.2),
                                style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
                } else {
                    ScrollView(.vertical) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 12)], spacing: 12)
                        {
                            ForEach(list.urls, id: \.self) { url in
                                TrayCard(url: url, tray: tray, services: model.services, metrics: .window)
                            }
                            DropMoreCard(active: targeted, width: nil)
                                .frame(height: TrayCardMetrics.window.thumbnail + 56)
                        }
                        .padding(12)
                    }
                    .scrollFade()
                    .windowCardBackground()
                }
            }
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL], isTargeted: $targeted, perform: FileDrop.handler { tray.add($0) })
            .background {
                // Space previews the selection in Quick Look, as in Finder.
                Button("Quick Look") { quickLook = list.urls.first { list.selected.contains($0) } }
                    .keyboardShortcut(list.selected.isEmpty ? nil : KeyboardShortcut(.space, modifiers: []))
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .quickLookPreview($quickLook, in: list.urls.filter { list.selected.contains($0) })
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Add to tray"
        guard panel.runModal() == .OK else { return }
        tray.add(panel.urls)
    }

    private var notchBody: some View {
        Group {
            if tray.list.urls.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.title)
                    Text("Drag files here to keep them handy")
                        .font(.callout).foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(DropOutline(active: targeted, cornerRadius: ShellMetrics.widgetCornerRadius))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    // A short tray fills the row: the drop card stretches into the free space.
                    if CGFloat(tray.count + 1) * SurfaceSizing.trayItemWidth <= SurfaceSizing.trayMinimumContentWidth {
                        cards(dropWidth: nil)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) { cards(dropWidth: Self.cardWidth) }
                            .scrollClipDisabled()
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: FileDrop.handler { tray.add($0) })
    }

    private func cards(dropWidth: CGFloat?) -> some View {
        HStack(spacing: Self.cardSpacing) {
            ForEach(tray.list.urls, id: \.self) { url in
                TrayCard(url: url, tray: tray, services: model.services)
            }
            DropMoreCard(active: targeted, width: dropWidth)
        }
    }

    nonisolated static let cardSpacing: CGFloat = 6
    nonisolated static var cardWidth: CGFloat { SurfaceSizing.trayItemWidth - cardSpacing }

    private var header: some View {
        let list = tray.list
        let allSelected = list.selected.count == list.urls.count
        return HStack(spacing: 6) {
            Text(tray.header)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.ink.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            TrayAction(symbol: allSelected ? "checkmark.circle.fill" : "checkmark.circle") { tray.toggleSelectAll() }
                .hoverHint(allSelected ? "Deselect all" : "Select all")
                .accessibilityLabel(allSelected ? "Deselect all" : "Select all")
            TrayAction(symbol: AirDropGlyph.symbol, title: "AirDrop") { tray.airDrop(list.actionTargets) }
            TrayAction(symbol: "wand.and.stars", title: "Transform") {
                model.services.openTransform(list.actionTargets)
            }
            TrayAction(symbol: "doc.zipper", title: "Zip") { tray.zip(list.actionTargets) }
            TrayAction(symbol: "trash") { tray.removeSelectedOrAll() }
                .hoverHint(list.selected.isEmpty ? "Clear tray" : "Remove selected")
                .accessibilityLabel(list.selected.isEmpty ? "Clear tray" : "Remove selected")
        }
        .frame(height: 24)
        .wispAnimation(.easeOut(duration: 0.15), value: tray.header)
    }
}

/// Card sizes: small in the notch's row, larger in the window's grid.
struct TrayCardMetrics {
    /// Nil fills the grid cell.
    let width: CGFloat?
    let thumbnail: CGFloat
    let nameSize: CGFloat
    let detailSize: CGFloat

    static let notch = TrayCardMetrics(width: TrayPage.cardWidth, thumbnail: 50, nameSize: 10, detailSize: 9)
    static let window = TrayCardMetrics(width: nil, thumbnail: 120, nameSize: 13, detailSize: 11)
}

/// A small capsule button for the tray header: an icon, with a label when there is room for one.
private struct TrayAction: View {
    let symbol: String
    var title: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
                if let title { Text(title).font(.subheadline.weight(.medium)) }
            }
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(minWidth: 24, minHeight: 24)
            .background(Capsule().fill(.ink.opacity(hovering ? 0.2 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct TrayCard: View {
    let url: URL
    let tray: TrayStore
    let services: AppServices
    var metrics = TrayCardMetrics.notch

    @State private var hovering = false

    var body: some View {
        let selected = tray.list.selected.contains(url)
        VStack(spacing: 3) {
            Group {
                if let image = tray.thumbnails[url] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").font(.system(size: metrics.thumbnail * 0.48))
                }
            }
            .frame(width: metrics.width.map { $0 - 12 }, height: metrics.thumbnail)
            .frame(maxWidth: metrics.width == nil ? .infinity : nil)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.wispViolet)
                        .offset(x: 4, y: -4)
                }
            }
            .padding(.top, 6)
            Text(url.lastPathComponent)
                .font(.system(size: metrics.nameSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(tray.detail(for: url))
                .font(.system(size: metrics.detailSize))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 6)
        .frame(width: metrics.width)
        .frame(maxWidth: metrics.width == nil ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                .fill(.ink.opacity(selected ? 0.14 : hovering ? 0.1 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                .strokeBorder(Color.wispViolet.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { tray.open(url) }
        .onTapGesture { tray.toggleSelection(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { tray.open(url) }
            Button("Show in Finder") { tray.reveal([url]) }
            Button("AirDrop") { tray.airDrop([url]) }
            Button("Transform…") { services.openTransform([url]) }
            Button("Zip") { tray.zip([url]) }
            if url.pathExtension.lowercased() == "pdf", services.textCapture.canSummarise {
                Button("Summarise PDF") { services.textCapture.summarise(url) }
            }
            Divider()
            Button("Remove from Tray") { tray.remove(url) }
        }
        .help(url.path)
        // One element: its name and details, selected or not, with the menu's actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(url.lastPathComponent), \(tray.detail(for: url))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Selects it. Double-click to open.")
        .accessibilityAction { tray.toggleSelection(url) }
        .accessibilityAction(named: "Open") { tray.open(url) }
        .accessibilityAction(named: "Show in Finder") { tray.reveal([url]) }
        .accessibilityAction(named: "AirDrop") { tray.airDrop([url]) }
        .accessibilityAction(named: "Zip") { tray.zip([url]) }
        .accessibilityAction(named: "Remove from Tray") { tray.remove(url) }
    }
}

/// The last card in a tray with files: room for one more drop.
private struct DropMoreCard: View {
    let active: Bool
    /// Nil fills the remaining width.
    let width: CGFloat?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "plus").font(.title3.weight(.semibold))
            Text("Drop more").font(.caption.weight(.medium))
        }
        .foregroundStyle(.ink.opacity(active ? 0.9 : 0.45))
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity)
        .overlay(DropOutline(active: active, cornerRadius: SurfaceRadius.row))
    }
}

private struct DropOutline: View {
    let active: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.ink.opacity(active ? 0.6 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }
}

/// Shown while a file drag is over the notch: drop on a tile to act on the files.
struct DropTiles: View {
    let model: NotchModel

    var body: some View {
        let tray = model.services.tray
        HStack(spacing: SurfaceSizing.tileSpacing) {
            DropTile(symbol: "tray.and.arrow.down.fill", title: "Drop") { tray.add($0) }
            DropTile(symbol: "wand.and.stars", title: "Transform") { model.services.openTransform($0) }
            DropTile(symbol: "doc.zipper", title: "Zip") { tray.zip($0) }
            DropTile(symbol: AirDropGlyph.symbol, title: "AirDrop") { tray.airDrop($0) }
            ForEach(model.preferences.dropActions.prefix(SurfaceSizing.maxDropActionTiles)) { action in
                DropTile(symbol: action.symbol, title: action.name) { urls in
                    model.services.dropActions.run(action, on: urls)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DropTile: View {
    let symbol: String
    let title: String
    let action: @MainActor @Sendable ([URL]) -> Void

    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(symbol: String, title: String, action: @escaping @MainActor @Sendable ([URL]) -> Void) {
        self.symbol = symbol
        self.title = title
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
            Text(title).font(.callout.weight(.semibold)).lineLimit(1).padding(.horizontal, 6)
        }
        .frame(width: SurfaceSizing.tileSize, height: SurfaceSizing.tileSize)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous).fill(
                .ink.opacity(targeted ? 0.22 : 0.08))
        )
        .scaleEffect(targeted && !reduceMotion ? 1.05 : 1)
        .animation(reduceMotion ? nil : .wispControl, value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: FileDrop.handler(action))
        #if DEBUG
            .onChange(of: targeted) { _, now in DropProbe.log.debug("probe: tile targeted \(now, privacy: .public)") }
        #endif
    }
}

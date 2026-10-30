import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Files parked in the tray: a summary with labelled actions above a row of file cards.
struct TrayPage: View {
    let model: NotchModel

    @State private var targeted = false

    private var tray: TrayStore { model.services.tray }

    var body: some View {
        Group {
            if tray.list.urls.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22))
                    Text("Drag files here to keep them handy")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
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

    static let cardSpacing: CGFloat = 6
    static var cardWidth: CGFloat { SurfaceSizing.trayItemWidth - cardSpacing }

    private var header: some View {
        let list = tray.list
        let allSelected = list.selected.count == list.urls.count
        return HStack(spacing: 6) {
            Text(tray.header)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            TrayAction(symbol: allSelected ? "checkmark.circle.fill" : "checkmark.circle") { tray.toggleSelectAll() }
                .help(allSelected ? "Deselect all" : "Select all")
            TrayAction(symbol: "airplayaudio", title: "AirDrop") { tray.airDrop(list.actionTargets) }
            TrayAction(symbol: "wand.and.stars", title: "Transform") {
                model.services.openTransform(list.actionTargets)
            }
            TrayAction(symbol: "doc.zipper", title: "Zip") { tray.zip(list.actionTargets) }
            TrayAction(symbol: "trash") { tray.removeSelectedOrAll() }
                .help(list.selected.isEmpty ? "Clear tray" : "Remove selected")
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.15), value: tray.header)
    }
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
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                if let title { Text(title).font(.system(size: 11, weight: .medium)) }
            }
            .padding(.horizontal, title == nil ? 0 : 9)
            .frame(minWidth: 24, minHeight: 24)
            .background(Capsule().fill(.white.opacity(hovering ? 0.2 : 0.1)))
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

    @State private var hovering = false

    var body: some View {
        let selected = tray.list.selected.contains(url)
        VStack(spacing: 3) {
            Group {
                if let image = tray.thumbnails[url] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").font(.system(size: 24))
                }
            }
            .frame(width: TrayPage.cardWidth - 12, height: 50)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 4, y: -4)
                }
            }
            .padding(.top, 6)
            Text(url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(tray.detail(for: url))
                .font(.system(size: 9))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 6)
        .frame(width: TrayPage.cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(selected ? 0.14 : hovering ? 0.1 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(selected ? 0.9 : 0), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Divider()
            Button("Remove from Tray") { tray.remove(url) }
        }
        .help(url.path)
    }
}

/// The last card in a tray with files: room for one more drop.
private struct DropMoreCard: View {
    let active: Bool
    /// Nil fills the remaining width.
    let width: CGFloat?

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
            Text("Drop more").font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(active ? 0.9 : 0.45))
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: .infinity)
        .overlay(DropOutline(active: active, cornerRadius: 12))
    }
}

private struct DropOutline: View {
    let active: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(active ? 0.6 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
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
            DropTile(symbol: "airplayaudio", title: "AirDrop") { tray.airDrop($0) }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DropTile: View {
    let symbol: String
    let title: String
    let action: @MainActor @Sendable ([URL]) -> Void

    @State private var targeted = false

    init(symbol: String, title: String, action: @escaping @MainActor @Sendable ([URL]) -> Void) {
        self.symbol = symbol
        self.title = title
        self.action = action
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .medium))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .frame(width: SurfaceSizing.tileSize, height: SurfaceSizing.tileSize)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(targeted ? 0.22 : 0.08))
        )
        .scaleEffect(targeted ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: targeted)
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: FileDrop.handler(action))
    }
}

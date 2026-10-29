import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// Files parked in the tray: thumbnails with selection, drag-out and file actions.
struct TrayPage: View {
    let model: NotchModel

    @State private var targeted = false

    private var tray: TrayStore { model.services.tray }

    var body: some View {
        HStack(spacing: 10) {
            if tray.list.urls.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 22))
                    Text("Drag files here to keep them handy")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous)
                        .strokeBorder(
                            .white.opacity(targeted ? 0.6 : 0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tray.list.urls, id: \.self) { url in
                            TrayItemView(url: url, tray: tray, services: model.services)
                        }
                    }
                    .padding(.vertical, 4)
                }
                actions
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted, perform: FileDrop.handler { tray.add($0) })
    }

    private var actions: some View {
        let list = tray.list
        let allSelected = !list.urls.isEmpty && list.selected.count == list.urls.count
        return VStack(spacing: 4) {
            ShelfButton(symbol: allSelected ? "checkmark.circle.fill" : "checkmark.circle", size: 13) {
                tray.toggleSelectAll()
            }
            .help("Select all")
            ShelfButton(symbol: "airplayaudio", size: 12) { tray.airDrop(list.actionTargets) }
                .help("AirDrop")
            ShelfButton(symbol: "wand.and.stars", size: 12) { model.services.openTransform(list.actionTargets) }
                .help("Transform")
            ShelfButton(symbol: "doc.zipper", size: 12) { tray.zip(list.actionTargets) }
                .help("Zip")
            ShelfButton(symbol: "trash", size: 12) { tray.removeSelectedOrAll() }
                .help(list.selected.isEmpty ? "Clear tray" : "Remove selected")
        }
    }
}

private struct TrayItemView: View {
    let url: URL
    let tray: TrayStore
    let services: AppServices

    @State private var hovering = false

    var body: some View {
        let selected = tray.list.selected.contains(url)
        VStack(spacing: 4) {
            Group {
                if let image = tray.thumbnails[url] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc").font(.system(size: 24))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 5, y: -5)
                }
            }
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering || selected ? 0.1 : 0))
        )
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

import AppKit
import ImageIO
import QuickLook
import SwiftUI
import WispCore

/// Clipboard history in the window: a searchable list (pinned first, then newest) with a
/// preview column beside it when the window is wide enough. Return copies, ⌘⌫ removes and,
/// without the preview column, Space opens a preview.
struct ClipboardPage: View {
    let store: ClipboardStore
    let preferences: Preferences
    let openSettings: () -> Void

    @State private var query = ""
    @State private var kind: ClipKind?
    @State private var selection: ClipItem.ID?
    @State private var confirmingClear = false
    @State private var quickLook: URL?
    @State private var previewing: ClipItem?
    @State private var copied: ClipItem.ID?

    var body: some View {
        let items = store.history.filtered(kind: kind, query: query)
        let selected = items.first { $0.id == selection }
        GeometryReader { proxy in
            let wide = WindowLayout.showsInspector(width: proxy.size.width)
            if items.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    list(items, wide: wide)
                    if wide {
                        Divider()
                        ClipPreview(item: selected, imageURL: selected.flatMap(store.imageURL(for:)))
                            .frame(width: WindowLayout.inspectorWidth)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search clipboard")
        .toolbar { toolbar(selected) }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear history", role: .destructive) { store.clear() }
        } message: {
            Text("Pinned items are kept.")
        }
        .quickLookPreview($quickLook)
        .sheet(item: $previewing) { item in
            VStack(spacing: 0) {
                ClipPreview(item: item, imageURL: store.imageURL(for: item))
                Divider()
                HStack {
                    Spacer()
                    Button("Done") { previewing = nil }.keyboardShortcut(.defaultAction)
                }
                .padding(12)
            }
            .frame(width: 420, height: 460)
        }
    }

    private func list(_ items: [ClipItem], wide: Bool) -> some View {
        List(selection: $selection) {
            let pinned = items.filter(\.pinned)
            if !pinned.isEmpty {
                Section("Pinned") { rows(pinned) }
            }
            let history = items.filter { !$0.pinned }
            if pinned.isEmpty {
                rows(history)
            } else if !history.isEmpty {
                Section("History") { rows(history) }
            }
        }
        .contextMenu(forSelectionType: ClipItem.ID.self) { ids in
            if let item = ids.first.flatMap(item(id:)) {
                Button("Copy") { copy(item) }
                Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                Divider()
                Button("Remove", role: .destructive) { remove(item) }
            }
        } primaryAction: { ids in
            if let item = ids.first.flatMap(item(id:)) { copy(item) }
        }
        .onKeyPress(.return) {
            guard let item = selection.flatMap(item(id:)) else { return .ignored }
            copy(item)
            return .handled
        }
        .onKeyPress(.space) {
            guard !wide, let item = selection.flatMap(item(id:)) else { return .ignored }
            if let url = store.imageURL(for: item) { quickLook = url } else { previewing = item }
            return .handled
        }
        .onKeyPress(keys: [.delete], phases: .down) { press in
            guard press.modifiers.contains(.command), let item = selection.flatMap(item(id:)) else { return .ignored }
            remove(item)
            return .handled
        }
    }

    private func rows(_ items: [ClipItem]) -> some View {
        ForEach(items) { item in
            ClipListRow(item: item, imageURL: store.imageURL(for: item), copied: copied == item.id)
                .tag(item.id)
        }
    }

    /// Why the list is empty: history off, nothing copied, or nothing matching.
    @ViewBuilder private var emptyState: some View {
        if !preferences.clipboardEnabled, store.history.items.isEmpty {
            ContentUnavailableView {
                Label("Clipboard history is off", systemImage: "doc.on.clipboard")
            } description: {
                Text("Turn it on to keep what you copy.")
            } actions: {
                Button("Clipboard settings", action: openSettings)
            }
        } else if store.history.items.isEmpty {
            ContentUnavailableView {
                Label("Nothing copied yet", systemImage: "doc.on.clipboard")
            } description: {
                Text("Text, links, images and colours you copy show up here.")
            }
        } else if query.isEmpty {
            ContentUnavailableView {
                Label("No items of this type", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing in the history matches this filter.")
            } actions: {
                Button("Show all") { kind = nil }
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    @ToolbarContentBuilder private func toolbar(_ selected: ClipItem?) -> some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Type", selection: $kind) {
                    Text("All").tag(ClipKind?.none)
                    Text("Text").tag(ClipKind?.some(.text))
                    Text("Links").tag(ClipKind?.some(.link))
                    Text("Images").tag(ClipKind?.some(.image))
                    Text("Colours").tag(ClipKind?.some(.color))
                }
                .pickerStyle(.inline)
            } label: {
                Label(
                    "Type",
                    systemImage: kind == nil
                        ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Show one type")
            Button(
                selected?.pinned == true ? "Unpin" : "Pin", systemImage: selected?.pinned == true ? "pin.slash" : "pin"
            ) {
                if let selected { store.togglePin(selected) }
            }
            .disabled(selected == nil)
            .help(selected?.pinned == true ? "Unpin" : "Pin")
            Button("Copy", systemImage: "doc.on.doc") {
                if let selected { copy(selected) }
            }
            .disabled(selected == nil)
            .help("Copy")
            Button("Clear history", systemImage: "trash") { confirmingClear = true }
                .disabled(store.history.items.allSatisfy(\.pinned))
                .help("Clear history")
        }
    }

    private func item(id: ClipItem.ID) -> ClipItem? {
        store.history.items.first { $0.id == id }
    }

    private func copy(_ item: ClipItem) {
        store.copy(item)
        copied = item.id
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if copied == item.id { copied = nil }
        }
    }

    private func remove(_ item: ClipItem) {
        if selection == item.id { selection = nil }
        store.remove(item)
    }
}

/// One history row: the kind's icon or a thumbnail, a one-line excerpt, the source app and
/// how long ago it was copied.
private struct ClipListRow: View {
    let item: ClipItem
    let imageURL: URL?
    let copied: Bool

    var body: some View {
        HStack(spacing: 10) {
            ClipThumbnail(item: item, imageURL: imageURL, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(ClipText.excerpt(item)).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 4) {
                    if let app = item.sourceApp {
                        Text(app)
                        Text("·")
                    }
                    Text(item.date, format: .relative(presentation: .named))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if copied {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.wispGreen)
                    .accessibilityLabel("Copied")
            } else if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            }
        }
        .padding(.vertical, 3)
    }
}

/// The selected item in full: text, image or colour swatch, then where and when it came from.
private struct ClipPreview: View {
    let item: ClipItem?
    let imageURL: URL?

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 16) {
                content(item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    detail("Type", ClipText.typeName(item.kind))
                    if let app = item.sourceApp { detail("From", app) }
                    detail("Copied", item.date.formatted(date: .abbreviated, time: .shortened))
                    if let size = ClipText.size(item) { detail("Size", size) }
                }
                .font(.system(size: 12))
            }
            .padding(16)
        } else {
            ContentUnavailableView(
                "No selection", systemImage: "doc.on.clipboard", description: Text("Pick an item to preview it."))
        }
    }

    @ViewBuilder private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            ClipThumbnail(item: item, imageURL: imageURL, size: nil)
        case .color:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ClipText.color(item) ?? .clear)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
                    .frame(height: 120)
                Text(item.text ?? "").font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .text, .link:
            ScrollView(.vertical) {
                Text(item.text ?? "")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// A clip's picture: the stored image, read off the main thread, or its kind's symbol. `size`
/// nil fits the space given.
private struct ClipThumbnail: View {
    let item: ClipItem
    let imageURL: URL?
    let size: CGFloat?

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                if size == nil {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(nsImage: image).resizable().scaledToFill()
                }
            } else if item.kind == .color, let color = ClipText.color(item) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color)
            } else {
                Image(systemName: ClipText.symbol(item.kind))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: imageURL) {
            // The last clip's picture must not stay up while this one loads, or if it's gone.
            image = nil
            guard let imageURL else { return }
            // Twice the points it's drawn at, for Retina; the preview column is at most about 450 pt.
            image = await ClipImageLoader.thumbnail(of: imageURL, maxPixels: Int((size ?? 450) * 2))
        }
    }
}

/// A stored clipboard image decoded as a thumbnail off the main thread, or `placeholder` until
/// it's ready. Screenshots can be tens of megabytes, too much to read in a view's body.
struct StoredClipImage<Placeholder: View>: View {
    let url: URL
    /// The longest side to decode, in pixels: twice the points it's drawn at.
    let maxPixels: Int
    let mode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: mode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            image = await ClipImageLoader.thumbnail(of: url, maxPixels: maxPixels)
        }
    }
}

enum ClipImageLoader {
    static func thumbnail(of url: URL, maxPixels: Int) async -> NSImage? {
        let image = await Task.detached { decode(url, maxPixels: maxPixels) }.value
        return image.map { NSImage(cgImage: $0, size: .zero) }
    }

    /// A screenshot can be tens of megapixels; decoding only a thumbnail keeps the list light.
    private nonisolated static func decode(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Wording and symbols for clipboard items.
private enum ClipText {
    static func symbol(_ kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .color: "paintpalette"
        }
    }

    static func typeName(_ kind: ClipKind) -> String {
        switch kind {
        case .text: "Text"
        case .link: "Link"
        case .image: "Image"
        case .color: "Colour"
        }
    }

    static func excerpt(_ item: ClipItem) -> String {
        let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Image" : text.replacingOccurrences(of: "\n", with: " ")
    }

    static func size(_ item: ClipItem) -> String? {
        if let pixels = item.imagePixelSize {
            return "\(Int(pixels.width)) × \(Int(pixels.height)) pixels"
        }
        return item.text.map { "\($0.count) characters" }
    }

    static func color(_ item: ClipItem) -> Color? {
        guard let rgb = item.text.flatMap({ ClipClassifier.rgb(fromHex: $0.trimmingCharacters(in: .whitespaces)) })
        else { return nil }
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

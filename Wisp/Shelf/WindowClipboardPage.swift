import AppKit
import ImageIO
import QuickLook
import SwiftUI
import WispCore

/// Clipboard history in the window: the apps clips came from down the side, filters and a
/// search on top, and the clips as cards. Click picks one, ⌘-click picks several to copy
/// together, a line each; double-click or Return copies, Space previews, ⌘⌫ removes.
struct ClipboardPage: View {
    let store: ClipboardStore
    let preferences: Preferences
    let openSettings: () -> Void

    /// What the chips at the top show.
    enum Show: Hashable {
        case all
        case pinned
        case kind(ClipKind)
    }

    @State private var query = ""
    @State private var show: Show = .all
    @State private var app: String?
    @State private var selection: Set<ClipItem.ID> = []
    /// The selection in the order it was picked, so Copy together keeps that order.
    @State private var pickOrder: [ClipItem.ID] = []
    @State private var confirmingClear = false
    @State private var quickLook: URL?
    @State private var previewing: ClipItem?
    @State private var copied: ClipItem.ID?
    @State private var width: CGFloat = 0
    @State private var gridWidth: CGFloat = 0
    @FocusState private var gridFocused: Bool
    @FocusState private var searching: Bool

    /// What the filters, the app and the search leave.
    private var items: [ClipItem] {
        let kind: ClipKind? = if case .kind(let kind) = show { kind } else { nil }
        return store.history.filtered(kind: kind, query: query).filter { item in
            (show != .pinned || item.pinned) && (app == nil || item.sourceApp == app)
        }
    }

    var body: some View {
        let items = items
        let picked = ordered(selection, in: items)
        let all = store.history.items
        WindowPageFrame {
            WindowPageHeader(
                symbol: "doc.on.clipboard", tint: .gray, title: "Clipboard",
                subtitle: "Everything you copied, ready to paste again.",
                count: all.count == 1 ? "1 clip" : "\(all.count) clips"
            ) { headerActions(picked: picked) }
        } content: {
            HStack(alignment: .top, spacing: WindowLayout.spacing) {
                if WindowLayout.masterDetail(width: width), !all.isEmpty {
                    appsColumn(all).frame(width: 230)
                }
                VStack(alignment: .leading, spacing: 12) {
                    filterBar(all)
                    searchField(count: all.count)
                    if items.isEmpty {
                        emptyState.frame(maxHeight: .infinity).windowCardBackground()
                    } else {
                        grid(items)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
        }
        .onChange(of: selection) { _, picks in
            pickOrder = PickOrder.update(pickOrder, selection: picks, listOrder: items.map(\.id))
        }
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

    // MARK: Header and filters

    @ViewBuilder private func headerActions(picked: [ClipItem]) -> some View {
        let selected = picked.count == 1 ? picked.first : nil
        Button(selected?.pinned == true ? "Unpin" : "Pin", systemImage: selected?.pinned == true ? "pin.slash" : "pin")
        {
            if let selected { store.togglePin(selected) }
        }
        .labelStyle(.iconOnly)
        .disabled(selected == nil)
        .help(selected?.pinned == true ? "Unpin" : "Pin")
        Button("Clear history", systemImage: "trash") { confirmingClear = true }
            .labelStyle(.iconOnly)
            .disabled(store.history.items.allSatisfy(\.pinned))
            .help("Clear history (keeps pinned)")
        WindowPrimaryButton(title: picked.count > 1 ? "Copy \(picked.count) together" : "Copy", symbol: "doc.on.doc") {
            if picked.count > 1 { copyTogether(picked) } else if let selected { copy(selected) }
        }
        .disabled(picked.isEmpty || (picked.count > 1 && picked.allSatisfy { $0.text == nil }))
    }

    private func filterBar(_ all: [ClipItem]) -> some View {
        let counts = ClipCounts(all)
        let pinned = all.filter(\.pinned).count
        // Scrolls sideways on a narrow page rather than breaking the chips' words.
        return ScrollView(.horizontal) {
            HStack(spacing: 4) {
                chip("All", count: counts.all, value: .all)
                chip("Pinned", count: pinned, value: .pinned)
                chip("Text", count: counts[.text], value: .kind(.text))
                chip("Links", count: counts[.link], value: .kind(.link))
                chip("Images", count: counts[.image], value: .kind(.image))
                chip("Colours", count: counts[.color], value: .kind(.color))
            }
            .padding(4)
            .background(Capsule().fill(.primary.opacity(0.08)))
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private func chip(_ title: String, count: Int, value: Show) -> some View {
        let on = show == value
        return Button {
            show = value
        } label: {
            HStack(spacing: 5) {
                Text(title).fontWeight(on ? .semibold : .regular)
                Text("\(count)").foregroundStyle(on ? Color.primary.opacity(0.7) : Color.secondaryText)
            }
            .wispFont(.callout).monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .wispHover(shape: Capsule())
            .background(Capsule().fill(on ? Color.primary.opacity(0.12) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func searchField(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
            TextField(count == 1 ? "Search 1 clip" : "Search among \(count) clips", text: $query)
                .textFieldStyle(.plain)
                .focused($searching)
                .onKeyPress(.escape) { clearSearch() }
            if !query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondaryText)
                    .padding(2)
                    .wispHover(shape: Circle())
                    .padding(-2)
            }
        }
        .wispFont(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(.primary.opacity(0.08)))
        .frame(maxWidth: 520)
        .findShortcut($searching)
    }

    private func clearSearch() -> KeyPress.Result {
        guard !query.isEmpty else { return .ignored }
        query = ""
        return .handled
    }

    /// Cards in a row of the grid, for moving up and down with the arrow keys.
    private var gridColumns: Int {
        WindowLayout.columns(width: Double(gridWidth), minimum: 200, spacing: 12, maximum: 99)
    }

    private func appsColumn(_ all: [ClipItem]) -> some View {
        WindowCard(title: "Apps", symbol: "square.grid.2x2", tint: .indigo, fills: true) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 2) {
                    appRow(name: "All apps", bundleID: nil, count: all.count, selected: app == nil) { app = nil }
                    ForEach(ClipCounts.apps(all)) { entry in
                        appRow(
                            name: entry.name, bundleID: entry.bundleID, count: entry.count, selected: app == entry.name
                        ) { app = entry.name }
                    }
                }
            }
            .scrollFade()
        }
    }

    private func appRow(
        name: String, bundleID: String?, count: Int, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon = bundleID.flatMap(Self.icon) {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    Image(systemName: bundleID == nil && name == "All apps" ? "asterisk" : "app")
                        .wispFont(.callout, weight: .semibold)
                        .foregroundStyle(Color.wispViolet)
                        .frame(width: 20, height: 20)
                }
                Text(name).wispFont(.body).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").wispFont(.subheadline).monospacedDigit().foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .wispHover(cornerRadius: SurfaceRadius.row)
            .background(
                RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                    .fill(selected ? Color.wispViolet.opacity(0.22) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func icon(_ bundleID: String) -> NSImage? {
        RingIconCache.shared.image(for: .app(bundleID: bundleID))
    }

    // MARK: Grid

    private func grid(_ items: [ClipItem]) -> some View {
        let picked = ordered(selection, in: items)
        return ScrollView(.vertical) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12, alignment: .top)],
                alignment: .leading, spacing: 12
            ) {
                ForEach(items) { item in
                    ClipTile(
                        item: item, store: store, selected: selection.contains(item.id),
                        pickNumber: picked.count > 1 ? picked.firstIndex { $0.id == item.id }.map { $0 + 1 } : nil,
                        copied: copied == item.id
                    )
                    .frame(height: 230)
                    .onTapGesture(count: 2) { copy(item) }
                    .onTapGesture { pick(item) }
                    .accessibilityAction { copy(item) }
                    .accessibilityAction(named: item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                    .accessibilityAction(named: "Remove") { remove(item) }
                    .contextMenu { menu(for: item, in: items) }
                }
            }
            .padding(2)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width - 4
            } action: {
                gridWidth = $0
            }
        }
        .scrollFade()
        .background {
            // ⌘A picks every card shown, only while the grid has focus so the search field keeps its own.
            Button("Select all") { selection = Set(items.map(\.id)) }
                .keyboardShortcut(gridFocused ? KeyboardShortcut("a", modifiers: .command) : nil)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onAppear { gridFocused = true }
        .onKeyPress(.return) {
            let many = ordered(selection, in: items)
            if many.count > 1 {
                copyTogether(many)
            } else if let item = many.first {
                copy(item)
            } else {
                return .ignored
            }
            return .handled
        }
        .onKeyPress(.space) {
            guard selection.count == 1, let item = selection.first.flatMap(item(id:)) else { return .ignored }
            if let url = store.imageURL(for: item) { quickLook = url } else { previewing = item }
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            move(by: press.key == .leftArrow ? -1 : 1, in: items)
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            move(by: press.key == .upArrow ? -gridColumns : gridColumns, in: items)
            return .handled
        }
        .onKeyPress(.escape) { clearSearch() }
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { _ in
            let many = ordered(selection, in: items)
            guard !many.isEmpty else { return .ignored }
            // One item goes even when pinned, as before; several leave the pinned ones.
            if many.count == 1 { many.forEach(remove) } else { many.filter { !$0.pinned }.forEach(remove) }
            return .handled
        }
    }

    @ViewBuilder private func menu(for item: ClipItem, in items: [ClipItem]) -> some View {
        let many = ordered(selection, in: items)
        if many.count > 1, selection.contains(item.id) {
            Button("Copy \(many.count) together") { copyTogether(many) }
            Divider()
            // Pinned items stay; they're unpinned first to be removed.
            let unpinned = many.filter { !$0.pinned }
            Button("Remove \(unpinned.count) items", role: .destructive) { unpinned.forEach(remove) }
                .disabled(unpinned.isEmpty)
        } else {
            Button("Copy") { copy(item) }
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("Preview") {
                if let url = store.imageURL(for: item) { quickLook = url } else { previewing = item }
            }
            Divider()
            Button("Remove", role: .destructive) { remove(item) }
        }
    }

    /// A click picks one; ⌘-click adds or takes away one, to copy several together.
    private func pick(_ item: ClipItem) {
        gridFocused = true
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else {
            selection = [item.id]
        }
    }

    private func move(by step: Int, in items: [ClipItem]) {
        // With nothing picked, any arrow starts at the first card (or the last, going back).
        let current = items.firstIndex { selection.contains($0.id) }
        let next = current.map { min(max($0 + step, 0), items.count - 1) } ?? (step > 0 ? 0 : items.count - 1)
        guard items.indices.contains(next) else { return }
        selection = [items[next].id]
    }

    /// Why there are no cards: history off, nothing copied, or nothing matching.
    @ViewBuilder private var emptyState: some View {
        if !preferences.clipboardEnabled, store.history.items.isEmpty {
            WindowEmptyState(
                symbol: "doc.on.clipboard", title: "Clipboard history is off",
                message: "Turn it on to keep what you copy, on this Mac only."
            ) {
                WindowPrimaryButton(title: "Clipboard settings", symbol: "gearshape", action: openSettings)
            }
        } else if store.history.items.isEmpty {
            WindowEmptyState(
                symbol: "doc.on.clipboard", title: "Nothing copied yet",
                message: "Text, links, images and colours you copy show up here.")
        } else if query.isEmpty {
            WindowEmptyState(
                symbol: "line.3.horizontal.decrease.circle", title: "Nothing here",
                message: "No clips match this filter."
            ) {
                Button("Show all") {
                    show = .all
                    app = nil
                }
            }
        } else {
            WindowEmptyState(
                symbol: "magnifyingglass", title: "No results for \u{201C}\(query)\u{201D}",
                message: "Check the spelling or try another word.")
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

    /// The picked items in the order they were picked.
    private func ordered(_ ids: Set<ClipItem.ID>, in items: [ClipItem]) -> [ClipItem] {
        let shown = items
        let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return PickOrder.update(pickOrder, selection: ids, listOrder: shown.map(\.id)).compactMap { byID[$0] }
    }

    private func copyTogether(_ items: [ClipItem]) {
        guard store.copyTogether(items) else { return }
        selection = []
    }

    private func remove(_ item: ClipItem) {
        selection.remove(item.id)
        store.remove(item)
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
                .wispFont(.callout)
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
                Text(item.text ?? "").wispFont(.title3, weight: .semibold, design: .monospaced)
                    .textSelection(.enabled)
            }
        case .text, .link:
            ScrollView(.vertical) {
                Text(item.text ?? "")
                    .wispFont(.body)
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

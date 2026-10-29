import AppKit
import SwiftUI
import WispCore

/// Clipboard history: type tabs, search, and a row of typed cards.
struct ClipboardView: View {
    @Bindable var model: ClipboardPanelModel
    let paste: (ClipItem) -> Void
    let close: () -> Void

    @FocusState private var searchFocused: Bool

    init(model: ClipboardPanelModel, paste: @escaping (ClipItem) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.paste = paste
        self.close = close
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            cards
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.1)))
        )
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onAppear { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            tab("Clipboard", kind: nil)
            tab("Text", kind: .text)
            tab("Links", kind: .link)
            tab("Images", kind: .image)
            tab("Colors", kind: .color)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.secondaryText)
                TextField("Search", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .frame(width: 180)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.08)))
            Menu {
                Button("Clear History (keeps pinned)") { model.store.clear() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    private func tab(_ title: String, kind: ClipKind?) -> some View {
        Button {
            model.kind = kind
            model.selectedID = model.items.first?.id
        } label: {
            Text(title)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(model.kind == kind ? 0.18 : 0)))
        }
        .buttonStyle(.plain)
    }

    private var cards: some View {
        let items = model.items
        let selected = model.selectedItem?.id
        return Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 26))
                    Text(model.query.isEmpty ? "Copy something and it shows up here" : "No matches")
                        .font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(items) { item in
                                ClipCard(item: item, store: model.store, selected: item.id == selected)
                                    .id(item.id)
                                    .onTapGesture(count: 2) { paste(item) }
                                    .onTapGesture { model.selectedID = item.id }
                                    .contextMenu {
                                        Button("Paste") { paste(item) }
                                        Button("Copy") { model.store.copy(item) }
                                        Button(item.pinned ? "Unpin" : "Pin") { model.store.togglePin(item) }
                                        Divider()
                                        Button("Delete") { model.store.remove(item) }
                                    }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: selected) { _, id in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }
}

private struct ClipCard: View {
    let item: ClipItem
    let store: ClipboardStore
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(12)
        .frame(width: 200, height: 220)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(item.sourceApp ?? "Unknown").font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer()
            if item.pinned { Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.wispAmber) }
            TimelineView(.everyMinute) { context in
                Text(RelativeAge.short(from: item.date, to: context.date))
                    .font(.system(size: 10)).foregroundStyle(Color.secondaryText)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "").font(.system(size: 12)).lineLimit(9)
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link").font(.system(size: 22)).foregroundStyle(Color.accentColor)
                Text(URL(string: item.text ?? "")?.host() ?? item.text ?? "")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.text ?? "").font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(4)
            }
        case .image:
            if let url = store.imageURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .color:
            let rgb = ClipClassifier.rgb(fromHex: item.text ?? "")
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    Color(
                        red: Double(rgb?.red ?? 0) / 255, green: Double(rgb?.green ?? 0) / 255,
                        blue: Double(rgb?.blue ?? 0) / 255)
                )
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.2)))
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.secondaryText)
            .lineLimit(1)
    }

    private var footerText: String {
        switch item.kind {
        case .text: return "\(item.text?.count ?? 0) characters"
        case .link: return "Link"
        case .image:
            guard let size = item.imagePixelSize else { return "Image" }
            return "\(Int(size.width)) × \(Int(size.height))"
        case .color:
            guard let rgb = ClipClassifier.rgb(fromHex: item.text ?? "") else { return item.text ?? "" }
            return "\(item.text ?? "")  ·  RGB \(rgb.red) \(rgb.green) \(rgb.blue)"
        }
    }

    private var appIcon: NSImage? {
        guard let id = item.sourceBundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

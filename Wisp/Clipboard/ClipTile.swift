import AppKit
import SwiftUI
import WispCore

/// A clip as a card, shared by the clipboard panel and the window's Clipboard page: pictures
/// and colours fill the top, text reads as text (code in a monospaced box), links show their
/// site, and the foot says where it came from and when.
struct ClipTile: View {
    let item: ClipItem
    let store: ClipboardStore
    let selected: Bool
    /// Its place among cards picked to paste or copy together.
    var pickNumber: Int?
    /// Briefly true after a copy, to say so on the card.
    var copied = false

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private static let radius = SurfaceRadius.card

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            media
            VStack(alignment: .leading, spacing: 8) {
                bodyText.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(hovering ? 0.09 : 0.06) : Color.white.opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(selected ? Color.wispViolet : .primary.opacity(0.08), lineWidth: selected ? 2 : 0.5)
        )
        .overlay(alignment: .topTrailing) { badges }
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Parts

    /// The picture or colour across the top, for clips that have one.
    @ViewBuilder private var media: some View {
        switch item.kind {
        case .image:
            ZStack {
                Rectangle().fill(.primary.opacity(0.05))
                if let url = store.imageURL(for: item) {
                    StoredClipImage(url: url, maxPixels: 640, mode: .fill) { Color.clear }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 112)
            .frame(maxWidth: .infinity)
            .clipped()
        case .color:
            Rectangle()
                .fill(swatch)
                .frame(height: 112)
        case .text, .link:
            EmptyView()
        }
    }

    @ViewBuilder private var bodyText: some View {
        switch item.kind {
        case .text:
            let text = item.text ?? ""
            if ClipLook.isCode(text) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(7)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                            .fill(.primary.opacity(0.06)))
            } else {
                Text(text).font(.callout).lineLimit(8)
            }
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.wispViolet)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                            .fill(Color.wispViolet.opacity(0.15)))
                Text(URL(string: item.text ?? "")?.host() ?? item.text ?? "")
                    .font(.body.weight(.semibold)).lineLimit(2)
                Text(item.text ?? "").font(.subheadline).foregroundStyle(Color.secondaryText).lineLimit(3)
            }
        case .image:
            Text(imageTitle).font(.callout.weight(.medium)).lineLimit(2)
        case .color:
            Text(item.text ?? "").font(.system(.callout, design: .monospaced).weight(.medium))
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let icon = appIcon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: kindSymbol).font(.caption).foregroundStyle(Color.secondaryText)
            }
            TimelineView(.everyMinute) { context in
                Text(footerText(now: context.date))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.wispViolet)
            }
        }
    }

    @ViewBuilder private var badges: some View {
        HStack(spacing: 4) {
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.orange))
                    .accessibilityHidden(true)
            }
            if let pickNumber {
                Text("\(pickNumber)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.wispViolet))
            }
        }
        .padding(8)
    }

    // MARK: Text

    private var swatch: Color {
        let rgb = ClipClassifier.rgb(fromHex: item.text ?? "")
        return Color(
            red: Double(rgb?.red ?? 0) / 255, green: Double(rgb?.green ?? 0) / 255, blue: Double(rgb?.blue ?? 0) / 255)
    }

    private var imageTitle: String {
        guard let size = item.imagePixelSize else { return "Image" }
        return "Image, \(Int(size.width)) × \(Int(size.height))"
    }

    private func footerText(now: Date) -> String {
        let age = RelativeAge.short(from: item.date, to: now)
        guard let app = item.sourceApp, !app.isEmpty else { return age }
        return "\(app) · \(age)"
    }

    private var kindSymbol: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .color: "paintpalette"
        }
    }

    /// Cached, since every card asks on every redraw.
    private var appIcon: NSImage? {
        item.sourceBundleID.flatMap { RingIconCache.shared.image(for: .app(bundleID: $0)) }
    }

    private var accessibilityText: String {
        let what: String =
            switch item.kind {
            case .text: item.text ?? ""
            case .link: "Link, \(item.text ?? "")"
            case .image: imageTitle
            case .color: "Colour \(item.text ?? "")"
            }
        let from = item.sourceApp.map { ", from \($0)" } ?? ""
        return (item.pinned ? "Pinned, " : "") + String(what.prefix(200)) + from
    }
}

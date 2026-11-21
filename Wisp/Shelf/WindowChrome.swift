import SwiftUI
import WispCore

/// A card on a window page: a small tinted icon, a title and an optional count, then the
/// card's content. Every window card shares this fill and radius.
struct WindowCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    var count: Int?
    /// Opens the card's own page; nil when there's none.
    var open: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .windowCardBackground()
    }

    @ViewBuilder private var header: some View {
        let label = HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint, size: 24)
            Text(title).font(.headline).foregroundStyle(.primary)
            Spacer(minLength: 8)
            if let count {
                Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(Color.secondaryText)
            }
            if open != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        if let open {
            Button(action: open) { label.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("Open \(title)")
                .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
                .accessibilityHint("Opens its page")
        } else {
            label.accessibilityElement(children: .combine)
        }
    }
}

extension View {
    /// The fill and hairline of a card in the window: a step up from the window's background,
    /// solid, so it reads the same over any desktop.
    func windowCardBackground() -> some View {
        modifier(WindowCardBackground())
    }
}

private struct WindowCardBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous)
        content
            .background(shape.fill(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.75)))
            .overlay(shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.08), lineWidth: 0.5))
    }
}

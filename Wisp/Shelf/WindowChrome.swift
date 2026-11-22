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
    /// The card's least height, so cards in a row line up.
    var minHeight: CGFloat?
    /// Takes all the height it's offered, for a card that fills a page's column.
    var fills = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
                .frame(
                    maxWidth: .infinity, maxHeight: fills || minHeight != nil ? .infinity : nil, alignment: .topLeading)
        }
        .padding(16)
        .frame(minHeight: minHeight, maxHeight: fills ? .infinity : nil, alignment: .top)
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
                .accessibilityAddTraits(.isHeader)
        } else {
            label.accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

extension View {
    /// ⌘F puts the cursor in the search field `focus` is bound to, as in Finder and Mail.
    func findShortcut(_ focus: FocusState<Bool>.Binding) -> some View {
        background {
            Button("Find") { focus.wrappedValue = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

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
        // Light mode: solid white with a clear edge and a soft shadow, so cards stand off the
        // light grey window; dark mode: a step up from the window with a faint edge.
        let light = scheme != .dark
        content
            .background(
                shape.fill(light ? Color.white : Color.white.opacity(0.05))
                    .shadow(color: .black.opacity(light ? 0.06 : 0), radius: 6, y: 1)
            )
            .overlay(
                shape.strokeBorder(
                    Color.primary.opacity(contrast == .increased ? 0.35 : light ? 0.12 : 0.08),
                    lineWidth: light ? 0.75 : 0.5))
    }
}

extension View {
    /// On macOS 26 and later, content scrolling under the toolbar stops at a hard edge rather
    /// than showing through its title and buttons. Put it on the page's scroll view.
    func windowScrollEdge() -> some View {
        modifier(HardTopScrollEdge())
    }
}

private struct HardTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
    }
}

// MARK: Page

/// The title block at the top of a window page: icon, title, a line on what it's for, an
/// optional count, and the page's main actions on the right.
struct WindowPageHeader<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var count: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            IconTile(symbol: symbol, tint: tint, size: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.largeTitle.bold()).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(Color.secondaryText).lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let count {
                Text(count)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.primary.opacity(0.08)))
            }
            HStack(spacing: 8) { actions }
                .controlSize(.large)
        }
    }
}

extension WindowPageHeader where Actions == EmptyView {
    init(symbol: String, tint: Color, title: String, subtitle: String, count: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, subtitle: subtitle, count: count) { EmptyView() }
    }
}

/// A primary action in a page header: violet and filled.
struct WindowPrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(.borderedProminent)
        .tint(.wispViolet)
    }
}

/// A scrolling window page: the header, then content inside the page margins. `content` gets
/// the width it has to lay out in. The scroll view is the root, so the toolbar keeps a clean
/// edge over it.
struct WindowWidgetPage<Header: View, Content: View>: View {
    enum Width {
        /// Uses the whole detail, for grids.
        case full
        /// Stops at a readable width, for lists and text.
        case readable
    }

    var width: Width = .full
    @ViewBuilder let header: Header
    @ViewBuilder let content: (CGFloat) -> Content
    @State private var available: CGFloat = 0

    var body: some View {
        let inner =
            width == .readable
            ? WindowLayout.readableWidth(available: available) : max(available - 2 * WindowLayout.margin, 0)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                header
                content(inner)
            }
            .frame(width: inner, alignment: .topLeading)
            .padding(WindowLayout.margin)
            .frame(maxWidth: .infinity, alignment: width == .readable ? .top : .topLeading)
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            available = $0
        }
        .windowScrollEdge()
    }
}

extension WindowWidgetPage where Header == EmptyView {
    init(width: Width = .full, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.init(width: width, header: { EmptyView() }, content: content)
    }
}

/// A page that lays itself out to fill the window (a list beside a detail, a grid of hours):
/// the header above, then content taking the rest, without an outer scroll.
struct WindowPageFrame<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(WindowLayout.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Pieces

/// A count that filters what a page lists: tap to show only those.
struct WindowStatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(tint.gradient))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(value)").font(.title2.weight(.semibold).monospacedDigit())
                    Text(label).font(.subheadline).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .windowCardBackground()
            .overlay(
                RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous)
                    .strokeBorder(tint, lineWidth: selected ? 2 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// What a page or card shows when it has nothing yet, or needs a permission: kept inside the
/// page's layout, so the page doesn't collapse to a lone symbol.
struct WindowEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(.largeTitle).weight(.light))
                .foregroundStyle(Color.secondaryText)
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 8) { actions }
                .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityElement(children: .contain)
    }
}

extension WindowEmptyState where Actions == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// A row in a window list: a tinted glyph, a title and a line under it, and something on the
/// right. Highlights on hover and when selected.
struct WindowListRow<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String?
    var selected = false
    @ViewBuilder let accessory: Accessory
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous).fill(tint.opacity(0.15))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.row + 2, style: .continuous)
                .fill(selected ? Color.wispViolet.opacity(0.22) : .primary.opacity(hovering ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension WindowListRow where Accessory == EmptyView {
    init(symbol: String, tint: Color, title: String, subtitle: String? = nil, selected: Bool = false) {
        self.init(symbol: symbol, tint: tint, title: title, subtitle: subtitle, selected: selected) { EmptyView() }
    }
}

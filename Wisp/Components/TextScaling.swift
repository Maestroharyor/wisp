import SwiftUI
import WispCore

extension EnvironmentValues {
    /// The Text size setting's factor. Only the window and Settings set it; the notch stays at 1.
    @Entry var wispTextScale: Double = 1
}

extension View {
    /// A text style that grows with the Text size setting. Dynamic Type sizes don't change text
    /// on macOS, so this scales the style's point size instead.
    func wispFont(
        _ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil
    ) -> some View {
        modifier(ScaledTextStyle(style: style, weight: weight, design: design))
    }

    /// Default text for a whole window, so labels without their own font grow too.
    func wispBaseFont() -> some View {
        modifier(ScaledBaseFont())
    }
}

private struct ScaledTextStyle: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let design: Font.Design?
    @Environment(\.wispTextScale) private var scale

    func body(content: Content) -> some View {
        content.font(font)
    }

    private var font: Font {
        // The real text style at the default size, so nothing shifts for most people.
        if scale == 1 { return .system(style, design: design, weight: weight) }
        let size = TextStyleSize(style)
        let fallback: Font.Weight = size.isBold ? .bold : .regular
        return .system(size: size.points(scale: scale), weight: weight ?? fallback, design: design ?? .default)
    }
}

private struct ScaledBaseFont: ViewModifier {
    @Environment(\.wispTextScale) private var scale

    func body(content: Content) -> some View {
        if scale == 1 {
            content
        } else {
            content.font(.system(size: TextStyleSize.body.points(scale: scale)))
        }
    }
}

extension TextStyleSize {
    init(_ style: Font.TextStyle) {
        switch style {
        case .largeTitle: self = .largeTitle
        case .title: self = .title
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .callout: self = .callout
        case .subheadline: self = .subheadline
        case .footnote: self = .footnote
        case .caption: self = .caption
        case .caption2: self = .caption2
        default: self = .body
        }
    }
}

import SwiftUI
import WispCore

/// A row of theme swatches; each shows its accent and glow as a split circle.
struct ThemePicker: View {
    @Bindable var preferences: Preferences

    var body: some View {
        HStack(spacing: 14) {
            ForEach(ThemeID.allCases, id: \.self) { id in
                let palette = ThemeCatalog.palette(
                    for: id, custom: ThemePalette(accent: preferences.customAccent, glow: preferences.customGlow))
                let selected = preferences.theme == id
                Button {
                    preferences.theme = id
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(rgb: palette.accent), Color(rgb: palette.glow)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.white.opacity(selected ? 0.9 : 0.15), lineWidth: 2))
                            .padding(2)
                            .overlay(
                                Circle().strokeBorder(selected ? Color(rgb: palette.accent) : .clear, lineWidth: 2))
                        Text(ThemeCatalog.title(for: id))
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ThemeCatalog.title(for: id))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Binds a stored RGB to SwiftUI's colour picker.
extension Binding where Value == RGB {
    var color: Binding<Color> {
        Binding<Color>(
            get: { Color(rgb: wrappedValue) },
            set: { if let rgb = RGB(color: $0) { wrappedValue = rgb } })
    }
}

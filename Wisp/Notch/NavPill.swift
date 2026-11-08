import SwiftUI
import WispCore

/// Floating capsule under the open shelf: Home, Tray (with count), Media, Widgets.
struct NavPill: View {
    let model: NotchModel

    var body: some View {
        if model.preferences.appearance.navPill == .dots { dots } else { tabs }
    }

    /// Labels go into the free space beside the pill, away from the shelf: below it, or above
    /// it on the bottom edge where the pill sits over the shelf.
    private var hintEdge: HoverHint.Edge {
        model.layout.edge == .bottom ? .top : .bottom
    }

    private var pages: [(ShelfPage, String)] {
        [(.home, "Home"), (.tray, "Tray"), (.media, "Media"), (.widgets, "Widgets")]
    }

    /// Four small dots in a slim capsule, for a quieter shelf.
    private var dots: some View {
        HStack(spacing: 2) {
            ForEach(pages, id: \.0) { page, name in
                Button {
                    model.page = page
                } label: {
                    Circle()
                        .fill(model.page == page ? model.accent : .white.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHint(name, edge: hintEdge)
                .accessibilityLabel(name)
            }
            formMenu.scaleEffect(0.7).frame(width: 22, height: 18)
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color(white: 0.2).opacity(0.92)))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab("house.fill", name: "Home", selected: model.page == .home) { model.page = .home }
            tab("tray.fill", name: "Tray", selected: model.page == .tray, badge: model.services.tray.count) {
                model.page = .tray
            }
            tab("music.note", name: "Media", selected: model.page == .media) { model.page = .media }
            tab("square.grid.2x2.fill", name: "Widgets", selected: model.page == .widgets) { model.page = .widgets }
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 16)
            formMenu
        }
        .padding(4)
        .background(
            Capsule().fill(Color(white: 0.32).opacity(0.92))
                .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        .foregroundStyle(.white)
    }

    /// Switches Wisp between notch, corner, bottom, side and orb on this display.
    private var formMenu: some View {
        Menu {
            FormMenuItems(model: model)
        } label: {
            Image(systemName: model.form.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverHint("Change form", edge: hintEdge, help: "Change form")
        .accessibilityLabel("Form: \(model.form.title)")
    }

    private func tab(
        _ symbol: String, name: String, selected: Bool, badge: Int = 0, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 38, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(
                        model.accent.opacity(selected ? 0.85 : 0))
                )
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Capsule().fill(Color.accentColor))
                            .offset(x: 2, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHint(name, edge: hintEdge)
        .accessibilityLabel(badge > 0 ? "\(name), \(badge) file\(badge == 1 ? "" : "s")" : name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The forms Wisp can switch to on this display, for the nav pill's menu and the window's toolbar.
struct FormMenuItems: View {
    let model: NotchModel

    var body: some View {
        ForEach(model.forms) { form in
            Button {
                model.onSetForm(form)
            } label: {
                Label(form.title, systemImage: form == model.form ? "checkmark" : form.symbol)
            }
        }
    }
}

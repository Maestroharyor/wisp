import SwiftUI

/// A card's text button ("Later", "Join", "Open") on a capsule. The padding and capsule sit
/// inside the button, so the whole capsule takes the click, not only the title.
struct CapsuleButton: View {
    let title: String
    /// Violet with white text, for the card's main action.
    let prominent: Bool
    let action: () -> Void

    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.foreground))
                .padding(.horizontal, prominent ? 14 : 12)
                .frame(height: 28)
                .background(Capsule().fill(prominent ? Color.wispViolet : .ink.opacity(0.14)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

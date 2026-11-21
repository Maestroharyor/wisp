import SwiftUI

/// A small spinner with a word, centred in the space it's given, for the moment before a
/// widget's first reading lands.
struct LoadingLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout).foregroundStyle(Color.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

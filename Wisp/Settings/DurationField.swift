import SwiftUI
import WispCore

/// A text field that takes typed durations ("25", "1h30m", "90s") and shows them back
/// tidied. Anything it can't read is put back as it was.
struct DurationField: View {
    let title: String
    @Binding var seconds: Double
    var range: ClosedRange<Double> = 60...10_800

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField("25m", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onAppear { text = DurationText.text(for: seconds) }
        }
    }

    private func commit() {
        if let parsed = DurationText.seconds(from: text) {
            seconds = min(max(parsed, range.lowerBound), range.upperBound)
        }
        text = DurationText.text(for: seconds)
    }
}

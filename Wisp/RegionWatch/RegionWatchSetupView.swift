import SwiftUI
import WispCore

/// Chooses what the new watch waits for, after the region is picked.
struct RegionWatchSetupView: View {
    enum Choice: String, CaseIterable, Identifiable {
        case changed
        case text
        case still

        var id: Self { self }

        var title: String {
            switch self {
            case .changed: "Changes"
            case .text: "Shows text"
            case .still: "Stops changing"
            }
        }
    }

    static let stillChoices: [Int] = [5, 10, 30, 60, 120, 300]

    let appName: String
    let start: (RegionWatchRule) -> Void
    let cancel: () -> Void

    @State private var choice = Choice.changed
    @State private var text = ""
    @State private var stillSeconds = 10
    @FocusState private var textFocused: Bool

    private var rule: RegionWatchRule? {
        switch choice {
        case .changed: return .changed
        case .still: return .stoppedChanging(seconds: TimeInterval(stillSeconds))
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .containsText(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill").foregroundStyle(Color.wispViolet)
                Text("Watch \(appName)").font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            Picker("Alert when it", selection: $choice) {
                ForEach(Choice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            detail.frame(height: 44, alignment: .topLeading)
            HStack {
                Text("Wisp looks every few seconds. Nothing is saved.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Start") { if let rule { start(rule) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rule == nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.1)))
        )
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .tint(.wispViolet)
        .onChange(of: choice) { _, next in textFocused = next == .text }
    }

    @ViewBuilder private var detail: some View {
        switch choice {
        case .changed:
            Text("Alerts once anything in the region looks different.")
                .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
        case .text:
            VStack(alignment: .leading, spacing: 4) {
                TextField("Text to look for", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($textFocused)
                Text("Alerts once this text shows").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            }
        case .still:
            Picker("Still for", selection: $stillSeconds) {
                ForEach(Self.stillChoices, id: \.self) { seconds in
                    Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) min").tag(seconds)
                }
            }
            .frame(maxWidth: 220)
        }
    }
}

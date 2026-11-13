import SwiftUI
import WispCore

/// An AI action under the notch: a spinner while the model works, then the answer with Copy
/// and Replace (or Paste, for clipboard text).
struct AIResultCardView: View {
    let card: AIResultCard
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.cardTopInset)
            header
                .padding(.leading, 18)
                // Room for the close button, so hovering doesn't move the buttons.
                .padding(.trailing, 44)
                .frame(height: SurfaceSizing.notificationCardHeight - 8)
            if let answer = card.answer {
                ScrollView {
                    Text(answer.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .frame(height: SurfaceSizing.aiResultHeight - 8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
        .overlay(alignment: .topTrailing) { CardCloseGlyph(model: model) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if card.answer == nil {
                    ProgressView().controlSize(.small).tint(Color.wispViolet)
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.wispViolet)
                }
            }
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.wispViolet.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(card.answer == nil ? card.task.progressTitle : card.task.title)
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(
                    AIResultButton.subtitle(
                        source: card.input.source, working: card.answer == nil,
                        truncated: card.answer?.truncated ?? false)
                )
                .font(.system(size: 12)).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 8)
            if card.answer != nil {
                let buttons = AIResultButton.buttons(task: card.task, source: card.input.source)
                ForEach(buttons, id: \.self) { button in
                    resultButton(button, primary: button == buttons.last)
                }
            }
        }
    }

    private func resultButton(_ button: AIResultButton, primary: Bool) -> some View {
        CapsuleButton(button.title, prominent: primary) { model.services.aiActions.perform(button, on: card) }
    }
}

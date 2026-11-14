import SwiftUI
import WispCore

/// What agents did while the user was away, under the notch once they're back. A click opens
/// the session history in the Agents widget. Shaped like the agent callout card.
struct AgentAwayCard: View {
    let summary: AwaySummary
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: summary.failed > 0 ? "exclamationmark.circle.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.wispViolet)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.wispViolet.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(AwaySummary.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(summary.detail).font(.system(size: 12)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 8)
                CapsuleButton("History", prominent: true) { openHistory() }
                    .fixedSize()
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            .contentShape(Rectangle())
            .onTapGesture { openHistory() }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
        .overlay(alignment: .topTrailing) { CardCloseGlyph(model: model) }
    }

    private func openHistory() {
        let services = model.services
        services.attention.requestHistory()
        services.activities.remove(.agentAway)
        services.openWidget(.agents)
    }
}

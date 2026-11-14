import SwiftUI
import WispCore

/// A decision about an agent session under the notch: Compact now when its context is nearly
/// full. Shaped like the finished download card.
struct AgentCalloutCard: View {
    let callout: AgentCallout
    let model: NotchModel

    private var hub: AgentHub { model.services.agents }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(tint.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 8)
                buttons
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.ink)
        .overlay(alignment: .topTrailing) { CardCloseGlyph(model: model) }
    }

    @ViewBuilder private var buttons: some View {
        switch callout.kind {
        case .compact(_, let canCompact):
            HStack(spacing: 8) {
                CapsuleButton("Terminal") {
                    hub.focus(session: callout.sessionID)
                    close()
                }
                if canCompact {
                    CapsuleButton("Compact now", prominent: true) {
                        hub.compact(session: callout.sessionID)
                        close()
                    }
                }
            }
            .fixedSize()
        }
    }

    private var symbol: String {
        switch callout.kind {
        case .compact: "gauge.with.dots.needle.100percent"
        }
    }

    private var tint: Color {
        switch callout.kind {
        case .compact: .red
        }
    }

    private var title: String {
        switch callout.kind {
        case .compact(let percent, _): "Context \(percent)% full"
        }
    }

    /// The project, unless details are hidden.
    private var detail: String {
        let place = hub.detailsHidden ? callout.source.displayName : callout.project
        switch callout.kind {
        case .compact(_, let canCompact):
            return canCompact ? "\(place) · compact to keep going" : "\(place) · start a new session soon"
        }
    }

    private func close() {
        model.services.activities.remove(.agentCallout)
    }
}

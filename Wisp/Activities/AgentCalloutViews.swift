import SwiftUI
import WispCore

/// A decision about an agent session under the notch: Compact now when its context is nearly
/// full, or what to do at the spend cap. Shaped like the finished download card.
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
        case .spendCap(let crossing, _):
            // The hub takes the card away once it has the choice.
            HStack(spacing: 8) {
                CapsuleButton("Stop") { hub.stopAtCap(session: callout.sessionID) }
                CapsuleButton(SpendCap.raiseTitle(crossing.raise)) {
                    hub.raiseCap(session: callout.sessionID, to: crossing.raise)
                }
                CapsuleButton("Keep going", prominent: true) { hub.keepGoing(session: callout.sessionID) }
            }
            .fixedSize()
        }
    }

    private var symbol: String {
        switch callout.kind {
        case .compact: "gauge.with.dots.needle.100percent"
        case .spendCap: "dollarsign.circle"
        }
    }

    private var tint: Color {
        switch callout.kind {
        case .compact: .red
        case .spendCap: .wispViolet
        }
    }

    private var title: String {
        switch callout.kind {
        case .compact(let percent, _): "Context \(percent)% full"
        case .spendCap(let crossing, let estimated): SpendCap.title(limit: crossing.limit, estimated: estimated)
        }
    }

    /// The project, unless details are hidden.
    private var detail: String {
        let place = hub.detailsHidden ? callout.source.displayName : callout.project
        switch callout.kind {
        case .compact(_, let canCompact):
            return canCompact ? "\(place) · compact to keep going" : "\(place) · start a new session soon"
        case .spendCap(_, let estimated):
            // Requests are what Wisp can hold; the agent keeps working until its next one.
            return estimated
                ? "\(place) · estimated · its next request waits" : "\(place) · its next request waits for you"
        }
    }

    /// Only while the slot still holds this card: a spend cap card that replaced it mid-transition
    /// must not go, since closing that one counts as Keep going.
    private func close() {
        let activities = model.services.activities
        guard case .agentCallout(let current) = activities.activity(in: .agentCallout), current.id == callout.id
        else { return }
        activities.remove(.agentCallout)
    }
}

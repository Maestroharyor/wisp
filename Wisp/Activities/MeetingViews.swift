import AppKit
import SwiftUI
import WispCore

/// "Starts in 2 min" under the notch, with a Join button that opens the call link.
struct MeetingSoonCard: View {
    let invite: MeetingInvite
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 8)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.wispViolet)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.wispViolet.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(invite.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(Self.startText(invite.start, now: context.date))
                            .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Button("Later") { model.services.activities.remove(.meetingSoon) }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.14)))
                Button("Join") {
                    NSWorkspace.shared.open(invite.link)
                    model.services.activities.remove(.meetingSoon)
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(Color.wispViolet))
            }
            .padding(.horizontal, 18)
            .frame(height: SurfaceSizing.notificationCardHeight - 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    private static func startText(_ start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes <= 0 ? "Starting now" : "Starts in \(minutes) min"
    }
}

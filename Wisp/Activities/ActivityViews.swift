import SwiftUI
import WispCore

/// One-line pill: a leading item left of the camera and a trailing item right of it.
struct CompactActivityView: View {
    let activity: Activity
    let model: NotchModel

    var body: some View {
        let surface = model.surfaceRect
        let gap = model.isNotchStyle ? model.layout.closedRect.width : 0
        let wing = max((surface.width - gap) / 2, 0)
        let padding =
            model.isNotchStyle
            ? ActivityMetrics.symmetricPadding(
                iconSize: ActivityMetrics.iconSize, notchHeight: model.notchHeight, notchStyle: true) - 6
            : ActivityMetrics.islandContentInset

        let minimal = model.preferences.appearance.minimalPill && !activity.keepsValueWhenMinimal
        HStack(spacing: 0) {
            Group {
                if minimal { ActivityGlyph(activity: activity, model: model) } else { leading }
            }
            .frame(width: max(wing - padding, 0), alignment: .leading)
            .padding(.leading, padding)
            if gap > 0 { Color.clear.frame(width: gap) } else { Spacer(minLength: 4) }
            Group {
                if minimal { MinimalDot(tint: model.accent) } else { trailing }
            }
            .frame(width: max(wing - padding, 0), alignment: .trailing)
            .padding(.trailing, padding)
        }
        .frame(height: surface.height)
        .font(.system(size: ActivityMetrics.labelFontSize, weight: .semibold))
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leading: some View {
        switch activity {
        case .level(let kind, let value, let muted):
            HStack(spacing: ActivityMetrics.contentSpacing) {
                Image(systemName: kind.symbol(value: value, muted: muted))
                    .frame(width: 16)
                Text(kind == .volume ? "Volume" : "Display").lineLimit(1)
            }
        case .charging:
            Label("Charging", systemImage: "bolt.fill").labelStyle(.titleOnly).lineLimit(1)
        case .unplugged(let percent), .lowBattery(let percent):
            Image(systemName: batterySymbol(percent)).foregroundStyle(percent <= 20 ? .red : .white)
        case .capsLock:
            Image(systemName: "capslock.fill")
        case .timer(_, let countdown):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressRing(progress: 1 - countdown.progress(now: context.date), tint: .wispAmber, lineWidth: 2.5)
                    .frame(width: 16, height: 16)
            }
        case .media:
            ArtworkView(image: model.services.nowPlaying.artwork, size: model.isNotchStyle ? 22 : 20, radius: 5)
        case .tray:
            Image(systemName: "tray.fill")
        case .notice(let symbol, _):
            Image(systemName: symbol)
        case .sent:
            Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(Color.accentColor)
        case .focus(let state):
            Image(systemName: state.symbol ?? "moon.fill").foregroundStyle(.indigo)
        case .agent(let status):
            HStack(spacing: ActivityMetrics.contentSpacing) {
                AgentGlyph(state: status.state, source: status.source, project: status.project)
                Text(status.project).lineLimit(1)
            }
        case .device(let device):
            HStack(spacing: ActivityMetrics.contentSpacing) {
                Image(systemName: device.symbol).frame(width: 18)
                Text(device.name).lineLimit(1)
            }
        case .meeting(let status):
            HStack(spacing: ActivityMetrics.contentSpacing) {
                Image(
                    systemName: model.services.microphone.muted
                        ? "mic.slash.fill" : status.kind == .recording ? "record.circle.fill" : "mic.fill"
                )
                .foregroundStyle(model.services.microphone.muted ? Color.secondaryText : .red)
                .frame(width: 16)
                Text(status.title).lineLimit(1)
            }
        case .batteryFull, .timerDone, .notification, .agentApproval, .meetingSoon:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch activity {
        case .level(let kind, let value, let muted):
            HStack(spacing: ActivityMetrics.contentSpacing) {
                LevelBar(
                    value: value,
                    tint: model.preferences.hudUsesAccent && !muted ? model.accent : kind.tint(muted: muted)
                )
                .frame(width: 46)
                ValueText(text: "\(LevelStep.percent(value))").frame(width: 24, alignment: .trailing)
            }
        case .charging(let percent):
            HStack(spacing: 4) {
                ValueText(text: "\(percent)%", tint: .wispGreen)
                Image(systemName: "battery.100percent.bolt").foregroundStyle(.wispGreen)
            }
        case .unplugged(let percent):
            ValueText(text: "\(percent)%")
        case .lowBattery(let percent):
            ValueText(text: "\(percent)%", tint: .red)
        case .capsLock(let on):
            ValueText(text: on ? "On" : "Off", tint: on ? .wispGreen : .white)
        case .timer(_, let countdown):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ValueText(text: Countdown.format(countdown.remaining(now: context.date)), tint: .wispAmber)
            }
        case .media:
            Waveform(tint: model.services.nowPlaying.tint, playing: model.services.nowPlaying.info?.isPlaying ?? false)
                .frame(width: 18, height: 14)
        case .tray(let count):
            ValueText(text: "\(count)", tint: .wispGreen)
        case .notice(_, let text):
            Text(text).lineLimit(1)
        case .sent(let text):
            Text("You: \(text)").lineLimit(1).foregroundStyle(Color.accentColor)
        case .focus(let state):
            Text(state.isOn ? (state.name ?? "On") : "Off").lineLimit(1)
                .foregroundStyle(state.isOn ? .white : Color.secondaryText)
        case .agent(let status):
            AgentStateLabel(status: status)
        case .meeting(let status):
            HStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ValueText(
                        text: Countdown.format(max(0, context.date.timeIntervalSince(status.started))), tint: .red)
                }
                Image(systemName: model.services.microphone.muted ? "mic.slash.circle.fill" : "mic.circle")
                    .foregroundStyle(.white.opacity(0.8))
                    .help(model.services.microphone.muted ? "Unmute the microphone" : "Mute the microphone")
            }
        case .device(let device):
            if let level = device.headline {
                HStack(spacing: 4) {
                    if let caseLevel = device.battery[.case] {
                        Image(systemName: "airpods.chargingcase.fill").foregroundStyle(Color.secondaryText)
                        ValueText(text: "\(caseLevel)%", tint: Color.secondaryText)
                    }
                    ValueText(text: "\(level)%", tint: level <= 20 ? .red : .wispGreen)
                }
            } else {
                Text("Connected").lineLimit(1).foregroundStyle(Color.secondaryText)
            }
        case .batteryFull, .timerDone, .notification, .agentApproval, .meetingSoon:
            EmptyView()
        }
    }

}

/// The battery outline closest to a charge level.
private func batterySymbol(_ percent: Int) -> String {
    switch percent {
    case ..<13: "battery.0percent"
    case ..<38: "battery.25percent"
    case ..<63: "battery.50percent"
    case ..<88: "battery.75percent"
    default: "battery.100percent"
    }
}

/// The upright pill on a left or right edge: one glyph above a short value, so the text
/// stays level instead of turning with the edge.
struct SideActivityView: View {
    let activity: Activity
    let model: NotchModel

    var body: some View {
        VStack(spacing: 7) {
            ActivityGlyph(activity: activity, model: model)
                .frame(height: 22)
            if model.preferences.appearance.minimalPill, !activity.keepsValueWhenMinimal {
                MinimalDot(tint: model.accent)
            } else {
                value
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
    }

    @ViewBuilder private var value: some View {
        switch activity {
        case .level(_, let value, _):
            ValueText(text: "\(LevelStep.percent(value))")
        case .charging(let percent):
            ValueText(text: "\(percent)%", tint: .wispGreen)
        case .unplugged(let percent):
            ValueText(text: "\(percent)%")
        case .lowBattery(let percent):
            ValueText(text: "\(percent)%", tint: .red)
        case .capsLock(let on):
            ValueText(text: on ? "On" : "Off", tint: on ? .wispGreen : .white)
        case .timer(_, let countdown):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ValueText(text: Countdown.format(countdown.remaining(now: context.date)), tint: .wispAmber)
            }
        case .media:
            Waveform(tint: model.services.nowPlaying.tint, playing: model.services.nowPlaying.info?.isPlaying ?? false)
                .frame(width: 18, height: 14)
        case .tray(let count):
            ValueText(text: "\(count)", tint: .wispGreen)
        case .focus(let state):
            ValueText(text: state.isOn ? "On" : "Off", tint: state.isOn ? .white : Color.secondaryText)
        case .agent(let status):
            AgentStateLabel(status: status).font(.system(size: 12, weight: .semibold))
        case .meeting(let status):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ValueText(text: Countdown.format(max(0, context.date.timeIntervalSince(status.started))), tint: .red)
            }
        case .device(let device):
            if let level = device.headline {
                ValueText(text: "\(level)%", tint: level <= 20 ? .red : .wispGreen)
            }
        case .notice(_, let text):
            caption(text)
        case .sent:
            caption("Sent").foregroundStyle(Color.accentColor)
        case .batteryFull, .timerDone, .notification, .agentApproval, .meetingSoon:
            EmptyView()
        }
    }

    /// A short notice in two small lines, since the pill is too narrow for a sentence.
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
    }
}

/// The one icon that stands for an activity: the side pill's top half and the minimal pill.
struct ActivityGlyph: View {
    let activity: Activity
    let model: NotchModel

    var body: some View {
        glyph
    }

    @ViewBuilder private var glyph: some View {
        switch activity {
        case .level(let kind, let value, let muted):
            Image(systemName: kind.symbol(value: value, muted: muted))
        case .charging:
            Image(systemName: "bolt.fill").foregroundStyle(.wispGreen)
        case .unplugged(let percent), .lowBattery(let percent):
            Image(systemName: batterySymbol(percent)).foregroundStyle(percent <= 20 ? .red : .white)
        case .capsLock:
            Image(systemName: "capslock.fill")
        case .timer(_, let countdown):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ProgressRing(progress: 1 - countdown.progress(now: context.date), tint: .wispAmber, lineWidth: 2.5)
                    .frame(width: 18, height: 18)
            }
        case .media:
            ArtworkView(image: model.services.nowPlaying.artwork, size: 22, radius: 5)
        case .tray:
            Image(systemName: "tray.fill")
        case .notice(let symbol, _):
            Image(systemName: symbol)
        case .sent:
            Image(systemName: "arrowshape.turn.up.left.fill").foregroundStyle(Color.accentColor)
        case .focus(let state):
            Image(systemName: state.symbol ?? "moon.fill").foregroundStyle(.indigo)
        case .agent(let status):
            AgentGlyph(state: status.state, source: status.source, project: status.project)
        case .device(let device):
            Image(systemName: device.symbol)
        case .meeting:
            Image(systemName: model.services.microphone.muted ? "mic.slash.fill" : "mic.fill")
                .foregroundStyle(model.services.microphone.muted ? Color.secondaryText : .red)
        case .batteryFull, .timerDone, .notification, .agentApproval, .meetingSoon:
            EmptyView()
        }
    }
}

extension Activity {
    /// Volume, brightness and countdowns are the point of their pills, so the minimal
    /// pill keeps their values.
    var keepsValueWhenMinimal: Bool {
        switch self {
        case .level, .timer: true
        default: false
        }
    }
}

/// The minimal pill's stand-in for a value: a small dot in the accent.
struct MinimalDot: View {
    let tint: Color

    var body: some View {
        Circle().fill(tint).frame(width: 7, height: 7).shadow(color: tint.opacity(0.7), radius: 3)
    }
}

/// Two-line card that grows below the notch.
struct MediumActivityView: View {
    let activity: Activity
    let model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.isNotchStyle ? model.notchHeight : 6)
            HStack(spacing: 12) {
                content
            }
            .padding(.horizontal, model.isNotchStyle ? 22 : 16)
            .frame(height: ActivityMetrics.cardContentHeight)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var content: some View {
        switch activity {
        case .batteryFull:
            Image(systemName: "battery.100percent").font(.system(size: 24)).foregroundStyle(.wispGreen)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Full Battery").font(.system(size: 14, weight: .bold))
                    ValueText(text: "100%", tint: .wispGreen, size: 14)
                }
                Text("Your Mac is fully charged.").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.wispGreen)
        case .timerDone(let label):
            Image(systemName: "timer").font(.system(size: 22)).foregroundStyle(.wispAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 14, weight: .bold))
                Text("Time is up.").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            }
            Spacer()
            ValueText(text: "0:00", tint: .wispAmber, size: 22)
        default:
            EmptyView()
        }
    }
}

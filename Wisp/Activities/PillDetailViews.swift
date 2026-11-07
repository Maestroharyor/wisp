import SwiftUI
import WispCore

// The views a click on a live pill opens when the activity has no widget of its own. Each
// reads its service directly, so it keeps up while open and says so once the activity ends.

/// The running region watch: whose window, the rule in words, how long, the last change.
/// Only times are kept from the watch; nothing captured from the window is shown.
struct RegionWatchDetail: View {
    let watch: RegionWatchController

    var body: some View {
        if let appName = watch.appName, let rule = watch.rule, let started = watch.started {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    DetailBadge(tint: watch.isPaused ? Color.secondaryText : Color.wispViolet) {
                        RegionWatchGlyph(paused: watch.isPaused)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appName).font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Text(rule.plainDescription)
                            .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    DetailButton(title: "Stop", help: "Stop watching") { watch.stop() }
                }
                // To the minute, so a slow refresh is enough.
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    HStack(alignment: .top, spacing: 20) {
                        // Low battery pauses the watch until the Mac is plugged in.
                        DetailFact(
                            title: watch.isPaused ? "Paused for low battery" : "Watching for",
                            value: watch.isPaused
                                ? "Until you plug in" : RegionWatchText.watching(since: started, now: context.date))
                        DetailFact(
                            title: "Last change", value: RegionWatchText.lastChange(watch.lastChange, now: context.date)
                        )
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            DetailEmpty(symbol: "eye.slash", text: "Not watching anything")
        }
    }
}

/// Every download in progress, newest first.
struct DownloadsDetail: View {
    let monitor: DownloadMonitor

    var body: some View {
        let downloads = monitor.downloads
        if downloads.isEmpty {
            DetailEmpty(symbol: "arrow.down.circle", text: "No downloads right now")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(downloads.count == 1 ? "1 download" : "\(downloads.count) downloads")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.secondaryText)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(downloads) { DownloadRow(progress: $0) }
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct DownloadRow: View {
    let progress: DownloadProgress

    var body: some View {
        HStack(spacing: 10) {
            DownloadGlyph(progress: progress, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(progress.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(DownloadText.amount(progress)).font(.system(size: 10)).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 8)
            ValueText(
                text: DownloadText.detail(progress), tint: progress.isStalled ? Color.secondaryText : .white)
        }
    }
}

/// An activity a script, Shortcut or link posted: its title, symbol, progress and sender.
struct ExternalActivityDetail: View {
    let automation: Automation

    var body: some View {
        if let activity = automation.current {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    DetailBadge(tint: Color.wispViolet) {
                        Image(systemName: activity.symbol).foregroundStyle(Color.wispViolet)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.title).font(.system(size: 13, weight: .bold)).lineLimit(2)
                        if let source = activity.source {
                            Text(source.label)
                                .font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let progress = activity.progress {
                    HStack(spacing: 10) {
                        ProgressView(value: progress).progressViewStyle(.linear).tint(Color.wispViolet)
                        ValueText(text: "\(LevelStep.percent(progress))%", tint: Color.wispViolet)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini).tint(Color.wispViolet)
                        Text("In progress").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    }
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            DetailEmpty(symbol: "checkmark.circle", text: "This activity has ended")
        }
    }
}

// MARK: Parts

/// The activity's glyph in a tinted circle, as on the download card.
private struct DetailBadge<Glyph: View>: View {
    let tint: Color
    @ViewBuilder let glyph: Glyph

    var body: some View {
        glyph
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 38, height: 38)
            .background(Circle().fill(tint.opacity(0.18)))
    }
}

private struct DetailFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.secondaryText)
            Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
    }
}

private struct DetailButton: View {
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain).font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 12).frame(height: 28)
            .background(Capsule().fill(.white.opacity(0.14)))
            .help(help)
    }
}

private struct DetailEmpty: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18))
            Text(text).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

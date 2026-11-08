import SwiftUI
import WispCore

/// A slider and mute button per app playing sound. Apps left at full volume play untouched.
struct AppVolumeMixer: View {
    let store: AppVolumeStore
    var compact = false

    var body: some View {
        Group {
            if !store.isSupported {
                note("Per-app volume needs macOS 14.2 or later.")
            } else if store.rows.isEmpty {
                note("Apps playing sound show here.")
            } else {
                ScrollView {
                    VStack(spacing: compact ? 4 : 8) {
                        ForEach(store.rows) { row in AppVolumeRowView(store: store, row: row, compact: compact) }
                        if store.canHear == false {
                            Text(
                                "Wisp can't hear these apps yet. If they stay at full volume, check System Audio Recording in System Settings."
                            )
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.listAppeared() }
        .onDisappear { store.listDisappeared() }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppVolumeRowView: View {
    let store: AppVolumeStore
    let row: AppVolumeRow
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let icon = store.icon(for: row.id) {
                Image(nsImage: icon).resizable().frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
            }
            Text(row.name).font(.system(size: compact ? 11 : 12, weight: .medium)).lineLimit(1)
                .frame(width: compact ? 70 : 96, alignment: .leading)
                .opacity(row.isPlaying ? 1 : 0.6)
            Slider(
                value: Binding(get: { row.level }, set: { store.setLevel($0, for: row.id) }), in: 0...1
            )
            .controlSize(.mini)
            .tint(Color.wispViolet)
            .disabled(row.muted)
            .accessibilityLabel("\(row.name) volume")
            ShelfButton(
                symbol: row.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 10,
                tint: row.muted ? .orange : .ink, label: row.muted ? "Unmute \(row.name)" : "Mute \(row.name)"
            ) { store.toggleMute(row.id) }
        }
        .contextMenu {
            Button("Reset to full volume") { store.reset(row.id) }
        }
    }
}

/// The rest of the playlist playing in Music. Music doesn't share its Up Next queue, so
/// this shows the playlist order, and only when it's what plays next.
struct UpNextList: View {
    let monitor: NowPlayingMonitor
    let store: UpNextStore
    var limit = 5

    var body: some View {
        Group {
            switch store.upNext {
            case .tracks(let playlist, let tracks):
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.isEmpty ? "Up next" : "Up next in \(playlist)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.secondaryText).lineLimit(1)
                    if tracks.isEmpty {
                        Text("End of the playlist").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    }
                    ForEach(Array(tracks.prefix(limit).enumerated()), id: \.offset) { _, track in
                        HStack(spacing: 6) {
                            Text(track.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            if !track.artist.isEmpty {
                                Text(track.artist).font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if let duration = track.duration {
                                Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.secondaryText)
                            }
                        }
                    }
                }
            case .hidden(.shuffled):
                hint("Shuffle is on, so Music doesn't say what's next")
            case .hidden(.repeatingOne):
                hint("Repeating this song")
            case .hidden(.unavailable), nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: monitor.info?.trackID) { await store.load(for: monitor.info) }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Color.secondaryText)
    }
}

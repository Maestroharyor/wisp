import SwiftUI
import WispCore

/// The line being sung now, with the next one dimmed below. Loads lyrics on appear.
struct LyricLines: View {
    let monitor: NowPlayingMonitor
    let lyrics: LyricsStore
    var size: CGFloat = 15
    var showsNext = true

    var body: some View {
        Group {
            if let found = lyrics.lyrics {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let index = found.index(at: monitor.position(at: context.date))
                    let current = index.map { found.lines[$0].text } ?? (found.isSynced ? "♪" : found.lines[0].text)
                    let nextIndex = (index ?? -1) + 1
                    let next = found.isSynced && nextIndex < found.lines.count ? found.lines[nextIndex].text : ""
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.isEmpty ? "♪" : current)
                            .font(.system(size: size, weight: .bold))
                            .lineLimit(2)
                            .contentTransition(.opacity)
                            .animation(.easeOut(duration: 0.25), value: current)
                        if showsNext, found.isSynced, !next.isEmpty {
                            Text(next).font(.system(size: size * 0.8, weight: .semibold))
                                .foregroundStyle(Color.secondaryText).lineLimit(1)
                        }
                    }
                }
            } else {
                Text(lyrics.loading ? "Finding lyrics…" : "No lyrics for this song")
                    .font(.system(size: size * 0.8)).foregroundStyle(Color.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: monitor.info?.trackID) { await lyrics.load(for: monitor.info) }
    }
}

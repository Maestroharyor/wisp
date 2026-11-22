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
                    let current =
                        index.map { found.lines[$0].text } ?? (found.isSynced ? "♪" : found.lines.first?.text ?? "")
                    let nextIndex = (index ?? -1) + 1
                    let next = found.isSynced && nextIndex < found.lines.count ? found.lines[nextIndex].text : ""
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current.isEmpty ? "♪" : current)
                            .font(.system(size: size, weight: .bold))
                            .lineLimit(2)
                            .contentTransition(.opacity)
                            .wispAnimation(.easeOut(duration: 0.25), value: current)
                            .accessibilityLabel(Self.spoken(current))
                            .accessibilityAddTraits(.updatesFrequently)
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

    /// The music note stands for a break between lines; VoiceOver says so in words.
    static func spoken(_ line: String) -> String {
        line.isEmpty || line == "♪" ? "Instrumental" : line
    }
}

/// The whole song, as Apple Music shows it: every line in a column, the one being sung large
/// and bright, the rest dimmer the further they are, and the column gliding up as the song
/// moves on. Scrolling by hand pauses the following for a moment; clicking a timed line seeks.
struct LyricsScroller: View {
    let monitor: NowPlayingMonitor
    let lyrics: Lyrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// When the user last scrolled by hand; following resumes a few seconds later.
    @State private var heldUntil: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let position = monitor.position(at: context.date)
            let current = lyrics.index(at: position)
            let following = heldUntil.map { context.date >= $0 } ?? true
            ScrollViewReader { reader in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        // Room above, so the first line can sit in the middle like the rest.
                        Color.clear.frame(height: 120)
                        if lyrics.isSynced, current == nil, LyricsDisplay.inGap(lyrics, at: position) {
                            BreakDots().id(-1)
                        }
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            row(index, line: line, current: current, position: position)
                                .id(index)
                            if index == current, LyricsDisplay.inGap(lyrics, at: position) {
                                BreakDots()
                            }
                        }
                        Color.clear.frame(height: 200)
                    }
                    .padding(.horizontal, 4)
                }
                .scrollFade()
                .modifier(HoldOnScroll { heldUntil = .now.addingTimeInterval(4) })
                .onChange(of: current) { _, line in
                    guard following, let line else { return }
                    withAnimation(reduceMotion ? nil : .wispSmooth) { reader.scrollTo(line, anchor: .center) }
                }
                .onAppear {
                    if let current { reader.scrollTo(current, anchor: .center) }
                }
                .overlay(alignment: .bottom) {
                    if !following, let current {
                        Button("Back to now", systemImage: "arrow.down.to.line") {
                            heldUntil = nil
                            withAnimation(reduceMotion ? nil : .wispSmooth) {
                                reader.scrollTo(current, anchor: .center)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.wispViolet)
                        .controlSize(.small)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    private func row(_ index: Int, line: Lyrics.Line, current: Int?, position: TimeInterval) -> some View {
        let isCurrent = index == current
        let distance = current.map { abs(index - $0) } ?? 0
        let text = line.text.isEmpty ? "♪" : line.text
        return Button {
            if let time = line.time { monitor.seek(to: time) }
        } label: {
            Text(text)
                .font(.title.bold())
                .foregroundStyle(.primary)
                .opacity(lyrics.isSynced ? LyricsDisplay.emphasis(line: index, current: current) : 0.9)
                .scaleEffect(isCurrent || !lyrics.isSynced ? 1 : 0.94, anchor: .leading)
                .blur(radius: !reduceMotion && !reduceTransparency && distance > 2 ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .wispSmooth, value: isCurrent)
        }
        .buttonStyle(.plain)
        .disabled(line.time == nil)
        .help(line.time == nil ? "" : "Play from here")
        .accessibilityLabel(LyricLines.spoken(line.text))
        .accessibilityAddTraits(isCurrent ? [.isSelected, .updatesFrequently] : [])
        .accessibilityHint(line.time == nil ? "" : "Plays from this line")
    }
}

/// Three dots that breathe while the music plays between lines.
private struct BreakDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.primary)
                        .frame(width: 10, height: 10)
                        .opacity(reduceMotion ? 0.6 : 0.35 + 0.5 * (0.5 + 0.5 * sin(phase * 3 - Double(index) * 0.7)))
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityLabel("Instrumental")
    }
}

/// The lyrics card's content: the song's lyrics, a YouTube video's own captions, live captions
/// made from the playing sound, or why there's nothing, in that order (`CaptionSource`).
struct LyricsPanel: View {
    let services: AppServices

    private var monitor: NowPlayingMonitor { services.nowPlaying }
    private var preferences: Preferences { services.preferences }

    private var source: CaptionSource {
        CaptionSource.choose(
            hasLyrics: preferences.lyrics && services.lyrics.lyrics != nil,
            youTube: services.youTubeCaptions.state,
            live: LiveCaptions.status(enabled: preferences.liveCaptions))
    }

    var body: some View {
        let source = source
        Group {
            switch source {
            case .lyrics:
                if let found = services.lyrics.lyrics { LyricsScroller(monitor: monitor, lyrics: found) }
            case .youTube:
                if let captions = services.youTubeCaptions.captions {
                    VStack(alignment: .leading, spacing: 6) {
                        SourceLabel(text: "Captions from YouTube", symbol: "captions.bubble")
                        LyricsScroller(monitor: monitor, lyrics: captions)
                    }
                }
            case .live:
                LiveCaptionLines(captions: services.liveCaptions)
            case .waiting:
                LoadingLabel(services.lyrics.loading ? "Finding lyrics…" : "Finding captions…")
            case .needsPermission:
                WindowEmptyState(
                    symbol: "captions.bubble", title: "Live captions need two permissions",
                    message: "Allow Speech Recognition and System Audio Recording, then captions follow what's playing."
                ) {
                    WindowPrimaryButton(title: "Open Settings", symbol: "gearshape") {
                        services.showSettings(pane: .activities)
                    }
                }
            case .nothing:
                WindowEmptyState(
                    symbol: "quote.bubble",
                    title: services.lyrics.loading ? "Finding lyrics…" : "No lyrics for this one",
                    message: services.lyrics.loading
                        ? "Looking it up on LRCLIB."
                        : "Turn on YouTube captions or live captions in Settings › Live Activities to read along with videos too."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .task(id: "\(monitor.info?.trackID ?? "")|\(preferences.youTubeCaptions)") {
            await services.lyrics.load(for: monitor.info)
            let wantsCaptions = !(preferences.lyrics && services.lyrics.lyrics != nil)
            await services.youTubeCaptions.load(
                for: monitor.info, enabled: preferences.youTubeCaptions && wantsCaptions)
        }
        // Listens only while live captions are what's shown and the app is playing.
        .task(id: "\(source == .live)|\(monitor.info?.isPlaying ?? false)|\(monitor.info?.appBundleID ?? "")") {
            if source == .live, monitor.info?.isPlaying == true, let app = monitor.info?.appBundleID {
                services.liveCaptions.start(app: app)
            } else {
                services.liveCaptions.stop()
            }
        }
        .onDisappear { services.liveCaptions.stop() }
    }
}

/// Where the words come from, above them.
private struct SourceLabel: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.secondaryText)
    }
}

/// Live captions as they're heard: the last three lines, the newest brightest.
private struct LiveCaptionLines: View {
    let captions: LiveCaptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SourceLabel(text: "Live captions, made on this Mac", symbol: "waveform")
            Spacer(minLength: 0)
            if captions.lines.isEmpty {
                Text(captions.listening ? "Listening…" : "Waiting for sound…")
                    .font(.title2.bold())
                    .foregroundStyle(Color.secondaryText)
            } else {
                ForEach(Array(captions.lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.title.bold())
                        .opacity(index == captions.lines.count - 1 ? 1 : 0.5)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : .wispSmooth, value: captions.lines)
        .accessibilityElement(children: .combine)
    }
}

/// On macOS 15 and later, scrolling by hand calls `hold`, so the column stays where the user put
/// it for a moment. Earlier versions keep following the song.
private struct HoldOnScroll: ViewModifier {
    let hold: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { hold() }
            }
        } else {
            content
        }
    }
}

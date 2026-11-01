import AVFoundation
import AVKit
import AppKit
import EventKit
import SwiftUI
import WispCore

/// Routes a widget kind to its view, inside the shared card.
struct WidgetCard: View {
    let kind: WidgetKind
    let model: NotchModel

    var body: some View {
        let services = model.services
        Group {
            switch kind {
            case .nowPlaying: NowPlayingWidget(monitor: services.nowPlaying)
            case .calendar: CalendarWidget(store: services.calendar)
            case .timer: TimerWidget(store: services.timers)
            case .pomodoro: PomodoroWidget(store: services.timers, preferences: services.preferences)
            case .battery: BatteryWidget(monitor: services.battery)
            case .systemStats: SystemStatsWidget(store: services.stats)
            case .weather: WeatherWidget(store: services.weather)
            case .notes: NotesWidget(store: services.notes)
            case .quickToggles: QuickTogglesWidget(actions: services.quickActions)
            case .shortcuts: ShortcutsWidget(runner: services.shortcuts, preferences: services.preferences)
            case .clipboard: ClipboardWidget(store: services.clipboard)
            case .mirror: MirrorWidget(camera: services.camera)
            case .dayProgress: DayProgressWidget(calendar: services.calendar, preferences: services.preferences)
            case .worldClocks: WorldClocksWidget(preferences: services.preferences)
            case .agents: AgentsWidget(hub: services.agents)
            case .script: ScriptWidget(store: services.script, preferences: services.preferences)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(model.editingHome)
    }
}

// MARK: Now Playing

struct NowPlayingWidget: View {
    let monitor: NowPlayingMonitor

    var body: some View {
        if let info = monitor.info {
            VStack(spacing: 0) {
                // Artwork, title and artist; waveform at the top right.
                HStack(alignment: .center, spacing: 12) {
                    ArtworkView(image: monitor.artwork, size: 50, radius: 11)
                        .onTapGesture { monitor.openPlayer() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(info.artist.isEmpty ? (info.appName ?? "") : info.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Waveform(tint: .white.opacity(0.55), playing: info.isPlaying, barCount: 6, barWidth: 2)
                        .frame(width: 22, height: 16)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 4)
                }
                .frame(height: 52)

                Spacer(minLength: 8)

                // Elapsed, progress, remaining.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let position = monitor.position(at: context.date)
                    HStack(spacing: 10) {
                        ValueText(text: Countdown.format(position), tint: .secondaryText, size: 11)
                        ProgressBar(
                            value: info.duration > 0 ? position / info.duration : 0, tint: .accentColor, height: 5
                        ) {
                            monitor.seek(to: $0 * info.duration)
                        }
                        ValueText(
                            text: "-" + Countdown.format(max(info.duration - position, 0)), tint: .secondaryText,
                            size: 11)
                    }
                }

                Spacer(minLength: 8)

                // Player, transport and output device spread across the width.
                HStack(spacing: 0) {
                    PlainIconButton(symbol: "list.bullet", size: 15, tint: .secondaryText, label: "Open player") {
                        monitor.openPlayer()
                    }
                    Spacer()
                    PlainIconButton(symbol: "backward.fill", size: 20) { monitor.previous() }
                    Spacer()
                    PlainIconButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: 28) {
                        monitor.togglePlayPause()
                    }
                    Spacer()
                    PlainIconButton(symbol: "forward.fill", size: 20) { monitor.next() }
                    Spacer()
                    OutputDevicePicker()
                        .frame(width: 26, height: 26)
                        .help("Output device")
                }
            }
        } else {
            HStack(spacing: 12) {
                ArtworkView(image: nil, size: 50, radius: 11)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing playing").font(.system(size: 15, weight: .semibold))
                    Text("Play something in any app or browser")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

/// A bare SF Symbol button that dims while pressed.
struct PlainIconButton: View {
    let symbol: String
    var size: CGFloat = 16
    var tint: Color = .white
    /// What VoiceOver says; defaults to a name for the symbol.
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(minWidth: size + 8, minHeight: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressDimStyle())
        .accessibilityLabel(label ?? SymbolLabel.label(for: symbol))
    }
}

private struct PressDimStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// System audio output picker (AirPlay, headphones, speakers).
struct OutputDevicePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
        picker.setRoutePickerButtonColor(.white, for: .active)
        return picker
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

/// Thin progress bar that seeks on click.
struct ProgressBar: View {
    let value: Double
    let tint: Color
    var height: CGFloat = 4
    let seek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(tint).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
            .contentShape(Rectangle())
            .onTapGesture { location in seek(min(max(location.x / proxy.size.width, 0), 1)) }
        }
        .frame(height: height)
    }
}

// MARK: Calendar

struct CalendarWidget: View {
    let store: CalendarStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 4) {
                    Text(context.date, format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(.red).textCase(.uppercase)
                    Text(context.date, format: .dateTime.day())
                    Text("W\(Calendar.current.component(.weekOfYear, from: context.date))")
                        .foregroundStyle(.red.opacity(0.75))
                }
                .font(.system(size: 12, weight: .bold))
            }
            if store.access == .fullAccess {
                if store.events.isEmpty {
                    Text("Nothing in the next week")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                            ForEach(CalendarDays.group(store.events, date: \.start, now: .now), id: \.label) { day in
                                Section {
                                    ForEach(day.items) { event in
                                        EventRow(event: event).onTapGesture { store.open(event) }
                                    }
                                } header: {
                                    if day.label != "Today" {
                                        Text(day.label.uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.secondaryText)
                                            .padding(.top, 4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 14)
                    }
                    // Fades the last row so it reads as "scroll for more".
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .white, location: 0.82), .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom))
                }
            } else {
                VStack(spacing: 6) {
                    Text("See today's events here").font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                    Button("Allow Calendar Access") { store.requestAccess() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { store.refresh() }
    }
}

private struct EventRow: View {
    let event: CalendarStore.Event

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 1.5).fill(event.color).frame(width: 3)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(timeText).font(.system(size: 11)).opacity(0.8).lineLimit(1)
            }
            .foregroundStyle(event.color)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .padding(.leading, 3)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(event.color.opacity(0.16)))
    }

    private var timeText: String {
        guard !event.isAllDay else { return "All day" }
        let format = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(event.start.formatted(format)) – \(event.end.formatted(format))"
    }
}

// MARK: Timer

struct TimerWidget: View {
    let store: TimerStore

    var body: some View {
        let timer = store.timer
        HStack(spacing: 10) {
            if timer.hasStarted {
                CircleButton(symbol: timer.isRunning ? "pause.fill" : "play.fill", tint: .wispAmber, filled: true) {
                    store.toggleTimer()
                }
                CircleButton(symbol: "xmark", tint: .white) { store.resetTimer() }
            } else {
                CircleButton(symbol: "play.fill", tint: .wispAmber, filled: true) { store.toggleTimer() }
                VStack(spacing: 2) {
                    PlainIconButton(symbol: "chevron.up", size: 10, tint: .secondaryText, label: "One more minute") {
                        store.adjustTimer(byMinutes: 1)
                    }
                    PlainIconButton(symbol: "chevron.down", size: 10, tint: .secondaryText, label: "One less minute") {
                        store.adjustTimer(byMinutes: -1)
                    }
                }
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ValueText(text: Countdown.format(timer.remaining(now: context.date)), tint: .wispAmber, size: 26)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Round control: tinted fill, bold glyph.
struct CircleButton: View {
    let symbol: String
    let tint: Color
    var filled = false
    var size: CGFloat = 34
    /// What VoiceOver says; defaults to a name for the symbol.
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(filled ? tint : .white.opacity(0.85))
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? tint.opacity(0.28) : .white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? SymbolLabel.label(for: symbol))
    }
}

// MARK: Pomodoro

struct PomodoroWidget: View {
    let store: TimerStore
    let preferences: Preferences

    var body: some View {
        let countdown = store.pomodoro
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                phasePill(.focus)
                phasePill(.rest)
            }
            RulerScrubber(
                value: Binding(
                    get: { store.phase == .focus ? store.focusMinutes : store.breakMinutes },
                    set: { store.phase == .focus ? (store.focusMinutes = $0) : (store.breakMinutes = $0) }
                ),
                range: store.phase == .focus ? 15...60 : 3...20,
                enabled: !countdown.hasStarted,
                feedback: preferences.scrubberSounds
            )
            HStack(spacing: 6) {
                CircleButton(
                    symbol: countdown.isRunning ? "pause.fill" : "play.fill", tint: .wispAmber, filled: true, size: 28
                ) {
                    store.togglePomodoro()
                }
                CircleButton(symbol: "arrow.counterclockwise", tint: .white, size: 28) { store.resetPomodoro() }
                CircleButton(
                    symbol: preferences.scrubberSounds ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    tint: .wispAmber, filled: preferences.scrubberSounds, size: 28
                ) {
                    preferences.scrubberSounds.toggle()
                }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ValueText(
                        text: Countdown.format(countdown.remaining(now: context.date)), tint: .wispAmber, size: 22)
                }
            }
        }
    }

    private func phasePill(_ phase: PomodoroPhase) -> some View {
        Button {
            store.setPhase(phase)
        } label: {
            Text(phase.title)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(store.phase == phase ? Color.wispAmber.opacity(0.28) : .white.opacity(0.1)))
                .foregroundStyle(store.phase == phase ? Color.wispAmber : Color.secondaryText)
        }
        .buttonStyle(.plain)
    }
}

/// Labelled ruler: drag to pick whole minutes; the caret marks the value.
struct RulerScrubber: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var enabled = true
    /// Plays a tick and a trackpad tap for each minute passed while dragging.
    var feedback = true

    @State private var dragStart: Int?
    private let spacing: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.width / 2
            Canvas { context, size in
                for minute in range {
                    let x = mid + CGFloat(minute - value) * spacing
                    guard x >= 0, x <= size.width else { continue }
                    let major = minute % 5 == 0
                    let tick = CGRect(x: x - 0.5, y: 14, width: 1, height: major ? 10 : 6)
                    context.fill(Path(tick), with: .color(.wispAmber.opacity(major ? 0.9 : 0.45)))
                    if major {
                        let label = Text("\(minute)")
                            .font(.system(size: 9, weight: minute == value ? .bold : .medium))
                            .foregroundStyle(minute == value ? Color.white : Color.wispAmber.opacity(0.8))
                        context.draw(label, at: CGPoint(x: x, y: 6))
                    }
                }
                var caret = Path()
                caret.move(to: CGPoint(x: mid - 4, y: size.height))
                caret.addLine(to: CGPoint(x: mid + 4, y: size.height))
                caret.addLine(to: CGPoint(x: mid, y: size.height - 5))
                caret.closeSubpath()
                context.fill(caret, with: .color(.wispAmber))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { drag in
                        guard enabled else { return }
                        let start = dragStart ?? value
                        dragStart = start
                        let next = min(
                            max(start - Int((drag.translation.width / spacing).rounded()), range.lowerBound),
                            range.upperBound)
                        guard next != value else { return }
                        value = next
                        if feedback { TickFeedback.tick(major: next % 5 == 0) }
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(height: 30)
        .opacity(enabled ? 1 : 0.5)
        .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing))
    }
}

// MARK: Battery

struct BatteryWidget: View {
    let monitor: BatteryMonitor

    var body: some View {
        HStack(spacing: 14) {
            if let state = monitor.state {
                let fraction = Double(state.percent) / 100
                let tint: Color = state.percent <= 20 && !state.isPluggedIn ? .red : .wispGreen
                ZStack {
                    ProgressRing(progress: fraction, tint: tint, lineWidth: 5)
                    ValueText(text: "\(state.percent)", size: 15)
                }
                .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        state.isCharging ? "Charging" : state.isPluggedIn ? "On power" : "On battery",
                        systemImage: state.isPluggedIn ? "bolt.fill" : "battery.75percent"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    if let minutes = monitor.minutesRemaining {
                        Text("\(minutes / 60)h \(minutes % 60)m \(state.isPluggedIn ? "to full" : "left")")
                            .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    }
                }
            } else {
                Text("No battery").font(.system(size: 13)).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: System stats

struct SystemStatsWidget: View {
    let store: SystemStatsStore

    private static let cpuTint = Color(red: 0.55, green: 0.5, blue: 1)
    private static let ramTint = Color(red: 0.45, green: 0.85, blue: 0.7)

    var body: some View {
        HStack(spacing: 12) {
            gauge(
                "CPU", symbol: "cpu", value: store.cpu, history: store.cpuHistory.values, tint: Self.cpuTint,
                filled: false
            )
            gauge(
                "RAM", symbol: "memorychip", value: store.memory.fraction, history: store.memoryHistory.values,
                tint: Self.ramTint, filled: true)
        }
        .onAppear { store.attach() }
        .onDisappear { store.detach() }
    }

    private func gauge(_ title: String, symbol: String, value: Double, history: [Double], tint: Color, filled: Bool)
        -> some View
    {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    ProgressRing(progress: value, tint: tint, lineWidth: 4)
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        ValueText(text: "\(LevelStep.percent(value))", size: 18)
                        Text("%").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.secondaryText)
                    }
                }
            }
            Sparkline(values: history, tint: tint, filled: filled)
                .frame(maxHeight: .infinity)
        }
    }
}

/// Small line or area chart of recent samples (0...1), newest on the right.
struct Sparkline: View {
    let values: [Double]
    let tint: Color
    var filled = false

    var body: some View {
        GeometryReader { proxy in
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: values.count > 1 ? proxy.size.width * CGFloat(index) / CGFloat(values.count - 1) : 0,
                    y: proxy.size.height * (1 - CGFloat(min(max(value, 0), 1)))
                )
            }
            ZStack {
                if filled, let first = points.first, let last = points.last {
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.45), tint.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                }
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: Weather

struct WeatherWidget: View {
    let store: WeatherStore

    var body: some View {
        Group {
            if let reading = store.reading {
                let now = WeatherCode.describe(reading.code, isDay: reading.isDay)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Label(reading.place.isEmpty ? "Here" : reading.place, systemImage: "location.fill")
                            .labelStyle(TrailingIconLabel())
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 13))
                    }
                    HStack(alignment: .top) {
                        Text("\(Int(reading.temperature.rounded()))°")
                            .font(.system(size: 30, weight: .regular, design: .rounded))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(now.title).font(.system(size: 10, weight: .semibold))
                            Text("H:\(Int(reading.high.rounded()))° L:\(Int(reading.low.rounded()))°")
                                .font(.system(size: 10))
                        }
                    }
                    if !reading.hours.isEmpty {
                        HStack {
                            ForEach(reading.hours) { hour in
                                VStack(spacing: 1) {
                                    Text("\(hour.hour)").font(.system(size: 8)).opacity(0.8)
                                    Image(systemName: WeatherCode.describe(hour.code, isDay: hour.isDay).symbol)
                                        .symbolRenderingMode(.multicolor).font(.system(size: 10))
                                    Text("\(Int(hour.temperature.rounded()))°").font(
                                        .system(size: 8, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(10)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 24))
                    Text(store.status).font(.system(size: 11)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: ShellMetrics.widgetCornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.47, blue: 0.82), Color(red: 0.5, green: 0.6, blue: 0.9)],
                        startPoint: .top, endPoint: .bottom))
        )
        .onAppear { store.refreshIfStale() }
    }
}

private struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.font(.system(size: 8))
        }
    }
}

// MARK: Notes

struct NotesWidget: View {
    @Bindable var store: NotesStore

    var body: some View {
        TextEditor(text: $store.text)
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .overlay(alignment: .topLeading) {
                if store.text.isEmpty {
                    Text("Jot something down…")
                        .font(.system(size: 12)).foregroundStyle(Color.secondaryText)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Click and haptic feedback for scrubbing: a watch-crown ratchet tick per step
/// (synthesised by `ClickSynth`), deeper and louder on every fifth.
@MainActor
enum TickFeedback {
    private static let player = ClickPlayer()

    static func tick(major isMajor: Bool) {
        player?.play(major: isMajor)
        NSHapticFeedbackManager.defaultPerformer.perform(isMajor ? .levelChange : .alignment, performanceTime: .now)
    }
}

/// Plays the two pre-rendered clicks with low latency. A new tick interrupts the
/// previous one, so fast scrubbing stays crisp instead of smearing.
@MainActor
private final class ClickPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let minor: AVAudioPCMBuffer
    private let major: AVAudioPCMBuffer
    /// Stops the engine once scrubbing pauses; a running engine keeps the output device awake.
    private var idleStop: Task<Void, Never>?

    init?() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
            let minor = Self.buffer(ClickSynth.samples(sampleRate: 48_000, major: false), format: format),
            let major = Self.buffer(ClickSynth.samples(sampleRate: 48_000, major: true), format: format)
        else { return nil }
        self.minor = minor
        self.major = major
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func play(major isMajor: Bool) {
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        node.scheduleBuffer(isMajor ? major : minor, at: nil, options: .interrupts)
        if !node.isPlaying { node.play() }
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.node.stop()
            self.engine.stop()
        }
    }

    private static func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        return buffer
    }
}

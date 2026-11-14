import AppKit
import Observation
import WispCore

enum PomodoroPhase: String, Codable {
    case focus
    case rest

    var title: String { self == .focus ? "Focus" : "Break" }
}

/// The countdown timer and the Pomodoro timer. Running timers show as a live
/// activity beside the notch; finishing posts a card and plays a sound.
@MainActor
@Observable
final class TimerStore {
    /// The plain timer's pill and card label; anything else on them is the Pomodoro.
    static let timerLabel = "Timer"

    private(set) var timer: Countdown
    private(set) var pomodoro: Countdown
    private(set) var phase: PomodoroPhase = .focus
    /// Today's finished focus sessions (times only), kept across relaunches.
    private(set) var log: PomodoroLog {
        didSet { if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: Self.logKey) } }
    }
    var focusMinutes: Int {
        didSet { if !pomodoro.hasStarted, phase == .focus { pomodoro = Countdown(duration: minutes(focusMinutes)) } }
    }
    var breakMinutes: Int {
        didSet { if !pomodoro.hasStarted, phase == .rest { pomodoro = Countdown(duration: minutes(breakMinutes)) } }
    }

    @ObservationIgnored var onActivity: (Activity?) -> Void = { _ in }
    /// A timer ran out: its label, and whether it ended a Pomodoro focus session.
    @ObservationIgnored var onFinished: (String, Bool) -> Void = { _, _ in }
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    static let logKey = "pomodoroLog"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timer = Countdown(duration: 5 * 60)
        focusMinutes = 25
        breakMinutes = 5
        pomodoro = Countdown(duration: 25 * 60)
        log =
            defaults.data(forKey: Self.logKey).flatMap { try? JSONDecoder().decode(PomodoroLog.self, from: $0) }
            ?? PomodoroLog()
    }

    // MARK: Timer

    func adjustTimer(byMinutes delta: Int) {
        guard !timer.hasStarted else { return }
        timer = Countdown(duration: min(max(timer.duration + minutes(delta), 60), minutes(180)))
    }

    /// The length a fresh timer starts at; leaves a timer that is already going alone.
    func applyDefaultLength(seconds: TimeInterval) {
        guard !timer.hasStarted, seconds >= 60 else { return }
        timer = Countdown(duration: min(seconds, minutes(180)))
    }

    func setTimer(minutes value: Int) {
        timer = Countdown(duration: minutes(value))
    }

    /// A fresh timer of this length, running now; replaces one already going.
    func startTimer(minutes value: Int) {
        timer = Countdown(duration: minutes(value))
        timer.start(now: .now)
        update()
    }

    func toggleTimer() {
        if timer.isRunning { timer.pause(now: .now) } else { timer.start(now: .now) }
        update()
    }

    func resetTimer() {
        timer.reset()
        update()
    }

    // MARK: Pomodoro

    func setPhase(_ next: PomodoroPhase) {
        phase = next
        pomodoro = Countdown(duration: minutes(next == .focus ? focusMinutes : breakMinutes))
        update()
    }

    func togglePomodoro() {
        if pomodoro.isRunning { pomodoro.pause(now: .now) } else { pomodoro.start(now: .now) }
        update()
    }

    func resetPomodoro() {
        pomodoro.reset()
        update()
    }

    /// Moves on to the other phase without counting this one as done.
    func skipPhase() {
        setPhase(phase == .focus ? .rest : .focus)
    }

    /// Sets both lengths, for the window's preset chips; ignored while a session is going.
    func applyPreset(focus: Int, rest: Int) {
        guard !pomodoro.hasStarted else { return }
        focusMinutes = focus
        breakMinutes = rest
    }

    /// A fresh focus session of `focus` minutes, running now, with `rest` minutes of break to
    /// follow; replaces a Pomodoro already going. For the Focus chips in the Agents view.
    func startFocus(minutes focus: Int, rest: Int) {
        pomodoro.reset()
        focusMinutes = focus
        breakMinutes = rest
        phase = .focus
        pomodoro = Countdown(duration: minutes(focus))
        pomodoro.start(now: .now)
        update()
    }

    // MARK: Ticking

    private func update() {
        let now = Date.now
        let running = [(Self.timerLabel, timer), (phase.title, pomodoro)]
            .filter { $0.1.isRunning }
            .min { $0.1.remaining(now: now) < $1.1.remaining(now: now) }
        onActivity(running.map { Activity.timer(label: $0.0, countdown: $0.1) })

        tickTask?.cancel()
        guard running != nil else { return }
        tickTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    private func tick() {
        let now = Date.now
        if timer.isRunning, timer.isFinished(now: now) {
            timer.reset()
            onFinished(Self.timerLabel, false)
        }
        if pomodoro.isRunning, pomodoro.isFinished(now: now) {
            let finished = phase
            if finished == .focus {
                // When it ran out, not when this tick noticed (the Mac may have slept).
                let end = now.addingTimeInterval(pomodoro.duration - pomodoro.elapsed(now: now))
                log.record(start: end.addingTimeInterval(-pomodoro.duration), end: end)
            }
            setPhase(finished == .focus ? .rest : .focus)
            onFinished(finished == .focus ? "Focus done" : "Break over", finished == .focus)
        }
        update()
    }

    private func minutes(_ value: Int) -> TimeInterval { TimeInterval(value * 60) }
}

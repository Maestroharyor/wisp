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
    private(set) var timer: Countdown
    private(set) var pomodoro: Countdown
    private(set) var phase: PomodoroPhase = .focus
    var focusMinutes: Int {
        didSet { if !pomodoro.hasStarted, phase == .focus { pomodoro = Countdown(duration: minutes(focusMinutes)) } }
    }
    var breakMinutes: Int {
        didSet { if !pomodoro.hasStarted, phase == .rest { pomodoro = Countdown(duration: minutes(breakMinutes)) } }
    }

    @ObservationIgnored var onActivity: (Activity?) -> Void = { _ in }
    @ObservationIgnored var onFinished: (String) -> Void = { _ in }
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init() {
        timer = Countdown(duration: 5 * 60)
        focusMinutes = 25
        breakMinutes = 5
        pomodoro = Countdown(duration: 25 * 60)
    }

    // MARK: Timer

    func adjustTimer(byMinutes delta: Int) {
        guard !timer.hasStarted else { return }
        timer = Countdown(duration: min(max(timer.duration + minutes(delta), 60), minutes(180)))
    }

    func setTimer(minutes value: Int) {
        timer = Countdown(duration: minutes(value))
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

    // MARK: Ticking

    private func update() {
        let now = Date.now
        let running = [("Timer", timer), (phase.title, pomodoro)]
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
            finish("Timer")
        }
        if pomodoro.isRunning, pomodoro.isFinished(now: now) {
            let finished = phase
            setPhase(finished == .focus ? .rest : .focus)
            finish(finished == .focus ? "Focus done" : "Break over")
        }
        update()
    }

    private func finish(_ label: String) {
        NSSound(named: "Glass")?.play()
        onFinished(label)
    }

    private func minutes(_ value: Int) -> TimeInterval { TimeInterval(value * 60) }
}

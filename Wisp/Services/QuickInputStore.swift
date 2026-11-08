import EventKit
import Foundation
import OSLog
import Observation
import WispCore

/// Quick add: a short request typed or dictated into the shelf ("25 min", "remind me to call Sam
/// at 5", "tomorrow 9am meeting") becomes a timer, a Reminders item or a calendar event. The Core
/// parser reads the common forms; anything else goes to the AI quick-input task when AI is on.
/// Nothing is made until the user confirms the card. Requests and titles are never logged.
@MainActor
@Observable
final class QuickInputStore {
    enum State: Equatable {
        case idle
        case thinking
        /// A short line under the field: why nothing was understood, or what was made.
        case message(String)
    }

    /// The field's text. Kept here so dictation can add to it and closing the shelf keeps it.
    var text = ""
    private(set) var state: State = .idle
    /// The request read and waiting for Add or Cancel, in the widget and on the notch card.
    private(set) var pending: QuickIntent?
    /// The request `pending` was read from, so the field is cleared only if it still holds it.
    @ObservationIgnored private var pendingInput = ""
    /// Set to put the cursor in the field (the ring action); the field clears it.
    private(set) var wantsFocus = false
    /// Fields on screen with the cursor in them, so held dictation types there.
    private(set) var focusedFields = 0

    @ObservationIgnored private let ai: AIService
    @ObservationIgnored private let timers: TimerStore
    @ObservationIgnored private let activities: ActivityCenter
    /// One store for saving, so an access prompt and the save that follows use the same one.
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "quick-input")

    /// How long the notch card waits for an answer.
    private static let cardSeconds: TimeInterval = 30
    private static let hint =
        "Try \u{201C}25 min\u{201D}, \u{201C}pomodoro\u{201D} or \u{201C}remind me to call Sam at 5\u{201D}"

    init(ai: AIService, timers: TimerStore, activities: ActivityCenter) {
        self.ai = ai
        self.timers = timers
        self.activities = activities
    }

    var isDictationTarget: Bool { focusedFields > 0 }

    func requestFocus() { wantsFocus = true }

    func focusTaken() { wantsFocus = false }

    func fieldFocused(_ focused: Bool) {
        focusedFields = max(focusedFields + (focused ? 1 : -1), 0)
    }

    func appendDictation(_ dictated: String) {
        text = DictationText.appending(dictated, to: text)
    }

    /// Reads the field: the parser first, then the AI when it's on. Times are read in the
    /// user's own time zone and calendar.
    func submit() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, state != .thinking else { return }
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let read = QuickInputParser.read(input, now: now, calendar: calendar)
        switch QuickInputFlow.step(for: read, aiReady: ai.isReady) {
        case .propose(let intent): propose(intent, input: input)
        case .passed: show(QuickIntentCheck.passed)
        case .hint: show(Self.hint)
        case .askModel(let fallback): askModel(input, now: now, calendar: calendar, fallback: fallback)
        }
    }

    private func askModel(_ input: String, now: Date, calendar: Calendar, fallback: QuickIntent?) {
        state = .thinking
        work?.cancel()
        work = Task { [weak self] in
            guard let self else { return }
            let intent: QuickIntent?
            do {
                let answer = try await self.ai.run(.quickInput(now: now, timeZone: calendar.timeZone), on: input)
                intent = QuickInputParser.intent(fromModel: answer.text, now: now, calendar: calendar)
            } catch {
                self.log.info("Quick input: the AI task failed")
                intent = nil
            }
            guard !Task.isCancelled else { return }
            switch QuickInputFlow.step(afterModel: intent, fallback: fallback) {
            case .propose(let chosen): self.propose(chosen, input: input)
            case .passed: self.show(QuickIntentCheck.passed)
            case .hint, .askModel: self.show(Self.hint)
            }
        }
    }

    private func propose(_ intent: QuickIntent, input: String) {
        if let problem = QuickIntentCheck.problem(intent, now: .now) { return show(problem) }
        state = .idle
        pending = intent
        pendingInput = input
        activities.post(.quickIntent(intent), slot: .quickInput, duration: Self.cardSeconds)
    }

    func cancel() {
        pending = nil
        activities.remove(.quickInput)
    }

    /// Makes what the card shows, checked against the time again since the card may have waited.
    /// Reminders and events ask for access the first time.
    func confirm() {
        guard let intent = pending else { return }
        let input = pendingInput
        pending = nil
        activities.remove(.quickInput)
        if let problem = QuickIntentCheck.problem(intent, now: .now) { return failed(problem) }
        switch intent {
        case .timer(.minutes(let minutes)):
            timers.startTimer(minutes: minutes)
            done("Timer started", symbol: "timer", input: input)
        case .timer(.pomodoro):
            if !(timers.phase == .focus && timers.pomodoro.isRunning) {
                timers.setPhase(.focus)
                timers.togglePomodoro()
            }
            done("Pomodoro started", symbol: "brain.head.profile", input: input)
        case .reminder(let title, let due):
            Task { await save(reminder: title, due: due, input: input) }
        case .event(let title, let start, let minutes):
            Task { await save(event: title, start: start, minutes: minutes, input: input) }
        }
    }

    private func save(reminder title: String, due: Date?, input: String) async {
        let asked = EKEventStore.authorizationStatus(for: .reminder) != .notDetermined
        guard await Permission.canSave(.reminder, in: store) else {
            return refused(.reminders, text: "Allow Reminders to add reminders", askedBefore: asked)
        }
        guard let list = store.defaultCalendarForNewReminders() else { return failed("No Reminders list to add to") }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            var components = Calendar.autoupdatingCurrent.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            components.timeZone = Calendar.autoupdatingCurrent.timeZone
            reminder.dueDateComponents = components
            // A due date alone doesn't alert; the alarm is what makes it go off.
            reminder.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(reminder, commit: true)
            done("Reminder added", symbol: "checklist", input: input)
        } catch {
            log.error("Saving a reminder failed: \(error.localizedDescription, privacy: .public)")
            failed("Couldn't add the reminder")
        }
    }

    private func save(event title: String, start: Date, minutes: Int, input: String) async {
        let asked = EKEventStore.authorizationStatus(for: .event) != .notDetermined
        guard await Permission.canSave(.event, in: store) else {
            return refused(.calendars, text: "Allow Calendars to add events", askedBefore: asked)
        }
        guard let calendar = store.defaultCalendarForNewEvents else { return failed("No calendar to add to") }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
            done("Event added", symbol: "calendar.badge.plus", input: input)
        } catch {
            log.error("Saving an event failed: \(error.localizedDescription, privacy: .public)")
            failed("Couldn't add the event")
        }
    }

    /// Made: the field empties, unless the user has typed something new since.
    private func done(_ message: String, symbol: String, input: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines) == input { text = "" }
        show(message)
        activities.post(.notice(symbol: symbol, text: message), slot: .notice, duration: 2)
    }

    private func failed(_ text: String) {
        show(text)
        activities.post(.notice(symbol: "exclamationmark.triangle", text: text), slot: .notice, duration: 3)
    }

    /// No access. When it was turned down before this request, macOS won't ask again, so the
    /// switch is in System Settings; a "Don't Allow" just now is left alone.
    private func refused(_ permission: Permission, text: String, askedBefore: Bool) {
        failed(text)
        if askedBefore { permission.openSettings() }
    }

    private func show(_ message: String) {
        state = .message(message)
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.state == .message(message) else { return }
            self.state = .idle
        }
    }
}

import Foundation

/// Push-to-talk for dictation: hold the key to record, let go to transcribe and deliver.
/// Each event returns the one thing the app should do next.
public struct PushToTalk: Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The key is down but the hold hasn't counted yet; letting go now is a tap.
        case pressed(since: Date)
        case recording(since: Date)
        /// The key is still held but recording couldn't start (shared key only): letting go
        /// is a tap.
        case blocked
        /// The key is up and the last words are being transcribed.
        case finishing
        case delivering

        /// The microphone is on.
        public var isListening: Bool {
            if case .recording = self { true } else { false }
        }

        public var isActive: Bool { self != .idle }
    }

    public enum DiscardReason: Equatable, Sendable {
        case cancelled
        case tooShort
        case nothingHeard
        case failed
        /// Recording couldn't start (permissions, no on-device model, no microphone).
        case unavailable
    }

    public enum Effect: Equatable, Sendable {
        case none
        /// Do what the shared key normally does (open the shelf). Leaves any dictation in
        /// progress alone.
        case tap
        /// A hold too short to dictate on the shared key: throw the recording away, then open
        /// the shelf.
        case tapDiscardingRecording
        case startRecording
        /// Stop the microphone and wait for the final transcript.
        case finishRecording
        /// Stop the microphone and throw the audio and any text away.
        case discard(DiscardReason)
        case deliver(String)
    }

    /// When the dictation key also opens the shelf, a press shorter than this opens the shelf.
    public static let sharedKeyHoldDelay: TimeInterval = 0.3

    public private(set) var phase: Phase = .idle
    /// The dictation key also opens the shelf, so a press that doesn't become dictation
    /// opens the shelf instead of showing an error.
    public let sharedWithShelf: Bool
    /// Shorter recordings are a slip of the finger, not speech.
    public let minimumRecording: TimeInterval

    public var holdDelay: TimeInterval { sharedWithShelf ? Self.sharedKeyHoldDelay : 0 }

    public init(sharedWithShelf: Bool, minimumRecording: TimeInterval = 0.4) {
        self.sharedWithShelf = sharedWithShelf
        self.minimumRecording = minimumRecording
    }

    /// Key down.
    public mutating func press(at now: Date) -> Effect {
        switch phase {
        case .idle:
            guard sharedWithShelf else {
                phase = .recording(since: now)
                return .startRecording
            }
            phase = .pressed(since: now)
            return .none
        case .finishing, .delivering:
            // Still busy with the last dictation: the shelf key keeps working.
            return sharedWithShelf ? .tap : .none
        case .pressed, .recording, .blocked:
            return .none
        }
    }

    /// The app's hold timer fired.
    public mutating func holdElapsed(at now: Date) -> Effect {
        // A millisecond of slack for timers and date arithmetic.
        guard case .pressed(let since) = phase, now.timeIntervalSince(since) >= holdDelay - 0.001 else {
            return .none
        }
        phase = .recording(since: now)
        return .startRecording
    }

    /// Recording was asked for but couldn't start.
    public mutating func unavailable() -> Effect {
        guard case .recording = phase else { return .none }
        guard sharedWithShelf else {
            phase = .idle
            return .discard(.unavailable)
        }
        phase = .blocked
        return .none
    }

    /// Key up.
    public mutating func release(at now: Date) -> Effect {
        switch phase {
        case .pressed, .blocked:
            phase = .idle
            return .tap
        case .recording(let since):
            guard now.timeIntervalSince(since) >= minimumRecording else {
                phase = .idle
                return sharedWithShelf ? .tapDiscardingRecording : .discard(.tooShort)
            }
            phase = .finishing
            return .finishRecording
        case .idle, .finishing, .delivering:
            return .none
        }
    }

    /// Escape, or the key-up was lost (the keyboard tap was reset).
    public mutating func cancel() -> Effect {
        switch phase {
        case .pressed, .blocked:
            phase = .idle
            return .none
        case .recording, .finishing:
            phase = .idle
            return .discard(.cancelled)
        case .idle, .delivering:
            return .none
        }
    }

    /// The final transcript arrived. Only counts once the key is up.
    public mutating func transcribed(_ raw: String) -> Effect {
        guard phase == .finishing else { return .none }
        let text = DictationText.tidy(raw)
        guard !text.isEmpty else {
            phase = .idle
            return .discard(.nothingHeard)
        }
        phase = .delivering
        return .deliver(text)
    }

    /// The recognizer or the microphone gave up.
    public mutating func failed() -> Effect {
        switch phase {
        case .recording, .finishing:
            phase = .idle
            return .discard(.failed)
        case .idle, .pressed, .blocked, .delivering:
            return .none
        }
    }

    public mutating func delivered() {
        if phase == .delivering { phase = .idle }
    }
}

/// Where dictated text goes.
public enum DictationTarget: Equatable, Sendable {
    /// The prompt draft box of the session open in the Agents view.
    case agentDraft(session: String)
    /// The typed answer of the question card under the notch.
    case questionAnswer(UUID)
    /// The quick add field in the open shelf.
    case quickInput
    /// Pasted into the app in front.
    case focusedApp

    /// The draft box the user is looking at first, then the quick add field they're typing in,
    /// then a question waiting for them, then whatever app has focus.
    public static func choose(draftSession: String?, questionCard: UUID?, quickInput: Bool = false)
        -> DictationTarget
    {
        if let draftSession, !draftSession.isEmpty { return .agentDraft(session: draftSession) }
        if quickInput { return .quickInput }
        if let questionCard { return .questionAnswer(questionCard) }
        return .focusedApp
    }

    /// Inside Wisp the field itself shows it's listening; a pill would cover the question card.
    public var showsPill: Bool { self == .focusedApp }
}

/// Which view's draft box dictation types into. Each Agents view claims it with its own
/// token, so a view going away can't clear a newer view's claim.
public struct DraftBoxClaim: Equatable, Sendable {
    public let owner: UUID
    public let session: String

    public init(owner: UUID, session: String) {
        self.owner = owner
        self.session = session
    }

    /// `owner` now shows `session`'s draft box, or none (nil, while details are private).
    public static func claim(_ current: DraftBoxClaim?, owner: UUID, session: String?) -> DraftBoxClaim? {
        if let session { return DraftBoxClaim(owner: owner, session: session) }
        return release(current, owner: owner)
    }

    /// `owner` went away: clears the claim only if it's still that view's.
    public static func release(_ current: DraftBoxClaim?, owner: UUID) -> DraftBoxClaim? {
        current?.owner == owner ? nil : current
    }
}

/// How dictated text reaches the app in front.
public enum DictationPaste {
    public enum Action: Equatable, Sendable {
        case paste
        /// Focus moved to another app while recording: copy rather than type into the wrong one.
        case copy
    }

    public static func action(appAtStart: Int32?, appNow: Int32?) -> Action {
        guard let appAtStart, appAtStart == appNow else { return .copy }
        return .paste
    }

    /// Clipboard types Wisp can hold and put back after a paste (plain text, rich text, HTML,
    /// images, PDF, file and web links).
    public static let restorableTypes = [
        "public.utf8-plain-text", "public.rtf", "public.html", "public.png", "public.tiff", "public.jpeg",
        "com.adobe.pdf", "public.file-url", "public.url",
    ]

    /// Whether the clipboard, given each item's types, can be put back exactly. Anything else
    /// (app-private data such as Figma or Excel, or an item with no types) would come back
    /// partial or not at all, so the restore is skipped and the dictated text stays instead.
    public static func canCapture(itemTypes: [[String]]) -> Bool {
        let restorable = Set(restorableTypes)
        return itemTypes.allSatisfy { types in !types.isEmpty && types.allSatisfy(restorable.contains) }
    }

    /// The most clipboard data put back after a paste. Bigger clipboards (a large image or
    /// file contents) are left alone rather than held in memory and rewritten.
    public static let restoreLimit = 10 * 1024 * 1024

    public static func canRestore(byteCount: Int) -> Bool { byteCount <= restoreLimit }

    /// Puts the user's clipboard back unless something was copied since Wisp staged the text.
    public static func shouldRestore(stagedChangeCount: Int, currentChangeCount: Int) -> Bool {
        stagedChangeCount == currentChangeCount
    }
}

/// The text heard so far in one hold. The recognizer can end a result early (a long
/// pause) while the key is still held; that part is kept and listening goes on.
public struct DictationTranscript: Equatable, Sendable {
    public private(set) var committed: [String] = []
    public private(set) var partial = ""

    public init() {}

    public mutating func update(_ partial: String) {
        self.partial = partial
    }

    /// A final result: kept, and the next words start fresh.
    public mutating func commit(_ final: String) {
        let text = DictationText.tidy(final)
        if !text.isEmpty { committed.append(text) }
        partial = ""
    }

    public var text: String { DictationText.tidy((committed + [partial]).joined(separator: " ")) }
}

/// Optional clean-up of a transcript (filler words, punctuation), for example by an on-device
/// model. Returns nil when it can't help, and the transcript is used as it is.
public typealias DictationCleanup = @Sendable (String) async -> String?

public enum DictationText {
    /// How long clean-up may take before the transcript goes as it is.
    public static let cleanupTimeout: Duration = .seconds(2)

    /// Single spaces, no line breaks, nothing at the ends.
    public static func tidy(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Adds dictated text after what's already typed.
    public static func appending(_ text: String, to existing: String) -> String {
        guard !text.isEmpty else { return existing }
        guard let last = existing.last else { return text }
        return last.isWhitespace ? existing + text : existing + " " + text
    }

    /// The text to deliver: tidied, then cleaned up when a clean-up is set and answers in
    /// time. Nil for silence.
    public static func finish(
        _ raw: String, cleanup: DictationCleanup?, timeout: Duration = cleanupTimeout
    ) async -> String? {
        let text = tidy(raw)
        guard !text.isEmpty else { return nil }
        guard let cleanup, let cleaned = await first(of: cleanup, text, within: timeout) else { return text }
        let tidied = tidy(cleaned)
        return tidied.isEmpty ? text : tidied
    }

    /// The clean-up's answer, or nil if the timeout comes first. Doesn't wait for a clean-up
    /// that ignores cancellation; the loser of the race is cancelled.
    private static func first(of cleanup: @escaping DictationCleanup, _ text: String, within timeout: Duration)
        async -> String?
    {
        let race = CleanupRace()
        return await withCheckedContinuation { continuation in
            let timer = Task {
                try? await Task.sleep(for: timeout)
                if await race.expire() { continuation.resume(returning: nil) }
            }
            let work = Task {
                let result = await cleanup(text)
                timer.cancel()
                if await race.win() { continuation.resume(returning: result) }
            }
            Task { await race.track(work) }
        }
    }
}

/// Decides the clean-up race once: the first of the clean-up and the timeout resumes, and a
/// timeout cancels the clean-up.
private actor CleanupRace {
    private var decided = false
    private var work: Task<Void, Never>?

    func win() -> Bool {
        guard !decided else { return false }
        decided = true
        return true
    }

    func expire() -> Bool {
        guard win() else { return false }
        work?.cancel()
        return true
    }

    /// The clean-up task, handed over just after it starts; cancelled at once if it already lost.
    func track(_ task: Task<Void, Never>) {
        if decided { task.cancel() } else { work = task }
    }
}

/// A permission as dictation sees it.
public enum DictationPermission: Equatable, Sendable {
    case notAsked
    case granted
    case denied
}

/// Whether dictation can run, or what stops it.
public enum DictationReadiness: Equatable, Sendable {
    case ready
    /// Push-to-talk needs the key-up, which only the Caps Lock (Hyper) tap sees.
    case needsHyperKey
    case needsPermission
    case speechDenied
    case microphoneDenied
    /// Recognition would need Apple's servers for this language. Wisp never sends audio there.
    case onDeviceUnavailable
    case noMicrophone

    public static func check(
        speech: DictationPermission, microphone: DictationPermission, onDeviceRecognition: Bool, hyperKey: Bool,
        hasMicrophone: Bool
    ) -> DictationReadiness {
        guard hyperKey else { return .needsHyperKey }
        if speech == .denied { return .speechDenied }
        if microphone == .denied { return .microphoneDenied }
        if speech == .notAsked || microphone == .notAsked { return .needsPermission }
        guard hasMicrophone else { return .noMicrophone }
        guard onDeviceRecognition else { return .onDeviceUnavailable }
        return .ready
    }

    public var isReady: Bool { self == .ready }

    public var message: String {
        switch self {
        case .ready: "Ready"
        case .needsHyperKey: "Turn on Caps Lock + Space for the shelf to use dictation"
        case .needsPermission: "Needs Speech Recognition and Microphone access"
        case .speechDenied: "Speech Recognition is off for Wisp in System Settings"
        case .microphoneDenied: "Microphone access is off for Wisp in System Settings"
        case .onDeviceUnavailable: "On-device dictation isn't available for your language"
        case .noMicrophone: "No microphone found"
        }
    }
}

/// The key held with Caps Lock to dictate.
public enum DictationKey: String, CaseIterable, Sendable {
    case space
    case d
    case m

    public var keyCode: UInt16 {
        switch self {
        case .space: KeyCodes.space
        case .d: 2
        case .m: 46
        }
    }

    public var title: String {
        switch self {
        case .space: "Caps Lock + Space"
        case .d: "Caps Lock + D"
        case .m: "Caps Lock + M"
        }
    }

    /// Also opens the shelf, so a quick press still does.
    public func sharesShelfKey(_ shelfKey: UInt16) -> Bool { keyCode == shelfKey }
}

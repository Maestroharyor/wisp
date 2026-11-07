import Foundation

/// Keyboard answers for the approval or question card on screen: Hyper+Y allows, Hyper+N
/// denies and Hyper+1 to 9 picks a question's option. Without Hyper the same keys work with
/// ⌃⌥⌘, registered only while a card shows. `Gate` keeps one press to one answer.
public enum ApprovalKeys {
    public enum Action: Equatable, Sendable {
        case allow
        case deny
        /// The option at this index in the current question.
        case pick(Int)
        /// Sends a multiple choice answer.
        case send
    }

    public static let yes: UInt16 = 16
    public static let no: UInt16 = 45
    /// Number row 1 to 9.
    public static let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

    /// What `keyCode` does on a card for `prompt`; nil leaves the key to other shortcuts
    /// (digits keep picking profiles on cards without options).
    public static func action(keyCode: UInt16, prompt: PermissionPrompt) -> Action? {
        if prompt == .question {
            if keyCode == yes { return .send }
            return KeyCodes.digit(forKeyCode: keyCode).map { .pick($0 - 1) }
        }
        switch keyCode {
        case yes: return .allow
        case no: return .deny
        default: return nil
        }
    }

    /// Like a click, a key can't answer a card that has only just swapped in.
    public static let settleDelay: TimeInterval = 0.4

    public static func isSettled(shownAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(shownAt) >= settleDelay
    }

    public static let fallbackModifiers: Hotkey.Modifiers = [.control, .option, .command]

    /// Every key the fallback can register, in a fixed order, so each has its own Carbon id.
    public static let allFallbackKeys: [UInt16] = [yes, no] + digits

    /// ⌃⌥⌘ with only the keys that do something on this card: Y and N for a request or a
    /// plan, Y and 1 to 9 for a question.
    public static func fallbackHotkeys(for prompt: PermissionPrompt) -> [Hotkey] {
        let keys = prompt == .question ? [yes] + digits : [yes, no]
        return keys.map { Hotkey(keyCode: $0, modifiers: fallbackModifiers) }
    }

    /// Decides whether a key press may answer. A held key repeats, and each answer brings
    /// the next card (or question) forward, so without this one long press would answer
    /// several. A press counts only when it isn't a repeat, the key was let go since its
    /// last press, and the card or question step has been on screen for `settleDelay`.
    public struct Gate: Sendable {
        private var held: Set<UInt16> = []
        private var shownAt: Date?

        public init() {}

        /// A new card took the front, or a question moved to its next step.
        public mutating func cardChanged(at date: Date) {
            shownAt = date
        }

        public mutating func press(_ keyCode: UInt16, isRepeat: Bool, at now: Date) -> Bool {
            guard !isRepeat, held.insert(keyCode).inserted, let shownAt else { return false }
            return isSettled(shownAt: shownAt, now: now)
        }

        public mutating func release(_ keyCode: UInt16) {
            held.remove(keyCode)
        }

        /// Key-ups may have been missed (the keyboard tap restarted, no card left to answer).
        public mutating func releaseAll() {
            held.removeAll()
        }
    }
}

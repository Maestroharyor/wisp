/// Wisp's keyboard shortcuts besides the shelf's own, which lives in `Preferences.hotkey`.
public enum ShortcutAction: String, CaseIterable, Sendable, Identifiable {
    case ring
    case cycleForm
    case clipboard
    case sessionSwitcher

    public var id: Self { self }

    public var title: String {
        switch self {
        case .ring: "Open the ring"
        case .cycleForm: "Change form"
        case .clipboard: "Clipboard history"
        case .sessionSwitcher: "Jump to an agent session"
        }
    }

    /// The letter it sits on by default.
    var letter: UInt16 {
        switch self {
        case .ring: KeyCodes.r
        case .cycleForm: KeyCodes.f
        case .clipboard: KeyCodes.v
        case .sessionSwitcher: KeyCodes.g
        }
    }

    /// The default without Caps Lock, or when the shelf takes the Caps Lock one.
    var fallback: Hotkey {
        switch self {
        case .clipboard: Hotkey.clipboardFallback
        case .sessionSwitcher: Hotkey.switcherFallback
        case .ring, .cycleForm: Hotkey(keyCode: letter, modifiers: [.control, .option, .command])
        }
    }
}

/// The shortcuts people changed, over the defaults. A changed shortcut can also be turned off.
public struct ShortcutMap: Equatable, Sendable {
    /// Changed actions: a key, or nil for turned off. Actions not here use their default.
    private var custom: [ShortcutAction: Hotkey?]

    public init() {
        custom = [:]
    }

    /// Read back from `stored`: "" is off; anything unreadable keeps the default.
    public init(stored: [String: String]) {
        var custom: [ShortcutAction: Hotkey?] = [:]
        for (name, text) in stored {
            guard let action = ShortcutAction(rawValue: name) else { continue }
            if text.isEmpty {
                custom[action] = .some(nil)
            } else if let hotkey = Hotkey(string: text) {
                custom[action] = .some(hotkey)
            }
        }
        self.custom = custom
    }

    public var stored: [String: String] {
        Dictionary(uniqueKeysWithValues: custom.map { ($0.key.rawValue, $0.value?.stringValue ?? "") })
    }

    /// Caps Lock and the action's letter while the shelf uses Caps Lock and doesn't sit on that
    /// letter itself; otherwise the action's ⌃⌥⌘ (or ⌥⇧⌘) fallback.
    public static func standard(_ action: ShortcutAction, shelf: Hotkey) -> Hotkey {
        let hyper = Hotkey(keyCode: action.letter, modifiers: .hyper)
        return shelf.usesHyper && shelf != hyper ? hyper : action.fallback
    }

    /// The key in use, or nil when turned off.
    public func key(for action: ShortcutAction, shelf: Hotkey) -> Hotkey? {
        if let changed = custom[action] { return changed }
        return Self.standard(action, shelf: shelf)
    }

    public func isCustom(_ action: ShortcutAction) -> Bool { custom[action] != nil }

    /// Sets a key, or nil to turn the action off.
    public mutating func set(_ hotkey: Hotkey?, for action: ShortcutAction) {
        custom[action] = .some(hotkey)
    }

    public mutating func reset(_ action: ShortcutAction) {
        custom[action] = nil
    }

    /// What already uses `candidate`, by name, if `action` took it; nil when it's free.
    /// Caps Lock with Y, N, 1–9 or the dictation key belongs to agent cards, profiles and
    /// dictation.
    public func clash(_ candidate: Hotkey, for action: ShortcutAction, shelf: Hotkey, holdKey: UInt16?) -> String? {
        if candidate == shelf { return "Open or close the shelf" }
        for other in ShortcutAction.allCases where other != action && key(for: other, shelf: shelf) == candidate {
            return other.title
        }
        guard candidate.modifiers == .hyper else { return nil }
        if candidate.keyCode == ApprovalKeys.yes { return "Allow, or send an answer" }
        if candidate.keyCode == ApprovalKeys.no { return "Deny" }
        if ApprovalKeys.digits.contains(candidate.keyCode) { return "Pick an answer or switch profile" }
        if candidate.keyCode == holdKey { return "Dictation" }
        return nil
    }

    /// Actions whose key clashes with something else, so Settings can flag them.
    public func clashes(shelf: Hotkey, holdKey: UInt16?) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { action in
            guard let hotkey = key(for: action, shelf: shelf) else { return false }
            return clash(hotkey, for: action, shelf: shelf, holdKey: holdKey) != nil
        }
    }
}

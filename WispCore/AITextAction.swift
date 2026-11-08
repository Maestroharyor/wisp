import Foundation

/// Where the text for an AI action came from.
public enum AITextSource: Equatable, Sendable {
    /// Selected in the app in front, read through Accessibility.
    case selection
    /// The newest text on the clipboard, or an item picked in clipboard history.
    case clipboard
}

/// The text an AI action works on, where it came from and the app that was in front.
public struct AITextInput: Equatable, Sendable {
    public let text: String
    public let source: AITextSource
    /// Process id of the app in front when the text was read. The answer is only pasted back
    /// into that app, so a switch while the model works can't put it somewhere else.
    public let app: Int32?

    public init(text: String, source: AITextSource, app: Int32?) {
        self.text = text
        self.source = source
        self.app = app
    }

    /// The selection when there is some, else the clipboard's text. Blank text counts as none.
    public static func pick(selection: String?, clipboard: String?, app: Int32?) -> AITextInput? {
        if let selection, !isBlank(selection) { return AITextInput(text: selection, source: .selection, app: app) }
        if let clipboard, !isBlank(clipboard) { return AITextInput(text: clipboard, source: .clipboard, app: app) }
        return nil
    }

    /// Whether the answer may be pasted into the app in front now.
    public func canPaste(appNow: Int32?) -> Bool {
        guard let app, app == appNow else { return false }
        return true
    }

    /// Whether Replace may paste over the selection read again just before pasting: it must
    /// still be the text the answer was made from, or the paste would replace something else.
    /// Clipboard text has no selection to check.
    public func selectionUnchanged(_ selectionNow: String?) -> Bool {
        source == .clipboard || selectionNow == text
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Which clipboard text AI actions may read.
public enum AIClipboardText {
    /// The clipboard's text, or nil when the clipboard is marked private or holds no text.
    public static func text(_ string: String?, types: [String]) -> String? {
        guard Set(types).isDisjoint(with: ClipClassifier.privateTypes), let string,
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return string
    }

    /// Whether a history item gets AI actions: plain text only. Concealed items never reach
    /// history, and links, images and colours have nothing to summarise or rewrite.
    public static func offers(_ item: ClipItem) -> Bool {
        guard item.kind == .text, let text = item.text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension AITask {
    /// The tasks offered on selected or copied text, in menu order, translating into `language`.
    public static func textActions(language: String) -> [AITask] {
        var tasks = menu
        tasks.insert(.translate(language: language), at: 1)
        return tasks
    }

    /// A stable name for the task, saved as a ring action's value. Nil for tasks that don't
    /// work on selected text.
    public var actionID: String? {
        switch self {
        case .summarise: "summarise"
        case .translate: "translate"
        case .fixGrammar: "fixGrammar"
        case .rewrite(let tone): "rewrite.\(tone.rawValue)"
        case .actionItems: "actionItems"
        case .explain: "explain"
        case .sessionSummary, .quickInput: nil
        }
    }

    /// The task saved as `actionID`. Translate takes the language from Settings, so changing
    /// it there changes every saved action.
    public init?(actionID: String, language: String) {
        guard let task = Self.textActions(language: language).first(where: { $0.actionID == actionID }) else {
            return nil
        }
        self = task
    }

    /// A short name for a saved action, without the language, for the ring and its editor.
    public static func actionTitle(id: String) -> String? {
        guard let task = AITask(actionID: id, language: "") else { return nil }
        if case .translate = task { return "Translate" }
        return task.title
    }

    /// What the result card says while the model works.
    public var progressTitle: String {
        switch self {
        case .summarise: "Summarising"
        case .translate(let language): "Translating to \(Self.languageName(language))"
        case .fixGrammar: "Fixing grammar"
        case .rewrite: "Rewriting"
        case .actionItems: "Finding action items"
        case .explain: "Explaining"
        case .sessionSummary: "Summarising the session"
        case .quickInput: "Reading"
        }
    }

    /// The answer stands in for the text it was given (translated, fixed, rewritten), so
    /// putting it back over the selection is the main thing to do with it.
    public var replacesText: Bool {
        switch self {
        case .translate, .fixGrammar, .rewrite: true
        case .summarise, .actionItems, .explain, .sessionSummary, .quickInput: false
        }
    }

    private static func languageName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "English" : trimmed
    }
}

/// The buttons on an AI result card.
public enum AIResultButton: Hashable, Sendable {
    case copy
    /// Pastes over the selection the text came from.
    case replace
    /// Pastes into the app in front; for text that came from the clipboard.
    case paste

    public var title: String {
        switch self {
        case .copy: "Copy"
        case .replace: "Replace"
        case .paste: "Paste"
        }
    }

    /// Copy, then Replace for a selection or Paste for clipboard text. The last one is drawn
    /// in the accent.
    public static func buttons(task: AITask, source: AITextSource) -> [AIResultButton] {
        let insert: AIResultButton = source == .selection ? .replace : .paste
        // Answers that stand in for the text lead with putting it back; the rest with Copy.
        return task.replacesText ? [.copy, insert] : [insert, .copy]
    }

    /// The card's second line: what it's working on, or where the answer came from.
    public static func subtitle(source: AITextSource, working: Bool, truncated: Bool) -> String {
        let from = source == .selection ? "the selection" : "the clipboard"
        if working { return "Working on \(from)" }
        if truncated { return "From \(from), only its start and end" }
        return "From \(from)"
    }
}

extension RingAction {
    /// The AI task an `.ai` action runs, as its `actionID`. Summarise when unset.
    public var aiTaskID: String { value ?? "summarise" }
}

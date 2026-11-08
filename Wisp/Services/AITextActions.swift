import AppKit
import WispCore

/// AI actions on text: the selection in the app in front (from the ring) or a clipboard item
/// (from the clipboard panel). The answer shows in a card under the notch with Copy and
/// Replace. Runs through `AIService`, so nothing leaves the Mac; text and answers are never logged.
@MainActor
final class AITextActions {
    private let ai: AIService
    private let preferences: Preferences
    private let activities: ActivityCenter
    /// Hands the keyboard back from the notch before a paste.
    private let releaseNotchKey: @MainActor () -> Void
    /// The request the card is waiting on; cancelled when the card closes or a new one starts.
    private var work: Task<Void, Never>?

    /// Longer than dictation's: an app may take a moment to read a long pasted answer before
    /// the clipboard goes back.
    private static let restoreDelay: Duration = .milliseconds(1500)
    /// Lets the notch give up the keyboard before ⌘V is sent.
    private static let pasteDelay: Duration = .milliseconds(150)

    init(
        ai: AIService, preferences: Preferences, activities: ActivityCenter,
        releaseNotchKey: @escaping @MainActor () -> Void
    ) {
        self.ai = ai
        self.preferences = preferences
        self.activities = activities
        self.releaseNotchKey = releaseNotchKey
    }

    /// The tasks menus offer, translating into the language chosen in Settings › AI.
    var tasks: [AITask] { AITask.textActions(language: preferences.aiTranslateLanguage) }
    var isEnabled: Bool { preferences.aiEnabled }
    var isReady: Bool { ai.isReady }
    var statusMessage: String { ai.status.message }

    /// Checks the engine again, so a menu about to show has a fresh status.
    func refresh() {
        guard preferences.aiEnabled else { return }
        Task { await ai.refresh() }
    }

    /// Says why the tasks can't run now: AI is off or the engine isn't ready. An older answer's
    /// card goes first, since it would hide the notice.
    func showStatus() {
        activities.remove(.aiResult)
        notice(isEnabled ? statusMessage : "Turn on AI in Settings first", symbol: "sparkle")
    }

    /// Stops the request the card is waiting on. Called when the card closes.
    func cancel() {
        work?.cancel()
        work = nil
    }

    /// From the ring: runs the task saved as `actionID` on the selection in the app in front,
    /// or else on the clipboard's text, unless the clipboard is marked private.
    func runOnSelection(actionID: String) {
        guard let task = AITask(actionID: actionID, language: preferences.aiTranslateLanguage) else { return }
        guard preferences.aiEnabled else {
            showStatus()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let pasteboard = NSPasteboard.general
        let clipboard = AIClipboardText.text(
            pasteboard.string(forType: .string), types: (pasteboard.types ?? []).map(\.rawValue))
        let trusted = AccessibilityPermission.isTrusted
        Task { [weak self] in
            var selection: String?
            if trusted, let app { selection = await SelectedText.read(from: app) }
            guard let self else { return }
            guard let input = AITextInput.pick(selection: selection, clipboard: clipboard, app: app) else {
                // An older answer's card would hide the notice.
                self.activities.remove(.aiResult)
                self.notice("Select or copy some text first", symbol: "text.cursor")
                return
            }
            self.start(task, on: input)
        }
    }

    /// From the clipboard panel: runs `task` on a text item from history.
    func run(_ task: AITask, on item: ClipItem) {
        guard AIClipboardText.offers(item), let text = item.text else { return }
        let app = NSWorkspace.shared.frontmostApplication?.processIdentifier
        start(task, on: AITextInput(text: text, source: .clipboard, app: app))
    }

    private func start(_ task: AITask, on input: AITextInput) {
        cancel()
        let card = AIResultCard(id: UUID(), task: task, input: input, answer: nil)
        activities.post(.aiResult(card), slot: .aiResult, duration: nil)
        work = Task { [weak self] in
            guard let self else { return }
            do throws(AIError) {
                let answer = try await self.ai.run(task, on: input.text)
                // Closed while the model worked, or a newer action took its place.
                guard !Task.isCancelled, self.isShowing(card.id) else { return }
                let done = AIResultCard(id: card.id, task: task, input: input, answer: answer)
                self.activities.post(.aiResult(done), slot: .aiResult, duration: nil)
            } catch {
                guard !Task.isCancelled, self.isShowing(card.id) else { return }
                self.activities.remove(.aiResult)
                self.notice(error.message, symbol: "exclamationmark.triangle")
            }
        }
    }

    private func isShowing(_ id: UUID) -> Bool {
        guard case .aiResult(let card) = activities.activity(in: .aiResult) else { return false }
        return card.id == id
    }

    func perform(_ button: AIResultButton, on card: AIResultCard) {
        switch button {
        case .copy: copy(card)
        case .replace, .paste: insert(card)
        }
    }

    private func copy(_ card: AIResultCard) {
        guard let text = card.answer?.text else { return }
        activities.remove(.aiResult)
        put(text)
        notice("Copied", symbol: "doc.on.clipboard")
    }

    /// Pastes into the app the text came from, over the same selection, then puts the user's
    /// clipboard back. If that app is no longer in front, the selection changed, or Wisp can't
    /// send keys, the answer is copied instead.
    private func insert(_ card: AIResultCard) {
        guard let text = card.answer?.text else { return }
        activities.remove(.aiResult)
        guard AccessibilityPermission.isTrusted else {
            put(text)
            notice("Copied. Pasting needs Accessibility", symbol: "doc.on.clipboard")
            return
        }
        // The answer's text can be selected, which makes the notch key; ⌘V would land there.
        releaseNotchKey()
        Task { [weak self] in
            try? await Task.sleep(for: Self.pasteDelay)
            let appNow = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard let self else { return }
            guard card.input.canPaste(appNow: appNow) else {
                self.put(text)
                self.notice("Copied, since another app is in front", symbol: "doc.on.clipboard")
                return
            }
            if card.input.source == .selection {
                var selectionNow: String?
                if let appNow { selectionNow = await SelectedText.read(from: appNow) }
                guard card.input.selectionUnchanged(selectionNow) else {
                    self.put(text)
                    self.notice("Copied, since the selection changed", symbol: "doc.on.clipboard")
                    return
                }
            }
            PasteShortcut.pasteRestoring(text, after: Self.restoreDelay)
        }
    }

    /// A plain copy, so clipboard history keeps the answer.
    private func put(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func notice(_ text: String, symbol: String) {
        activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
    }
}

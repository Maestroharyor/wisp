import AppIntents
import WispCore

// Shortcuts actions. Each one is a thin call into `Automation`, which uses the same services as
// the notch. Approve and Deny live here and nowhere a wisp:// link can reach. A saved Shortcut
// can still be started from a web page, so they confirm first unless the user turns that off.

/// What Shortcuts shows when an action can't run.
struct IntentFailure: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

@MainActor
private func automation() throws(IntentFailure) -> Automation {
    guard let shared = Automation.shared else { throw IntentFailure(message: "Wisp is still starting.") }
    return shared
}

@MainActor
private func run(_ command: ExternalCommand) throws(IntentFailure) {
    let target = try automation()
    do {
        try target.perform(command, from: .shortcut)
    } catch {
        throw IntentFailure(message: error.message)
    }
}

/// Answers the card on screen if it's a tool permission, asking first while `confirmFirst` is on.
/// A saved Shortcut can be run from any web page (`shortcuts://run-shortcut`), so the question is
/// the guard a link doesn't have.
@MainActor
private func answerFront<Intent: AppIntent>(
    _ intent: Intent, allow: Bool, confirmFirst: IntentParameter<Bool>
) async throws -> String {
    let target = try automation()
    let pending: Automation.PendingAnswer
    do {
        pending = try target.frontRequest()
    } catch {
        throw IntentFailure(message: error.message)
    }
    if confirmFirst.wrappedValue {
        let dialog: IntentDialog =
            "\(ShortcutAnswer.confirmation(pending.request, allow: allow, hidden: pending.hidden))"
        if #available(macOS 15.0, *) {
            try await intent.requestConfirmation(actionName: .continue, dialog: dialog)
        } else {
            // macOS 14's intent-level confirmation is deprecated; the parameter's own one isn't.
            guard try await confirmFirst.requestConfirmation(for: true, dialog: dialog) else {
                throw IntentFailure(message: "Not answered.")
            }
        }
    }
    do {
        return try target.answer(pending, allow: allow)
    } catch {
        throw IntentFailure(message: error.message)
    }
}

enum WispPage: String, AppEnum {
    case home
    case tray
    case media
    case widgets

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let caseDisplayRepresentations: [WispPage: DisplayRepresentation] = [
        .home: "Home", .tray: "Tray", .media: "Media", .widgets: "Widgets",
    ]

    var external: ExternalPage {
        switch self {
        case .home: .home
        case .tray: .tray
        case .media: .media
        case .widgets: .widgets
        }
    }
}

struct OpenPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Wisp page"
    static let description = IntentDescription("Opens the shelf on a page.")

    @Parameter(title: "Page", default: .home)
    var page: WispPage

    @MainActor
    func perform() async throws -> some IntentResult {
        try run(.openPage(page.external))
        return .result()
    }
}

struct SwitchProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch Wisp profile"
    static let description = IntentDescription("Switches to a profile by name and holds it for 30 minutes.")

    @Parameter(title: "Profile")
    var profile: String

    @MainActor
    func perform() async throws -> some IntentResult {
        switch ExternalCommand.profileName(profile) {
        case .success(let name): try run(.switchProfile(name))
        case .failure(let error): throw IntentFailure(message: error.message)
        }
        return .result()
    }
}

struct StartTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Wisp timer"
    static let description = IntentDescription("Starts the notch timer, replacing one already running.")

    // The range must be a literal for the metadata extractor; it matches `ExternalCommand.timerMinutes`,
    // which still checks the value.
    @Parameter(title: "Minutes", default: 25, inclusiveRange: (1, 180))
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult {
        try run(.startTimer(minutes: minutes))
        return .result()
    }
}

struct PostActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Wisp activity"
    static let description = IntentDescription(
        "Shows or updates a live activity beside the notch. Use the same ID again to update it.")

    @Parameter(title: "ID", default: "shortcut")
    var id: String

    @Parameter(title: "Title")
    var title: String

    @Parameter(
        title: "Symbol", description: "An SF Symbol from the list in wisp activity --help.", default: "bolt.fill")
    var symbol: String

    @Parameter(title: "Progress", description: "From 0 to 1. Leave empty for no progress.")
    var progress: Double?

    @MainActor
    func perform() async throws -> some IntentResult {
        var fields = ["id": id, "title": title, "symbol": symbol]
        if let progress { fields["progress"] = String(progress) }
        switch ExternalCommand.parse(activityVerb: "start", fields: fields) {
        case .success(let action): try run(.activity(action))
        case .failure(let error): throw IntentFailure(message: error.message)
        }
        return .result()
    }
}

struct EndActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "End Wisp activity"
    static let description = IntentDescription("Removes a live activity this or another Shortcut showed.")

    @Parameter(title: "ID", default: "shortcut")
    var id: String

    @MainActor
    func perform() async throws -> some IntentResult {
        switch ExternalCommand.parse(activityVerb: "end", fields: ["id": id]) {
        case .success(let action): try run(.activity(action))
        case .failure(let error): throw IntentFailure(message: error.message)
        }
        return .result()
    }
}

struct ApproveRequestIntent: AppIntent {
    static let title: LocalizedStringResource = "Approve agent request"
    static let description = IntentDescription(
        "Allows the coding agent request on screen in the notch. Plans and questions still need the notch.")

    @Parameter(
        title: "Confirm first",
        description: "Ask before answering. Turned off, any link that runs this Shortcut can answer requests.",
        default: true)
    var confirmFirst: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await answerFront(self, allow: true, confirmFirst: $confirmFirst)
        return .result(dialog: "\(text)")
    }
}

struct DenyRequestIntent: AppIntent {
    static let title: LocalizedStringResource = "Deny agent request"
    static let description = IntentDescription(
        "Denies the coding agent request on screen in the notch. Plans and questions still need the notch.")

    @Parameter(
        title: "Confirm first",
        description: "Ask before answering. Turned off, any link that runs this Shortcut can answer requests.",
        default: true)
    var confirmFirst: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = try await answerFront(self, allow: false, confirmFirst: $confirmFirst)
        return .result(dialog: "\(text)")
    }
}

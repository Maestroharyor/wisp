import AppKit
import OSLog
import Observation
import WispCore

/// Runs what `wisp://` links, `wisp activity` and Shortcuts ask for, through the services the
/// notch already uses. Links go through `ExternalCommand`, which has no way to answer an
/// agent's request; only Shortcuts (`frontRequest`, `answer`) can, since the user builds those,
/// and they confirm first unless the user turns that off.
@MainActor
@Observable
final class Automation {
    /// For App Intents, which the system creates on its own. Set once services start.
    private(set) static weak var shared: Automation?

    /// The outside activity on show, for the details its pill opens.
    private(set) var current: ExternalActivity? {
        didSet { if hasCurrent != (current != nil) { hasCurrent = current != nil } }
    }
    /// Whether an outside activity is on show, for views that shouldn't redraw on its progress.
    private(set) var hasCurrent = false

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private var board = ExternalActivities()
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "automation")

    init(services: AppServices) {
        self.services = services
    }

    /// Links that arrived before launch finished: AppKit can deliver the one that launched
    /// Wisp before `applicationDidFinishLaunching`.
    @ObservationIgnored private var early: [URL]? = []

    func start() {
        Self.shared = self
        services.agents.onExternalActivity = { [weak self] action in self?.problem(applying: action) }
    }

    /// Called once the notches exist, so a link can open the shelf.
    func acceptLinks() {
        let waiting = early ?? []
        early = nil
        waiting.forEach(open)
    }

    func stop() {
        expiryTask?.cancel()
    }

    /// A `wisp://` link from the browser, Terminal (`open`) or another app.
    func open(_ url: URL) {
        if early != nil {
            early?.append(url)
            return
        }
        do {
            try perform(ExternalCommand.parse(url: url).get(), from: .link)
        } catch {
            // The link came from outside, so what it said stays private.
            log.notice("ignored a link: \(error.message, privacy: .private)")
        }
    }

    /// `source` is a link or a Shortcut; the socket comes in through `problem(applying:)`.
    func perform(_ command: ExternalCommand, from source: ExternalActivitySource) throws(ExternalCommandError) {
        switch command {
        case .openPage(let page):
            services.openShelf(ShelfPage(name: page.rawValue))
        case .switchProfile(let name):
            let profiles = services.preferences.profiles
            guard let index = Profile.index(named: name, in: profiles) else {
                throw ExternalCommandError("No profile named \(name).")
            }
            services.context.choose(profiles[index])
        case .startTimer(let minutes):
            services.timers.startTimer(minutes: minutes)
        case .activity(let action):
            try apply(action, from: source)
        }
    }

    /// A request a Shortcut picked to answer, kept so the answer goes to the same one even if
    /// the user took a while to confirm.
    struct PendingAnswer {
        let id: UUID
        let request: ShortcutAnswer.Request
        let hidden: Bool
    }

    /// The card on screen, if a Shortcut may answer it (`ShortcutAnswer.pick`).
    func frontRequest() throws(ExternalCommandError) -> PendingAnswer {
        let front = services.agents.approvals.first
        if case .refuse(let reason) = ShortcutAnswer.pick(front: front?.prompt) { throw ExternalCommandError(reason) }
        guard let front else { throw ExternalCommandError(ShortcutAnswer.nothingWaiting) }
        let request = ShortcutAnswer.Request(
            agent: front.source.displayName, tool: front.tool, project: front.project, prompt: front.prompt,
            summary: front.summary)
        return PendingAnswer(id: front.id, request: request, hidden: services.agents.detailsHidden)
    }

    /// Allows or denies the picked request if it's still on screen, and says what was done.
    func answer(_ pending: PendingAnswer, allow: Bool) throws(ExternalCommandError) -> String {
        guard services.agents.approvals.first?.id == pending.id else {
            throw ExternalCommandError("That request was already answered.")
        }
        services.agents.answer(pending.id, allow: allow)
        return ShortcutAnswer.result(pending.request, allow: allow, hidden: services.agents.detailsHidden)
    }

    // MARK: Activities

    /// For the socket: nil when done, otherwise what goes back to the sender.
    private func problem(applying action: ExternalActivityAction) -> String? {
        do {
            try apply(action, from: .command)
            return nil
        } catch {
            return error.message
        }
    }

    private func apply(_ action: ExternalActivityAction, from source: ExternalActivitySource)
        throws(ExternalCommandError)
    {
        let applied = board.apply(action, from: source, now: .now)
        refresh()
        guard applied else { throw ExternalCommandError(ExternalActivities.notShowing(action.id)) }
    }

    /// Shows the activity touched last, and looks again when the next one runs out.
    private func refresh() {
        let now = Date.now
        board.prune(now: now)
        let shown = board.current(now: now)
        if shown != current { current = shown }
        if let shown {
            services.activities.post(.custom(shown), slot: .external, duration: nil)
        } else {
            services.activities.remove(.external)
        }
        expiryTask?.cancel()
        guard let expiry = board.expiry(now: now) else { return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(expiry.timeIntervalSinceNow + 0.01))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

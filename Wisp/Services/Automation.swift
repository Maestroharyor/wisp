import AppKit
import OSLog
import WispCore

/// Runs what `wisp://` links, `wisp activity` and Shortcuts ask for, through the services the
/// notch already uses. Links go through `ExternalCommand`, which has no way to answer an
/// agent's request; only Shortcuts (`frontRequest`, `answer`) can, since the user builds those,
/// and they confirm first unless the user turns that off.
@MainActor
final class Automation {
    /// For App Intents, which the system creates on its own. Set once services start.
    private(set) static weak var shared: Automation?

    private let services: AppServices
    private var board = ExternalActivities()
    private var expiryTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "automation")

    init(services: AppServices) {
        self.services = services
    }

    /// Links that arrived before launch finished: AppKit can deliver the one that launched
    /// Wisp before `applicationDidFinishLaunching`.
    private var early: [URL]? = []

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
            try perform(ExternalCommand.parse(url: url).get())
        } catch {
            // The link came from outside, so what it said stays private.
            log.notice("ignored a link: \(error.message, privacy: .private)")
        }
    }

    func perform(_ command: ExternalCommand) throws(ExternalCommandError) {
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
            try apply(action)
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
            try apply(action)
            return nil
        } catch {
            return error.message
        }
    }

    private func apply(_ action: ExternalActivityAction) throws(ExternalCommandError) {
        let applied = board.apply(action, now: .now)
        refresh()
        guard applied else { throw ExternalCommandError(ExternalActivities.notShowing(action.id)) }
    }

    /// Shows the activity touched last, and looks again when the next one runs out.
    private func refresh() {
        let now = Date.now
        board.prune(now: now)
        if let current = board.current(now: now) {
            services.activities.post(.custom(current), slot: .external, duration: nil)
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

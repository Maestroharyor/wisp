import AppKit
import CoreGraphics
import Foundation
import OSLog
import Observation
import WispCore

/// Phone and Watch push through ntfy (ntfy.sh or a self-hosted server), off until the user turns
/// it on. Publishes masked notices (`PushMessage`) when `PushPolicy` allows, and while approvals
/// wait it listens on the reply topic for the phone's Allow or Deny, which resolve through the
/// hub like the notch's buttons. Topics, tokens, nonces and message text are never logged.
@MainActor
@Observable
final class PushService {
    /// The last problem talking to the server, for Settings; nil when the last request worked.
    private(set) var problem: String?
    /// "Send test" is on its way.
    private(set) var testing = false
    /// The reply stream is open.
    private(set) var listening = false
    /// Whether an access token is saved, without holding it in observable state.
    private(set) var hasToken = false
    /// Whether a reply token for the Allow and Deny buttons is saved.
    private(set) var hasReplyToken = false

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let hub: AgentHub
    @ObservationIgnored private var policy = PushPolicy()
    @ObservationIgnored private var replies = PushReplies<UUID>()
    /// Approvals seen in the hub's queue, with when they arrived and their notification's
    /// sequence id once pushed.
    @ObservationIgnored private var tracked: [UUID: (arrived: Date, sequenceID: String?)] = [:]
    /// Answered from the phone, so no "Answered on the Mac" follows.
    @ObservationIgnored private var answeredByPhone: Set<UUID> = []
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var awayTask: Task<Void, Never>?
    @ObservationIgnored private var locked = false
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "push")

    /// Seconds between checks for the user leaving while an approval hasn't gone out.
    private let awayCheck: Duration = .seconds(15)
    /// The longest pause before reconnecting the reply stream.
    private let maximumBackoff: Double = 60

    init(preferences: Preferences, hub: AgentHub) {
        self.preferences = preferences
        self.hub = hub
        hasToken = KeychainStore.read(.ntfyToken) != nil
        hasReplyToken = KeychainStore.read(.ntfyReplyToken) != nil
    }

    // MARK: Lifecycle

    func stop() {
        reset()
    }

    /// Settings that shape what goes out. Turning push off forgets every pending reply.
    func apply(kinds: Set<PushKind>, mode: PushMode, idleMinutes: Int, enabled: Bool) {
        policy.kinds = kinds
        policy.mode = mode
        policy.idleMinutes = idleMinutes
        if enabled { approvalsChanged() } else { reset() }
    }

    private func reset() {
        replies = PushReplies()
        tracked = [:]
        answeredByPhone = []
        stopListening()
        awayTask?.cancel()
        awayTask = nil
    }

    /// From `SessionMonitor`, which only reports a real lock: switching to another account
    /// sends the same lock notification but isn't the user stepping away from this session.
    func setLocked(_ value: Bool) {
        locked = value
        // Locking is the clearest "I'm away"; anything waiting can go now.
        if value { approvalsChanged() }
    }

    // MARK: Settings

    /// Makes both topics the first time push is turned on.
    func ensureTopics() {
        if !PushTopic.isValid(preferences.pushTopic) { preferences.pushTopic = PushTopic.random() }
        if !PushTopic.isValid(preferences.pushReplyTopic) { preferences.pushReplyTopic = PushTopic.random() }
    }

    /// New topics for both directions; the phone must subscribe again, and old buttons stop working.
    func regenerateTopics() {
        preferences.pushTopic = PushTopic.random()
        preferences.pushReplyTopic = PushTopic.random()
        replies = PushReplies()
        stopListening()
    }

    /// Saves the token in the Keychain, or removes it when empty.
    func setToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeychainStore.write(trimmed, for: .ntfyToken) {
            hasToken = !trimmed.isEmpty
        } else {
            problem = "Couldn't save the token in the Keychain"
        }
    }

    /// Saves the buttons' reply token in the Keychain, or removes it when empty.
    func setReplyToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeychainStore.write(trimmed, for: .ntfyReplyToken) {
            hasReplyToken = !trimmed.isEmpty
        } else {
            problem = "Couldn't save the token in the Keychain"
        }
    }

    var server: URL? { PushTopic.server(preferences.pushServer) }

    /// What the phone subscribes to, for the QR code and Copy.
    var subscribeURL: URL? { server.flatMap { PushTopic.url(server: $0, topic: preferences.pushTopic) } }

    /// Sends a test whatever the policy says, so the user can check the phone gets it.
    func sendTest() async {
        testing = true
        defer { testing = false }
        await publish(PushMessage.test)
    }

    // MARK: Events

    /// The hub's queue changed: push new approvals, settle answered ones, and listen for replies
    /// only while one waits.
    func approvalsChanged() {
        guard preferences.pushEnabled else { return }
        // Questions need typed or picked answers, which buttons can't give; they go as Needs you.
        let current = hub.approvals.filter { $0.prompt != .question }
        let ids = Set(current.map(\.id))
        for (id, entry) in tracked where !ids.contains(id) {
            tracked[id] = nil
            replies.remove(id)
            let byPhone = answeredByPhone.remove(id) != nil
            if let sequenceID = entry.sequenceID, !byPhone {
                let timedOut = Date.now.timeIntervalSince(entry.arrived) >= Double(preferences.approvalTimeout - 15)
                Task { await publish(PushMessage.settled(sequenceID: sequenceID, answered: !timedOut)) }
            }
        }
        for approval in current where tracked[approval.id] == nil { tracked[approval.id] = (.now, nil) }
        for approval in current where tracked[approval.id]?.sequenceID == nil { push(approval) }
        replies.removeExpired(now: .now)
        if replies.isEmpty { stopListening() } else { startListening() }
        watchForAway(waiting: current.contains { tracked[$0.id]?.sequenceID == nil })
    }

    func moment(_ moment: AgentMoment) {
        guard preferences.pushEnabled, policy.allow(moment.kind, key: moment.key, away: isAway, now: .now) else {
            return
        }
        let notice = moment.notice(hidden: hub.detailsHidden, includeDetails: preferences.pushDetails)
        Task { await publish(notice) }
    }

    private func push(_ approval: AgentApproval) {
        guard let server, let replyURL = PushTopic.url(server: server, topic: preferences.pushReplyTopic),
            policy.allow(.approval, key: approval.id.uuidString, away: isAway, now: .now)
        else { return }
        let nonce = PushTopic.random()
        let sequenceID = PushTopic.random()
        replies.register(
            nonce: nonce, for: approval.id, expires: .now.addingTimeInterval(Double(preferences.approvalTimeout)))
        tracked[approval.id]?.sequenceID = sequenceID
        let request = PushMessage.Approval(
            agent: approval.source.displayName, tool: approval.tool, prompt: approval.prompt,
            summary: approval.summary, project: approval.project)
        let notice = PushMessage.approval(
            request,
            // Only the reply token: the buttons are stored on the server and the phone with the
            // notification, so the access token never goes in them.
            reply: PushMessage.Reply(url: replyURL, nonce: nonce, token: KeychainStore.read(.ntfyReplyToken)),
            hidden: hub.detailsHidden, includeDetails: preferences.pushDetails, sequenceID: sequenceID)
        Task { await publish(notice) }
    }

    /// Locked, or no input for the idle minutes. Public APIs only: the lock notifications and
    /// the HID idle time.
    private var isAway: Bool {
        PushPolicy.isAway(locked: locked, idleSeconds: Self.idleSeconds, idleMinutes: preferences.pushIdleMinutes)
    }

    private static var idleSeconds: TimeInterval {
        // kCGAnyInputEventType: any keyboard, mouse or trackpad input.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    /// An approval that arrived while the user was here goes out once they've been gone long enough.
    private func watchForAway(waiting: Bool) {
        guard waiting, policy.mode == .away, policy.kinds.contains(.approval) else {
            awayTask?.cancel()
            awayTask = nil
            return
        }
        guard awayTask == nil else { return }
        // One check per wake; `approvalsChanged` schedules the next while something still waits.
        awayTask = Task { [weak self, awayCheck] in
            try? await Task.sleep(for: awayCheck)
            guard let self, !Task.isCancelled else { return }
            self.awayTask = nil
            self.approvalsChanged()
        }
    }

    // MARK: Network

    private func publish(_ notice: PushNotice) async {
        guard preferences.pushEnabled, let server, PushTopic.isValid(preferences.pushTopic),
            let body = try? PushMessage.json(topic: preferences.pushTopic, notice: notice)
        else {
            problem = "Check the server address"
            return
        }
        var request = URLRequest(url: server, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                problem = nil
            } else {
                problem = Self.describe(status: status)
                log.error("push publish failed: status \(status, privacy: .public)")
            }
        } catch {
            problem = "Couldn't reach the server"
            log.error("push publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func authorize(_ request: inout URLRequest) {
        if let token = KeychainStore.read(.ntfyToken) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func describe(status: Int) -> String {
        switch status {
        case 401, 403: "The server refused: check the access token"
        case 413: "The message was too large"
        case 429: "The server's rate limit was reached"
        default: "The server answered \(status)"
        }
    }

    private func startListening() {
        guard streamTask == nil, let server,
            let stream = PushTopic.streamURL(server: server, topic: preferences.pushReplyTopic)
        else { return }
        // Replies posted while reconnecting are still read: the stream starts a little before the
        // oldest pending approval, and used nonces are ignored.
        let since = Int((tracked.values.map(\.arrived).min() ?? .now).timeIntervalSince1970) - 5
        var components = URLComponents(url: stream, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "since", value: String(since))]
        guard let url = components?.url else { return }
        streamTask = Task { [weak self] in
            var delay = 1.0
            while !Task.isCancelled {
                guard let self else { return }
                // Back off on failures, so a dead network or a refusing server isn't hit every second.
                if await self.listen(url) { delay = 1 }
                guard !Task.isCancelled, !self.replies.isEmpty else { break }
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, self.maximumBackoff)
            }
            self?.streamTask = nil
            self?.listening = false
        }
    }

    /// Reads the stream until it closes or nothing waits. True only when the server accepted the
    /// connection.
    private func listen(_ url: URL) async -> Bool {
        var connected = false
        // ntfy sends a keepalive every 45 s by default, so a minute and a half of silence is a
        // dead connection.
        var request = URLRequest(url: url, timeoutInterval: 90)
        authorize(&request)
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                problem = Self.describe(status: status)
                log.error("push stream refused: status \(status, privacy: .public)")
                return false
            }
            listening = true
            connected = true
            for try await line in bytes.lines {
                received(line)
                if replies.isEmpty || Task.isCancelled { break }
            }
        } catch {
            if !Task.isCancelled { log.notice("push stream closed: \(error.localizedDescription, privacy: .public)") }
        }
        listening = false
        return connected
    }

    private func received(_ line: String) {
        guard let reply = replies.resolve(line: line, now: .now) else { return }
        answeredByPhone.insert(reply.id)
        log.info("approval answered from the phone")
        hub.answer(reply.id, allow: reply.decision == .allow)
    }

    private func stopListening() {
        streamTask?.cancel()
        streamTask = nil
        listening = false
    }
}

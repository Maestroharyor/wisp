import AppKit
import OSLog
import Observation
import WispCore

/// Watches the system notification store and the Focus state (both need Full Disk
/// Access), and sends replies through Messages, WhatsApp Web or Telegram Web.
@MainActor
@Observable
final class NotificationMonitor {
    private(set) var hasAccess = Permission.hasFullDiskAccess
    /// Apps seen sending notifications, for the per-app list in Settings.
    private(set) var seenApps: [String: String] = [:]

    @ObservationIgnored var onNotification: (NotificationItem) -> Void = { _ in }
    @ObservationIgnored var onFocus: (FocusModeState) -> Void = { _ in }
    @ObservationIgnored let avatars = ContactAvatars()

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var database: NotificationDatabase?
    @ObservationIgnored private var feed = NotificationFeed(ownBundleID: Bundle.main.bundleIdentifier ?? "")
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var bulletinObserver: NSObjectProtocol?
    @ObservationIgnored private var lastFocus: FocusModeState?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private lazy var whatsApp = WebChatSession(channel: .whatsApp)
    @ObservationIgnored private lazy var telegram = WebChatSession(channel: .telegram)
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "notifications")

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // Notification Center posts this when a banner is added; poll right away.
        bulletinObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.notificationcenterui.bulletin_added"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollNotifications() }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let bulletinObserver { DistributedNotificationCenter.default().removeObserver(bulletinObserver) }
        bulletinObserver = nil
    }

    func canReply(to item: NotificationItem) -> Bool {
        switch item.channel {
        case .iMessage: true
        case .whatsApp: preferences.whatsAppReplies
        case .telegram: preferences.telegramReplies
        case nil: false
        }
    }

    func reply(to item: NotificationItem, text: String) async -> Bool {
        switch item.channel {
        case .iMessage: MessagesReply.send(text, title: item.title, body: item.body)
        case .whatsApp: await whatsApp.send(text, to: item.title)
        case .telegram: await telegram.send(text, to: item.title)
        case nil: false
        }
    }

    func showLogin(for channel: ReplyChannel) {
        switch channel {
        case .whatsApp: whatsApp.showLogin()
        case .telegram: telegram.showLogin()
        case .iMessage: break
        }
    }

    func openApp(for item: NotificationItem) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.appID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func tick() {
        ticks += 1
        // Re-check access occasionally; it changes only when the user flips it in Settings.
        if ticks % 5 == 1 {
            hasAccess = Permission.hasFullDiskAccess
            if !hasAccess { database = nil }
        }
        // bulletin_added triggers a poll as banners arrive; this is only the fallback.
        if ticks % 3 == 0 { pollNotifications() }
        if ticks % 2 == 0 { pollFocus() }
    }

    private func pollNotifications() {
        guard preferences.notificationsEnabled, hasAccess else { return }
        if database == nil { database = NotificationDatabase() }
        guard let database else { return }
        do {
            let baseline = feed.cursor == nil ? try database.latestRecordID() : nil
            let records = try database.records(after: feed.cursor ?? baseline ?? 0)
            feed.blockedApps = Set(preferences.blockedNotificationApps)
            for record in feed.ingest(records, baseline: baseline) {
                let name = appName(for: record.appID)
                seenApps[record.appID] = name
                onNotification(
                    NotificationItem(
                        id: record.recID, appID: record.appID, appName: name, title: record.title,
                        subtitle: record.subtitle, body: record.body, date: record.date,
                        channel: ReplyRouting.channel(for: record.appID)))
            }
        } catch {
            log.error("notification poll failed: \(String(describing: error), privacy: .public)")
            self.database = nil
        }
    }

    private func pollFocus() {
        guard preferences.focusActivity, hasAccess else { return }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
        guard let assertions = try? Data(contentsOf: folder.appendingPathComponent("Assertions.json")),
            let state = FocusModeState.parse(
                assertions: assertions,
                modes: try? Data(contentsOf: folder.appendingPathComponent("ModeConfigurations.json")))
        else { return }
        defer { lastFocus = state }
        // The first reading is the starting point, not a change.
        guard let lastFocus, lastFocus.isOn != state.isOn || lastFocus.name != state.name else { return }
        onFocus(state)
    }

    private func appName(for bundleID: String) -> String {
        if let known = seenApps[bundleID] { return known }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

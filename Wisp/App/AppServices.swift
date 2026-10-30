import AppKit
import SwiftUI
import WispCore

/// Long-lived stores and monitors shared by every notch and window.
@MainActor
final class AppServices {
    let preferences: Preferences
    let activities = ActivityCenter()
    let nowPlaying = NowPlayingMonitor()
    let tray = TrayStore()
    let timers = TimerStore()
    let battery = BatteryMonitor()
    let stats = SystemStatsStore()
    let calendar = CalendarStore()
    let weather = WeatherStore()
    let notes = NotesStore()
    let shortcuts = ShortcutsRunner()
    let camera = CameraMirror()
    let agents = AgentHub()
    let context: ContextEngine
    let quickActions: QuickActions
    let clipboard: ClipboardStore
    let systemHUD: SystemHUD
    let notifications: NotificationMonitor
    let lyrics: LyricsStore
    let microphone = MicrophoneMonitor()
    /// Calls already offered with a Join card, so each is offered once.
    @ObservationIgnored private var offeredMeetings: Set<String> = []
    @ObservationIgnored private var meetingTask: Task<Void, Never>?
    /// The notification being replied to; new notifications wait until it is done.
    private(set) var replyingTo: NotificationItem?

    private(set) lazy var transform = TransformPanelController(services: self)
    private(set) lazy var pocket = QuickPocket(services: self)
    private(set) lazy var miniPlayer = MiniPlayerController(services: self)
    private(set) lazy var lockScreenPlayer = LockScreenPlayer(services: self)

    func openTransform(_ urls: [URL]) {
        pocket.hide()
        transform.open(urls)
    }

    /// Set by the app delegate once the windows exist.
    var openSettings: @MainActor () -> Void = {}
    var openClipboard: @MainActor () -> Void = {}
    var openSetup: @MainActor () -> Void = {}

    init(preferences: Preferences) {
        self.preferences = preferences
        clipboard = ClipboardStore(preferences: preferences)
        systemHUD = SystemHUD(preferences: preferences, activities: activities)
        notifications = NotificationMonitor(preferences: preferences)
        lyrics = LyricsStore(preferences: preferences)
        quickActions = QuickActions(preferences: preferences, shortcuts: shortcuts)
        context = ContextEngine(preferences: preferences)
    }

    /// Glow and glass tint: the playing album's colour when allowed, otherwise Wisp's violet.
    var accent: Color {
        // Without artwork the album tint is a plain white fallback, which turns the glow grey.
        if preferences.adaptiveAccent, nowPlaying.info?.isPlaying == true, nowPlaying.artwork != nil {
            return nowPlaying.tint
        }
        return .wispViolet
    }

    /// Set by the notch coordinator: the page closed shelves open on next.
    var restingPage: @MainActor (ShelfPage) -> Void = { _ in }

    private func applyProfile(_ profile: Profile, swapsHome: Bool) {
        guard profile.name != preferences.activeProfile || swapsHome else { return }
        if swapsHome { preferences.apply(profile) } else { preferences.applySurface(profile) }
        restingPage(ShelfPage(name: profile.defaultPage))
        activities.post(.notice(symbol: "rectangle.stack.fill", text: profile.name), slot: .notice, duration: 1.8)
    }

    /// Set by the notch coordinator: closes every open shelf.
    var closeShelves: @MainActor () -> Void = {}

    /// Working shows until the turn ends; Done and Needs you show briefly.
    private func agentStatusChanged(_ status: AgentStatus?) {
        let needsUser = agents.sessions.anyNeedsUser
        context.update { $0.agentWaiting = needsUser }
        guard let status else {
            activities.remove(.agent)
            return
        }
        switch status.state {
        case .running: activities.post(.agent(status), slot: .agent, duration: nil)
        case .finished, .waiting: activities.post(.agent(status), slot: .agent, duration: 4)
        case .idle: activities.remove(.agent)
        case .needsApproval: break
        }
    }

    /// How long a notification card stays when untouched.
    private let notificationDuration: TimeInterval = 6

    /// Keeps the card on screen while the user types a reply.
    func beginReply(to item: NotificationItem) {
        replyingTo = item
        activities.post(.notification(item), slot: .notification, duration: nil)
    }

    func endReply(sentText: String?) {
        replyingTo = nil
        activities.remove(.notification)
        if let sentText {
            activities.post(.sent(text: sentText), slot: .notice, duration: 2.5)
        }
    }

    func start() {
        nowPlaying.onChange = { [weak self] info in self?.mediaChanged(info) }
        nowPlaying.start()

        lockScreenPlayer.start()
        microphone.onChange = { [weak self] _ in self?.updateMeeting() }
        microphone.start()
        // Calendar-driven: look for calls about to start twice a minute.
        meetingTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.offerUpcomingMeeting()
                try? await Task.sleep(for: .seconds(30))
            }
        }

        battery.onEvent = { [weak self] event, state in self?.batteryEvent(event, state) }
        battery.start()

        timers.onActivity = { [weak self] activity in
            if let activity {
                self?.activities.post(activity, slot: .timer, duration: nil)
            } else {
                self?.activities.remove(.timer)
            }
        }
        timers.onFinished = { [weak self] label in
            self?.activities.post(.timerDone(label: label), slot: .notice, duration: 5)
        }

        let notice: (String, String) -> Void = { [weak self] symbol, text in
            self?.activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
        }
        shortcuts.onNotice = notice
        quickActions.onNotice = notice
        quickActions.closeShelves = { [weak self] in self?.closeShelves() }

        agents.onStatus = { [weak self] status in self?.agentStatusChanged(status) }
        agents.onApproval = { [weak self] approval in
            if let approval {
                self?.activities.post(.agentApproval(approval), slot: .agentApproval, duration: nil)
            } else {
                self?.activities.remove(.agentApproval)
            }
        }
        agents.onNewRequest = { [weak self] in
            guard self?.preferences.approvalSound == true else { return }
            NSSound(named: "Tink")?.play()
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        agents.onNotice = { [weak self] text in
            self?.activities.post(.notice(symbol: "checkmark.shield.fill", text: text), slot: .notice, duration: 2)
        }
        agents.start()

        context.onSwitch = { [weak self] profile, swapsHome in self?.applyProfile(profile, swapsHome: swapsHome) }
        context.start()

        tray.onAdd = { [weak self] count in self?.activities.post(.tray(count: count), slot: .tray, duration: 2) }
        tray.onNotice = { [weak self] symbol, text in
            self?.activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
        }

        notifications.onNotification = { [weak self] item in self?.showNotification(item) }
        notifications.onFocus = { [weak self] state in
            self?.context.update { $0.focus = state.isOn ? state.name : nil }
            self?.activities.post(.focus(state), slot: .focus, duration: 2.2)
        }
        notifications.start()

        clipboard.start()
        systemHUD.start()
    }

    func stop() {
        lockScreenPlayer.stop()
        microphone.stop()
        meetingTask?.cancel()
        nowPlaying.stop()
        battery.stop()
        clipboard.stop()
        systemHUD.stop()
        notifications.stop()
    }

    private var meetingEvents: [MeetingEvent] {
        calendar.events.map {
            MeetingEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay, link: $0.link)
        }
    }

    /// The meeting pill while the microphone is live, named after the event in progress.
    private func updateMeeting() {
        guard preferences.meetingActivity, microphone.inUse else {
            activities.remove(.meeting)
            return
        }
        calendar.refresh()
        let title = Meetings.current(meetingEvents, now: .now)?.title ?? "On a call"
        activities.post(
            .meeting(MeetingStatus(title: title, started: microphone.since ?? .now)), slot: .meeting, duration: nil)
    }

    private func offerUpcomingMeeting() {
        guard preferences.meetingActivity, calendar.access == .fullAccess else { return }
        calendar.refresh()
        guard let next = Meetings.upcoming(meetingEvents, now: .now, within: 120), let link = next.link,
            !offeredMeetings.contains(next.id)
        else { return }
        offeredMeetings.insert(next.id)
        activities.post(
            .meetingSoon(MeetingInvite(id: next.id, title: next.title, link: link, start: next.start)),
            slot: .meetingSoon, duration: 90)
    }

    private func showNotification(_ item: NotificationItem) {
        guard replyingTo == nil else { return }
        activities.post(.notification(item), slot: .notification, duration: notificationDuration)
        if preferences.hideSystemBanners { BannerSuppressor.closeBanners() }
    }

    private func mediaChanged(_ info: NowPlayingInfo?) {
        context.update { $0.mediaPlaying = info?.isPlaying ?? false }
        if preferences.mediaActivity, info?.isPlaying == true {
            activities.post(.media, slot: .media, duration: nil)
        } else {
            activities.remove(.media)
        }
    }

    private func batteryEvent(_ event: BatteryEvent, _ state: BatteryState) {
        guard preferences.batteryHUD else { return }
        switch event {
        case .pluggedIn: activities.post(.charging(percent: state.percent), slot: .battery, duration: 3)
        case .unplugged: activities.post(.unplugged(percent: state.percent), slot: .battery, duration: 2.5)
        case .full: activities.post(.batteryFull, slot: .battery, duration: 4)
        case .low(let percent): activities.post(.lowBattery(percent: percent), slot: .battery, duration: 4)
        }
    }
}

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
    let wallpaper = WallpaperTint()
    let dropActions = DropActionRunner()
    let script = ScriptStore()
    let headphones = HeadphoneMonitor()
    let sounds: SoundPlayer
    let updater = Updater()
    /// Bumped for each confetti burst; the notch watches it.
    private(set) var celebrations = 0
    private(set) var lastCelebration: Date?
    /// Bumped when a timer or an agent run finishes; the breathing glow flashes once.
    private(set) var finishes = 0
    /// The current minute, kept fresh only while something on screen depends on the time.
    private(set) var clock = Date.now
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    /// Each session's last published state. The hub republishes on every hook event, so
    /// the finish sound and confetti fire only when a session first becomes finished.
    @ObservationIgnored private var themeObserver: NSObjectProtocol?
    @ObservationIgnored private var agentStates: [String: AgentSession.State] = [:]
    /// Calls already offered with a Join card, so each is offered once.
    /// Meeting occurrences already offered a Join card, with their start times.
    @ObservationIgnored private var offeredMeetings: [String: Date] = [:]
    @ObservationIgnored private var meetingTask: Task<Void, Never>?
    /// The notification being replied to; new notifications wait until it is done.
    private(set) var replyingTo: NotificationItem?
    /// The newest notification that arrived during a reply, shown when the reply ends.
    private var waitingNotification: NotificationItem?
    /// The default timer length last given to the timer, so only a change resets it.
    private var appliedTimerLength: Double?

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
        sounds = SoundPlayer(preferences: preferences)
    }

    /// Glow and glass tint: the playing album's colour when allowed, otherwise Wisp's violet.
    /// The theme's colours, or the wallpaper's when that is on.
    var palette: ThemePalette {
        let theme = ThemeCatalog.palette(
            for: preferences.theme, custom: ThemePalette(accent: preferences.customAccent, glow: preferences.customGlow)
        )
        guard preferences.wallpaperTint, let sampled = wallpaper.color else { return timeTinted(theme) }
        return timeTinted(ThemePalette(accent: sampled, glow: sampled))
    }

    private func timeTinted(_ palette: ThemePalette) -> ThemePalette {
        let mode = preferences.appearance.timeOfDay
        guard mode != .off else { return palette }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: clock)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ThemePalette(
            accent: TimeOfDayTint.tint(palette.accent, minuteOfDay: minute, mode: mode, isDark: dark),
            glow: TimeOfDayTint.tint(palette.glow, minuteOfDay: minute, mode: mode, isDark: dark))
    }

    /// Confetti from the notch when the look allows it for this moment.
    func celebrate(_ event: CelebrationEvent) {
        guard Celebration.shouldFire(event, look: preferences.appearance) else { return }
        celebrateNow()
    }

    /// A burst whatever the settings say; also how Settings tries confetti out.
    func celebrateNow() {
        celebrations += 1
        lastCelebration = .now
    }

    /// What the idle ears can show right now.
    var earContext: EarContext {
        let look = preferences.appearance
        // Skip a call that started over ten minutes ago, so the ear points at the next one.
        let recent = clock.addingTimeInterval(-10 * 60)
        let meeting =
            [look.leftEar, look.rightEar].contains(.meeting)
            ? calendar.events.first { !$0.isAllDay && $0.start > recent } : nil
        let weatherText = weather.reading.map { "\(Int($0.temperature.rounded()))°" }
        return EarContext(
            now: clock, uses24Hour: Self.uses24Hour, batteryLevel: battery.state?.percent,
            nextMeeting: meeting?.start, weather: weatherText, customText: look.earText)
    }

    private static let uses24Hour =
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")

    /// Without artwork the album tint is a plain white fallback, which turns the glow grey.
    private var albumTintActive: Bool {
        preferences.adaptiveAccent && nowPlaying.info?.isPlaying == true && nowPlaying.artwork != nil
    }

    var accent: Color { albumTintActive ? nowPlaying.tint : Color(rgb: palette.accent) }

    /// The second colour of the shelf glow; the same as the accent for one-colour themes.
    var glow: Color { albumTintActive ? nowPlaying.tint : Color(rgb: palette.glow) }

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
        let changed = agentStates.updateValue(status.state, forKey: status.sessionID) != status.state
        switch status.state {
        case .running: activities.post(.agent(status), slot: .agent, duration: nil)
        case .finished:
            if changed {
                finishes += 1
                sounds.play(.done)
                celebrate(.agentDone(duration: Date.now.timeIntervalSince(status.started)))
            }
            activities.post(.agent(status), slot: .agent, duration: 4)
        case .waiting: activities.post(.agent(status), slot: .agent, duration: 4)
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
        guard replyingTo != nil else { return }
        replyingTo = nil
        activities.remove(.notification)
        if let sentText {
            activities.post(.sent(text: sentText), slot: .notice, duration: 2.5)
        }
        // The card holds one notification at a time, so show the newest that waited, after
        // the "sent" notice has had its moment (a notification would outrank it).
        if let waiting = waitingNotification {
            waitingNotification = nil
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(sentText == nil ? 0 : 2.5))
                self?.showNotification(waiting)
            }
        }
    }

    func start() {
        // Light and Dark switches retint the accent now rather than on the next minute.
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.preferences.appearance.timeOfDay == .lightDark else { return }
                self.clock = .now
            }
        }
        nowPlaying.onChange = { [weak self] info in self?.mediaChanged(info) }
        nowPlaying.looksUpArtwork = { [weak self] in self?.preferences.artworkLookup ?? false }
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
        battery.thresholds = { [weak self] in self?.preferences.batteryThresholds ?? BatteryAlerts.lowThresholds }
        syncPreferenceEffects()
        battery.start()

        timers.onActivity = { [weak self] activity in
            if let activity {
                self?.activities.post(activity, slot: .timer, duration: nil)
            } else {
                self?.activities.remove(.timer)
            }
        }
        timers.onFinished = { [weak self] label, endedFocus in
            self?.sounds.play(.done, fallback: "Glass")
            self?.finishes += 1
            if endedFocus { self?.celebrate(.pomodoroDone) }
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
            self?.sounds.play(.alert, fallback: "Tink")
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        agents.onNotice = { [weak self] text in
            self?.activities.post(.notice(symbol: "checkmark.shield.fill", text: text), slot: .notice, duration: 2)
        }
        agents.start()

        context.onSwitch = { [weak self] profile, swapsHome in self?.applyProfile(profile, swapsHome: swapsHome) }
        context.start()

        tray.onAdd = { [weak self] count in self?.activities.post(.tray(count: count), slot: .tray, duration: 2) }
        headphones.onConnect = { [weak self] device in
            guard let self, self.preferences.deviceActivity else { return }
            self.activities.post(.device(device), slot: .device, duration: 4)
        }
        headphones.start()
        dropActions.onNotice = { [weak self] symbol, text in
            self?.activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
        }
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

    /// Applies settings that drive services: the desktop picture is sampled only while the
    /// wallpaper glow is on, and an idle timer takes a newly chosen default length. Only the
    /// settings are tracked; reading the timer here would undo every +/- in the widget.
    private func syncPreferenceEffects() {
        let (wallpaperOn, timerLength, needsClock) = withObservationTracking {
            let look = preferences.appearance
            let timeEars = [look.leftEar, look.rightEar].contains { [.time, .date, .meeting, .weather].contains($0) }
            return (preferences.wallpaperTint, preferences.defaultTimerSeconds, look.timeOfDay != .off || timeEars)
        } onChange: { [weak self] in
            Task { @MainActor in self?.syncPreferenceEffects() }
        }
        if wallpaperOn { wallpaper.start() } else { wallpaper.stop() }
        if needsClock { startClock() } else { stopClock() }
        if timerLength != appliedTimerLength {
            appliedTimerLength = timerLength
            timers.applyDefaultLength(seconds: timerLength)
        }
    }

    /// Ticks on each minute boundary.
    private func startClock() {
        guard clockTask == nil else { return }
        tickClock()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                let second = Calendar.current.component(.second, from: .now)
                try? await Task.sleep(for: .seconds(60 - second))
                guard !Task.isCancelled else { return }
                self?.tickClock()
            }
        }
    }

    /// The weather and meeting ears read stores that otherwise refresh only for their widgets.
    private func tickClock() {
        clock = .now
        let ears = [preferences.appearance.leftEar, preferences.appearance.rightEar]
        if ears.contains(.weather) { weather.refreshIfStale() }
        if ears.contains(.meeting) { calendar.refreshIfStale() }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    func stop() {
        stopClock()
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
        wallpaper.stop()
        headphones.stop()
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
        calendar.refreshIfStale()
        let title = Meetings.current(meetingEvents, now: .now)?.title ?? "On a call"
        activities.post(
            .meeting(MeetingStatus(title: title, started: microphone.since ?? .now)), slot: .meeting, duration: nil)
    }

    private func offerUpcomingMeeting() {
        guard preferences.meetingActivity else { return }
        calendar.refreshIfStale()
        guard calendar.access == .fullAccess else { return }
        guard let next = Meetings.upcoming(meetingEvents, now: .now, within: 120), let link = next.link,
            offeredMeetings[next.id] == nil
        else { return }
        offeredMeetings = offeredMeetings.filter { $0.value > .now.addingTimeInterval(-86_400) }
        offeredMeetings[next.id] = next.start
        activities.post(
            .meetingSoon(MeetingInvite(id: next.id, title: next.title, link: link, start: next.start)),
            slot: .meetingSoon, duration: 90)
    }

    private func showNotification(_ item: NotificationItem) {
        guard replyingTo == nil else {
            waitingNotification = item
            return
        }
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
        // Confetti is its own setting, so it doesn't depend on the battery pills.
        if case .full = event { celebrate(.batteryFull) }
        guard preferences.batteryHUD else { return }
        switch event {
        case .pluggedIn: activities.post(.charging(percent: state.percent), slot: .battery, duration: 3)
        case .unplugged: activities.post(.unplugged(percent: state.percent), slot: .battery, duration: 2.5)
        case .full: activities.post(.batteryFull, slot: .battery, duration: 4)
        case .low(let percent): activities.post(.lowBattery(percent: percent), slot: .battery, duration: 4)
        }
    }
}

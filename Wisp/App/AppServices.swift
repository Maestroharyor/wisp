import AppKit
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
    let clipboard: ClipboardStore
    let systemHUD: SystemHUD
    let notifications: NotificationMonitor
    /// The notification being replied to; new notifications wait until it is done.
    private(set) var replyingTo: NotificationItem?

    private(set) lazy var transform = TransformPanelController(services: self)
    private(set) lazy var basket = QuickBasket(services: self)

    func openTransform(_ urls: [URL]) {
        basket.hide()
        transform.open(urls)
    }

    /// Set by the app delegate once the windows exist.
    var openSettings: @MainActor () -> Void = {}
    var openClipboard: @MainActor () -> Void = {}

    init(preferences: Preferences) {
        self.preferences = preferences
        clipboard = ClipboardStore(preferences: preferences)
        systemHUD = SystemHUD(preferences: preferences, activities: activities)
        notifications = NotificationMonitor(preferences: preferences)
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

        tray.onAdd = { [weak self] count in self?.activities.post(.tray(count: count), slot: .tray, duration: 2) }
        tray.onNotice = { [weak self] symbol, text in
            self?.activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
        }

        notifications.onNotification = { [weak self] item in self?.showNotification(item) }
        notifications.onFocus = { [weak self] state in
            self?.activities.post(.focus(state), slot: .focus, duration: 2.2)
        }
        notifications.start()

        clipboard.start()
        systemHUD.start()
    }

    func stop() {
        nowPlaying.stop()
        battery.stop()
        clipboard.stop()
        systemHUD.stop()
        notifications.stop()
    }

    private func showNotification(_ item: NotificationItem) {
        guard replyingTo == nil else { return }
        activities.post(.notification(item), slot: .notification, duration: notificationDuration)
        if preferences.hideSystemBanners { BannerSuppressor.closeBanners() }
    }

    private func mediaChanged(_ info: NowPlayingInfo?) {
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

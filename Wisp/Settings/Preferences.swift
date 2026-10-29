import Foundation
import Observation
import WispCore

/// How the shelf opens from the closed notch.
enum OpenTrigger: String, CaseIterable, Identifiable {
    case hover
    case click

    var id: Self { self }
    var title: String { self == .hover ? "Hover" : "Click" }
}

/// Overall speed of the notch morph.
enum AnimationSpeed: String, CaseIterable, Identifiable {
    case relaxed
    case standard
    case fast

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

/// Shape on displays without a camera housing.
enum ExternalStyle: String, CaseIterable, Identifiable {
    case notch
    case island

    var id: Self { self }
    var title: String { self == .notch ? "Notch" : "Floating island" }
}

/// When the floating drop basket appears during a file drag.
enum BasketTrigger: String, CaseIterable, Identifiable {
    case shake
    case dragStart
    case off

    var id: Self { self }
    var title: String {
        switch self {
        case .shake: "When I shake a file"
        case .dragStart: "As soon as I drag a file"
        case .off: "Never"
        }
    }
}

/// Translucent fade at the bottom edge of the open surface.
enum GlassEdge: String, CaseIterable, Identifiable {
    case off
    case subtle
    case strong

    var id: Self { self }
    var title: String { rawValue.capitalized }
    /// Opacity of black left at the very bottom edge.
    var bottomOpacity: Double {
        switch self {
        case .off: 1
        case .subtle: 0.72
        case .strong: 0.45
        }
    }
}

/// Widgets that can sit on the Home page, in user order.
enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    case nowPlaying
    case calendar
    case timer
    case pomodoro
    case battery
    case systemStats
    case weather
    case notes

    var id: Self { self }

    var title: String {
        switch self {
        case .nowPlaying: "Now Playing"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .pomodoro: "Pomodoro"
        case .battery: "Battery"
        case .systemStats: "System Stats"
        case .weather: "Weather"
        case .notes: "Notes"
        }
    }

    /// Widgets whose content needs the taller row.
    var needsTallRow: Bool { self == .nowPlaying }

    /// Size when first added to Home.
    var defaultSize: WidgetSize {
        switch self {
        case .nowPlaying: .large
        case .calendar, .systemStats, .notes: .medium
        case .timer, .pomodoro, .battery, .weather: .small
        }
    }

    var symbol: String {
        switch self {
        case .nowPlaying: "music.note"
        case .calendar: "calendar"
        case .timer: "timer"
        case .pomodoro: "brain.head.profile"
        case .battery: "battery.75percent"
        case .systemStats: "cpu"
        case .weather: "cloud.sun.fill"
        case .notes: "note.text"
        }
    }
}

/// User settings, persisted in UserDefaults. Observed by the UI and by services.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let hotkey = "hotkey"
        static let quickPressTogglesCapsLock = "quickPressTogglesCapsLock"
        static let showOnExternalDisplays = "showOnExternalDisplays"
        static let hoverDelay = "hoverDelay"
        static let openTrigger = "openTrigger"
        static let animationSpeed = "animationSpeed"
        static let externalStyle = "externalStyle"
        static let glassEdge = "glassEdge"
        static let homeWidgets = "homeWidgets"
        static let homeLayout = "homeLayout"
        static let enabledWidgets = "enabledWidgets"
        static let volumeHUD = "volumeHUD"
        static let brightnessHUD = "brightnessHUD"
        static let batteryHUD = "batteryHUD"
        static let capsLockHUD = "capsLockHUD"
        static let mediaActivity = "mediaActivity"
        static let activityDisplay = "activityDisplay"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardLimit = "clipboardLimit"
        static let notificationsEnabled = "notificationsEnabled"
        static let hideSystemBanners = "hideSystemBanners"
        static let blockedNotificationApps = "blockedNotificationApps"
        static let whatsAppReplies = "whatsAppReplies"
        static let telegramReplies = "telegramReplies"
        static let focusActivity = "focusActivity"
        static let basketTrigger = "basketTrigger"
        static let scrubberSounds = "scrubberSounds"
        static let widgetGridOrder = "widgetGridOrder"
        static let widgetGridRows = "widgetGridRows"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Toggles the shelf. Hyper (Caps Lock) shortcuts need Accessibility access.
    var hotkey: Hotkey { didSet { defaults.set(hotkey.stringValue, forKey: Key.hotkey) } }

    /// Pressing Caps Lock on its own still toggles Caps Lock while it doubles as Hyper.
    var quickPressTogglesCapsLock: Bool {
        didSet { defaults.set(quickPressTogglesCapsLock, forKey: Key.quickPressTogglesCapsLock) }
    }

    /// Show the shelf on displays without a notch.
    var showOnExternalDisplays: Bool {
        didSet { defaults.set(showOnExternalDisplays, forKey: Key.showOnExternalDisplays) }
    }

    /// Seconds the pointer must rest on the notch before it opens.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }

    var openTrigger: OpenTrigger { didSet { defaults.set(openTrigger.rawValue, forKey: Key.openTrigger) } }

    var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: Key.animationSpeed) }
    }

    var externalStyle: ExternalStyle {
        didSet { defaults.set(externalStyle.rawValue, forKey: Key.externalStyle) }
    }

    var glassEdge: GlassEdge { didSet { defaults.set(glassEdge.rawValue, forKey: Key.glassEdge) } }

    /// Up to four widgets on Home, with sizes and order.
    var homeLayout: HomeLayout {
        didSet { defaults.set(try? JSONEncoder().encode(homeLayout), forKey: Key.homeLayout) }
    }

    /// Every switched-on widget; the Widgets page shows them all.
    var enabledWidgets: [WidgetKind] {
        didSet { defaults.set(enabledWidgets.map(\.rawValue), forKey: Key.enabledWidgets) }
    }

    /// Order of the Widgets page grid, separate from Home. Read through `gridWidgets`.
    private var widgetGridOrder: [WidgetKind] {
        didSet { defaults.set(widgetGridOrder.map(\.rawValue), forKey: Key.widgetGridOrder) }
    }

    /// Rows in the Widgets page grid: 1 or 2.
    var widgetGridRows: Int {
        didSet { defaults.set(WidgetGrid.clampedRows(widgetGridRows), forKey: Key.widgetGridRows) }
    }

    /// Switched-on widgets in the grid's saved order.
    var gridWidgets: [WidgetKind] {
        WidgetGrid.merge(order: widgetGridOrder.map(\.rawValue), enabled: enabledWidgets.map(\.rawValue))
            .compactMap(WidgetKind.init(rawValue:))
    }

    func moveGridWidget(_ kind: WidgetKind, before target: WidgetKind) {
        widgetGridOrder = WidgetGrid.move(gridWidgets.map(\.rawValue), item: kind.rawValue, before: target.rawValue)
            .compactMap(WidgetKind.init(rawValue:))
    }

    /// Home widgets in order, resolved to kinds.
    var homeWidgets: [WidgetKind] { homeLayout.ids.compactMap(WidgetKind.init(rawValue:)) }

    func size(of kind: WidgetKind) -> WidgetSize {
        homeLayout.slots.first { $0.id == kind.rawValue }?.size ?? kind.defaultSize
    }

    /// Switches a widget on and puts it on Home when there is room.
    func enable(_ kind: WidgetKind) {
        if !enabledWidgets.contains(kind) { enabledWidgets.append(kind) }
        homeLayout.add(kind.rawValue, size: kind.defaultSize)
    }

    /// Switches a widget off everywhere.
    func disable(_ kind: WidgetKind) {
        enabledWidgets.removeAll { $0 == kind }
        homeLayout.remove(kind.rawValue)
    }

    var volumeHUD: Bool { didSet { defaults.set(volumeHUD, forKey: Key.volumeHUD) } }
    var brightnessHUD: Bool { didSet { defaults.set(brightnessHUD, forKey: Key.brightnessHUD) } }
    var batteryHUD: Bool { didSet { defaults.set(batteryHUD, forKey: Key.batteryHUD) } }
    var capsLockHUD: Bool { didSet { defaults.set(capsLockHUD, forKey: Key.capsLockHUD) } }
    var mediaActivity: Bool { didSet { defaults.set(mediaActivity, forKey: Key.mediaActivity) } }

    /// Where live activities (Now Playing, HUDs, timers) appear.
    var activityDisplay: ActivityDisplayTarget {
        didSet { defaults.set(activityDisplay.rawValue, forKey: Key.activityDisplay) }
    }

    var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled) } }
    var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: Key.clipboardLimit) } }

    /// Show notifications in the notch (needs Full Disk Access).
    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }
    /// Close the macOS banner when Wisp shows the notification (needs Accessibility).
    var hideSystemBanners: Bool { didSet { defaults.set(hideSystemBanners, forKey: Key.hideSystemBanners) } }
    var blockedNotificationApps: [String] {
        didSet { defaults.set(blockedNotificationApps, forKey: Key.blockedNotificationApps) }
    }
    var whatsAppReplies: Bool { didSet { defaults.set(whatsAppReplies, forKey: Key.whatsAppReplies) } }
    var telegramReplies: Bool { didSet { defaults.set(telegramReplies, forKey: Key.telegramReplies) } }
    var focusActivity: Bool { didSet { defaults.set(focusActivity, forKey: Key.focusActivity) } }
    /// Tick sounds and haptics when scrubbing the Pomodoro ruler.
    var scrubberSounds: Bool { didSet { defaults.set(scrubberSounds, forKey: Key.scrubberSounds) } }
    var basketTrigger: BasketTrigger { didSet { defaults.set(basketTrigger.rawValue, forKey: Key.basketTrigger) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.hotkey: Hotkey.hyperSpace.stringValue,
            Key.quickPressTogglesCapsLock: true,
            Key.showOnExternalDisplays: true,
            Key.hoverDelay: 0.15,
            // Matches the reference app: hover peeks, a click opens.
            Key.openTrigger: OpenTrigger.click.rawValue,
            Key.animationSpeed: AnimationSpeed.standard.rawValue,
            Key.externalStyle: ExternalStyle.notch.rawValue,
            Key.glassEdge: GlassEdge.subtle.rawValue,
            Key.volumeHUD: true,
            Key.brightnessHUD: true,
            Key.batteryHUD: true,
            Key.capsLockHUD: true,
            Key.mediaActivity: true,
            Key.activityDisplay: ActivityDisplayTarget.pointer.rawValue,
            Key.clipboardEnabled: true,
            Key.clipboardLimit: 200,
            Key.notificationsEnabled: true,
            Key.hideSystemBanners: true,
            Key.whatsAppReplies: false,
            Key.telegramReplies: false,
            Key.focusActivity: true,
            Key.basketTrigger: BasketTrigger.shake.rawValue,
            Key.scrubberSounds: true,
            Key.widgetGridRows: 2,
        ])
        hotkey = defaults.string(forKey: Key.hotkey).flatMap(Hotkey.init(string:)) ?? .hyperSpace
        quickPressTogglesCapsLock = defaults.bool(forKey: Key.quickPressTogglesCapsLock)
        showOnExternalDisplays = defaults.bool(forKey: Key.showOnExternalDisplays)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        openTrigger = defaults.string(forKey: Key.openTrigger).flatMap(OpenTrigger.init(rawValue:)) ?? .click
        animationSpeed =
            defaults.string(forKey: Key.animationSpeed).flatMap(AnimationSpeed.init(rawValue:)) ?? .standard
        externalStyle = defaults.string(forKey: Key.externalStyle).flatMap(ExternalStyle.init(rawValue:)) ?? .notch
        glassEdge = defaults.string(forKey: Key.glassEdge).flatMap(GlassEdge.init(rawValue:)) ?? .subtle
        // Earlier builds stored a plain list of Home widgets; carry it over once.
        let legacy = (defaults.stringArray(forKey: Key.homeWidgets) ?? []).compactMap(WidgetKind.init(rawValue:))
        let starting = legacy.isEmpty ? [WidgetKind.nowPlaying, .calendar] : legacy
        homeLayout =
            defaults.data(forKey: Key.homeLayout).flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) }
            ?? HomeLayout(slots: starting.map { HomeLayout.Slot(id: $0.rawValue, size: $0.defaultSize) })
        enabledWidgets =
            defaults.stringArray(forKey: Key.enabledWidgets)?.compactMap(WidgetKind.init(rawValue:)) ?? starting
        volumeHUD = defaults.bool(forKey: Key.volumeHUD)
        brightnessHUD = defaults.bool(forKey: Key.brightnessHUD)
        batteryHUD = defaults.bool(forKey: Key.batteryHUD)
        capsLockHUD = defaults.bool(forKey: Key.capsLockHUD)
        mediaActivity = defaults.bool(forKey: Key.mediaActivity)
        activityDisplay =
            defaults.string(forKey: Key.activityDisplay).flatMap(ActivityDisplayTarget.init(rawValue:)) ?? .pointer
        clipboardEnabled = defaults.bool(forKey: Key.clipboardEnabled)
        clipboardLimit = max(defaults.integer(forKey: Key.clipboardLimit), 20)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        hideSystemBanners = defaults.bool(forKey: Key.hideSystemBanners)
        blockedNotificationApps = defaults.stringArray(forKey: Key.blockedNotificationApps) ?? []
        whatsAppReplies = defaults.bool(forKey: Key.whatsAppReplies)
        telegramReplies = defaults.bool(forKey: Key.telegramReplies)
        focusActivity = defaults.bool(forKey: Key.focusActivity)
        scrubberSounds = defaults.bool(forKey: Key.scrubberSounds)
        widgetGridOrder =
            (defaults.stringArray(forKey: Key.widgetGridOrder) ?? []).compactMap(WidgetKind.init(rawValue:))
        widgetGridRows = WidgetGrid.clampedRows(defaults.integer(forKey: Key.widgetGridRows))
        basketTrigger = defaults.string(forKey: Key.basketTrigger).flatMap(BasketTrigger.init(rawValue:)) ?? .shake
    }
}

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

/// When the floating drop pocket appears during a file drag.
enum PocketTrigger: String, CaseIterable, Identifiable {
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

/// What the open surface is made of. The closed notch is always black so it
/// blends with the camera housing.
enum SurfaceStyle: String, CaseIterable, Identifiable {
    case black
    case glass
    case tinted

    var id: Self { self }
    var title: String { rawValue.capitalized }
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
    case quickToggles
    case shortcuts
    case clipboard
    case mirror
    case dayProgress
    case worldClocks
    case agents

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
        case .quickToggles: "Quick Toggles"
        case .shortcuts: "Shortcuts"
        case .clipboard: "Clipboard"
        case .mirror: "Mirror"
        case .dayProgress: "Day Progress"
        case .worldClocks: "World Clocks"
        case .agents: "Agents"
        }
    }

    /// Widgets whose content needs the taller row.
    var needsTallRow: Bool { self == .nowPlaying }

    /// Size when first added to Home.
    var defaultSize: WidgetSize {
        switch self {
        case .nowPlaying: .large
        case .calendar, .systemStats, .notes, .quickToggles, .shortcuts, .clipboard, .dayProgress, .agents: .medium
        case .timer, .pomodoro, .battery, .weather, .mirror, .worldClocks: .small
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
        case .quickToggles: "switch.2"
        case .shortcuts: "square.stack.3d.up.fill"
        case .clipboard: "doc.on.clipboard"
        case .mirror: "person.crop.square"
        case .dayProgress: "sun.horizon.fill"
        case .worldClocks: "globe"
        case .agents: "sparkle"
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
        static let shelfAutoCloses = "shelfAutoCloses"
        static let animationSpeed = "animationSpeed"
        static let externalStyle = "externalStyle"
        static let glassEdge = "glassEdge"
        static let surfaceStyle = "surfaceStyle"
        static let lastSettingsPane = "lastSettingsPane"
        static let onboarded = "onboarded"
        static let profiles = "profiles"
        static let activeProfile = "activeProfile"
        static let homeProfile = "homeProfile"
        static let contextRules = "contextRules"
        static let contextAware = "contextAware"
        static let adaptiveAccent = "adaptiveAccent"
        static let homeWidgets = "homeWidgets"
        static let homeLayout = "homeLayout"
        static let enabledWidgets = "enabledWidgets"
        static let volumeHUD = "volumeHUD"
        static let brightnessHUD = "brightnessHUD"
        static let batteryHUD = "batteryHUD"
        static let capsLockHUD = "capsLockHUD"
        static let mediaActivity = "mediaActivity"
        static let approvalSound = "approvalSound"
        static let lyrics = "lyrics"
        static let artworkLookup = "artworkLookup"
        static let meetingActivity = "meetingActivity"
        static let lockScreenPlayer = "lockScreenPlayer"
        static let activityBubbles = "activityBubbles"
        static let miniPlayerOrigin = "miniPlayerOrigin"
        static let activityDisplay = "activityDisplay"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardLimit = "clipboardLimit"
        static let notificationsEnabled = "notificationsEnabled"
        static let hideSystemBanners = "hideSystemBanners"
        static let blockedNotificationApps = "blockedNotificationApps"
        static let whatsAppReplies = "whatsAppReplies"
        static let telegramReplies = "telegramReplies"
        static let focusActivity = "focusActivity"
        static let pocketTrigger = "pocketTrigger"
        /// Earlier builds' name for the pocket setting, read once to carry it over.
        static let legacyPocketTrigger = "pocketTrigger"
        static let scrubberSounds = "scrubberSounds"
        static let widgetGridOrder = "widgetGridOrder"
        static let widgetGridRows = "widgetGridRows"
        static let introducedWidgets = "introducedWidgets"
        static let favouriteShortcuts = "favouriteShortcuts"
        static let doNotDisturbShortcut = "doNotDisturbShortcut"
        static let workdayStart = "workdayStart"
        static let workdayEnd = "workdayEnd"
        static let worldClockZones = "worldClockZones"
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
    /// Close the shelf when the pointer leaves it. Off keeps it open until a click
    /// outside, Esc or the shortcut.
    var shelfAutoCloses: Bool { didSet { defaults.set(shelfAutoCloses, forKey: Key.shelfAutoCloses) } }

    var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: Key.animationSpeed) }
    }

    var externalStyle: ExternalStyle {
        didSet { defaults.set(externalStyle.rawValue, forKey: Key.externalStyle) }
    }

    var glassEdge: GlassEdge { didSet { defaults.set(glassEdge.rawValue, forKey: Key.glassEdge) } }
    var surfaceStyle: SurfaceStyle {
        didSet {
            defaults.set(surfaceStyle.rawValue, forKey: Key.surfaceStyle)
            updateActiveProfile { $0.surface = surfaceStyle.rawValue }
        }
    }

    /// The Settings pane shown last, reopened next time.
    /// First-launch setup is done (or was never needed).
    var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: Key.onboarded) }
    }

    var lastSettingsPane: SettingsPaneID {
        didSet { defaults.set(lastSettingsPane.rawValue, forKey: Key.lastSettingsPane) }
    }

    /// Keys that hold the user's content rather than settings; a reset keeps them.
    private static let contentKeys: Set<String> = [
        "trayPaths", "notesText", "webChatStore.whatsApp", "webChatStore.telegram",
    ]

    /// Clears every Wisp setting but keeps content (tray, notes, chat logins). The caller
    /// relaunches Wisp so everything reloads.
    func resetAll() {
        guard let domain = Bundle.main.bundleIdentifier, let stored = defaults.persistentDomain(forName: domain)
        else { return }
        defaults.setPersistentDomain(stored.filter { Self.contentKeys.contains($0.key) }, forName: domain)
    }

    /// Saved setups. Editing Home or the surface updates the active one.
    var profiles: [Profile] {
        didSet { defaults.set(try? JSONEncoder().encode(profiles), forKey: Key.profiles) }
    }

    var activeProfile: String {
        didSet { defaults.set(activeProfile, forKey: Key.activeProfile) }
    }

    /// The profile whose Home widgets are showing. Automatic switches leave Home alone,
    /// so this can differ from `activeProfile`; Home edits are saved into this one.
    private(set) var homeProfile: String {
        didSet { defaults.set(homeProfile, forKey: Key.homeProfile) }
    }

    var contextRules: [ContextRule] {
        didSet { defaults.set(try? JSONEncoder().encode(contextRules), forKey: Key.contextRules) }
    }

    /// Switch profiles automatically from the front app, music, Focus and agents.
    var contextAware: Bool {
        didSet { defaults.set(contextAware, forKey: Key.contextAware) }
    }

    func profile(named name: String) -> Profile? { profiles.first { $0.name == name } }

    /// Makes `profile` active: its Home widgets (switched on if needed) and surface.
    func apply(_ profile: Profile) {
        applySurface(profile)
        homeProfile = profile.name
        for kind in profile.home.ids.compactMap(WidgetKind.init(rawValue:)) { enable(kind) }
        homeLayout = profile.home
    }

    /// Makes `profile` active for its surface (and start page, set by the caller) but
    /// keeps the current Home. Used by automatic switches.
    func applySurface(_ profile: Profile) {
        activeProfile = profile.name
        surfaceStyle = SurfaceStyle(rawValue: profile.surface) ?? surfaceStyle
    }

    /// Saves the current Home and surface as a new profile and makes it active.
    func saveCurrentAsProfile(named name: String) {
        let unique = Profile.uniqueName(name, existing: profiles.map(\.name))
        profiles.append(Profile(name: unique, home: homeLayout, defaultPage: "home", surface: surfaceStyle.rawValue))
        activeProfile = unique
        homeProfile = unique
    }

    func deleteProfile(named name: String) {
        guard name != ContextEngineState.baseProfile else { return }
        profiles.removeAll { $0.name == name }
        if activeProfile == name || homeProfile == name, let base = profile(named: ContextEngineState.baseProfile) {
            apply(base)
        }
    }

    func setDefaultPage(_ page: String, for name: String) {
        guard let index = profiles.firstIndex(where: { $0.name == name }) else { return }
        profiles[index].defaultPage = page
    }

    private func updateActiveProfile(_ change: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.name == activeProfile }) else { return }
        var profile = profiles[index]
        change(&profile)
        if profile != profiles[index] { profiles[index] = profile }
    }
    /// Tint the glow and glass with the playing album's colour. Off by default: the
    /// surface stays Wisp violet, the brand colour.
    var adaptiveAccent: Bool { didSet { defaults.set(adaptiveAccent, forKey: Key.adaptiveAccent) } }

    /// Up to four widgets on Home, with sizes and order.
    var homeLayout: HomeLayout {
        didSet {
            defaults.set(try? JSONEncoder().encode(homeLayout), forKey: Key.homeLayout)
            if let index = profiles.firstIndex(where: { $0.name == homeProfile }), profiles[index].home != homeLayout {
                profiles[index].home = homeLayout
            }
        }
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

    /// Shortcuts shown in the Shortcuts widget, in order.
    var favouriteShortcuts: [String] {
        didSet { defaults.set(favouriteShortcuts, forKey: Key.favouriteShortcuts) }
    }

    /// The Shortcut the Do Not Disturb toggle runs (macOS has no public Focus API).
    var doNotDisturbShortcut: String {
        didSet { defaults.set(doNotDisturbShortcut, forKey: Key.doNotDisturbShortcut) }
    }

    var workdayStart: Int {
        didSet { defaults.set(workdayStart, forKey: Key.workdayStart) }
    }

    var workdayEnd: Int {
        didSet { defaults.set(workdayEnd, forKey: Key.workdayEnd) }
    }

    /// Time zone identifiers for the World Clocks widget, at most three.
    var worldClockZones: [String] {
        didSet { defaults.set(Array(worldClockZones.prefix(3)), forKey: Key.worldClockZones) }
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

    /// Switches on widgets added in an update once, so they show up on the Widgets page
    /// (not on Home, which stays as the user arranged it). The camera mirror stays off.
    private func introduceNewWidgets() {
        // Builds before this key existed shipped the first eight widgets.
        let original: [WidgetKind] = [
            .nowPlaying, .calendar, .timer, .pomodoro, .battery, .systemStats, .weather, .notes,
        ]
        let seen = Set(defaults.stringArray(forKey: Key.introducedWidgets) ?? original.map(\.rawValue))
        for kind in WidgetKind.allCases where !seen.contains(kind.rawValue) && kind != .mirror {
            if !enabledWidgets.contains(kind) { enabledWidgets.append(kind) }
        }
        defaults.set(WidgetKind.allCases.map(\.rawValue), forKey: Key.introducedWidgets)
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
    /// A short sound when an agent asks for permission.
    var approvalSound: Bool { didSet { defaults.set(approvalSound, forKey: Key.approvalSound) } }
    /// Fetch lyrics from LRCLIB for the playing song (sends title, artist and length).
    var lyrics: Bool { didSet { defaults.set(lyrics, forKey: Key.lyrics) } }
    /// Look up album art on iTunes when the player gives none (sends title and artist).
    var artworkLookup: Bool { didSet { defaults.set(artworkLookup, forKey: Key.artworkLookup) } }
    /// The meeting pill while the microphone is in use, and the Join card before calls.
    var meetingActivity: Bool { didSet { defaults.set(meetingActivity, forKey: Key.meetingActivity) } }
    /// Show a player while the screen is locked, where macOS allows it.
    var lockScreenPlayer: Bool { didSet { defaults.set(lockScreenPlayer, forKey: Key.lockScreenPlayer) } }
    /// Extra live activities split off into round bubbles beside the pill.
    var activityBubbles: Bool { didSet { defaults.set(activityBubbles, forKey: Key.activityBubbles) } }
    /// Where the mini player was last left, as "x,y" (its top-left corner).
    var miniPlayerOrigin: String? { didSet { defaults.set(miniPlayerOrigin, forKey: Key.miniPlayerOrigin) } }

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
    var pocketTrigger: PocketTrigger { didSet { defaults.set(pocketTrigger.rawValue, forKey: Key.pocketTrigger) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read before anything below writes the first settings.
        onboarded = !OnboardingStep.needsSetup(
            storedFlag: defaults.object(forKey: Key.onboarded) == nil ? nil : defaults.bool(forKey: Key.onboarded),
            hasEarlierSettings: defaults.object(forKey: Key.profiles) != nil)
        defaults.register(defaults: [
            Key.hotkey: Hotkey.hyperSpace.stringValue,
            Key.quickPressTogglesCapsLock: true,
            Key.showOnExternalDisplays: true,
            Key.hoverDelay: 0.15,
            // Hover only peeks; a click opens, so the shelf never appears by accident.
            Key.openTrigger: OpenTrigger.click.rawValue,
            Key.shelfAutoCloses: true,
            Key.animationSpeed: AnimationSpeed.standard.rawValue,
            Key.externalStyle: ExternalStyle.notch.rawValue,
            Key.glassEdge: GlassEdge.subtle.rawValue,
            Key.surfaceStyle: SurfaceStyle.black.rawValue,
            Key.adaptiveAccent: false,
            Key.contextAware: true,
            Key.volumeHUD: true,
            Key.brightnessHUD: true,
            Key.batteryHUD: true,
            Key.capsLockHUD: true,
            Key.mediaActivity: true,
            Key.approvalSound: true,
            Key.lyrics: true,
            Key.artworkLookup: true,
            Key.meetingActivity: true,
            Key.lockScreenPlayer: true,
            Key.activityBubbles: true,
            Key.activityDisplay: ActivityDisplayTarget.pointer.rawValue,
            Key.clipboardEnabled: true,
            Key.clipboardLimit: 200,
            Key.notificationsEnabled: true,
            Key.hideSystemBanners: true,
            Key.whatsAppReplies: false,
            Key.telegramReplies: false,
            Key.focusActivity: true,
            Key.scrubberSounds: true,
            Key.widgetGridRows: 2,
            Key.workdayStart: 9,
            Key.workdayEnd: 18,
            Key.worldClockZones: ["America/New_York", "Europe/London", "Asia/Tokyo"],
        ])
        hotkey = defaults.string(forKey: Key.hotkey).flatMap(Hotkey.init(string:)) ?? .hyperSpace
        quickPressTogglesCapsLock = defaults.bool(forKey: Key.quickPressTogglesCapsLock)
        showOnExternalDisplays = defaults.bool(forKey: Key.showOnExternalDisplays)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        openTrigger = defaults.string(forKey: Key.openTrigger).flatMap(OpenTrigger.init(rawValue:)) ?? .click
        shelfAutoCloses = defaults.bool(forKey: Key.shelfAutoCloses)
        animationSpeed =
            defaults.string(forKey: Key.animationSpeed).flatMap(AnimationSpeed.init(rawValue:)) ?? .standard
        externalStyle = defaults.string(forKey: Key.externalStyle).flatMap(ExternalStyle.init(rawValue:)) ?? .notch
        glassEdge = defaults.string(forKey: Key.glassEdge).flatMap(GlassEdge.init(rawValue:)) ?? .subtle
        surfaceStyle = defaults.string(forKey: Key.surfaceStyle).flatMap(SurfaceStyle.init(rawValue:)) ?? .black
        adaptiveAccent = defaults.bool(forKey: Key.adaptiveAccent)
        contextAware = defaults.bool(forKey: Key.contextAware)
        lastSettingsPane =
            defaults.string(forKey: Key.lastSettingsPane).flatMap(SettingsPaneID.init(rawValue:)) ?? .general
        contextRules =
            defaults.data(forKey: Key.contextRules).flatMap { try? JSONDecoder().decode([ContextRule].self, from: $0) }
            ?? ContextRules.defaults
        let active = defaults.string(forKey: Key.activeProfile) ?? ContextEngineState.baseProfile
        activeProfile = active
        homeProfile = defaults.string(forKey: Key.homeProfile) ?? active
        profiles = []
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
        approvalSound = defaults.bool(forKey: Key.approvalSound)
        lyrics = defaults.bool(forKey: Key.lyrics)
        artworkLookup = defaults.bool(forKey: Key.artworkLookup)
        meetingActivity = defaults.bool(forKey: Key.meetingActivity)
        lockScreenPlayer = defaults.bool(forKey: Key.lockScreenPlayer)
        activityBubbles = defaults.bool(forKey: Key.activityBubbles)
        miniPlayerOrigin = defaults.string(forKey: Key.miniPlayerOrigin)
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
        favouriteShortcuts = defaults.stringArray(forKey: Key.favouriteShortcuts) ?? []
        doNotDisturbShortcut = defaults.string(forKey: Key.doNotDisturbShortcut) ?? ""
        workdayStart = defaults.integer(forKey: Key.workdayStart)
        workdayEnd = defaults.integer(forKey: Key.workdayEnd)
        worldClockZones = defaults.stringArray(forKey: Key.worldClockZones) ?? []
        pocketTrigger =
            (defaults.string(forKey: Key.pocketTrigger) ?? defaults.string(forKey: Key.legacyPocketTrigger))
            .flatMap(PocketTrigger.init(rawValue:)) ?? .shake
        introduceNewWidgets()
        // First run with profiles: the everyday profile starts as the user's current setup.
        profiles =
            defaults.data(forKey: Key.profiles).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) }
            ?? Profile.builtIns.map { builtIn in
                guard builtIn.name == ContextEngineState.baseProfile else { return builtIn }
                return Profile(
                    name: builtIn.name, home: homeLayout, defaultPage: builtIn.defaultPage,
                    surface: surfaceStyle.rawValue)
            }
    }
}

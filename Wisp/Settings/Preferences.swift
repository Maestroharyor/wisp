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

extension Placement {
    var title: String {
        switch self {
        case .top: "Top"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottom: "Bottom"
        case .left: "Left edge"
        case .right: "Right edge"
        case .floating: "Floating orb"
        }
    }
}

/// Shape on displays without a camera housing.
enum ExternalStyle: String, CaseIterable, Identifiable {
    case notch
    case island

    var id: Self { self }
    var title: String { self == .notch ? "Notch" : "Floating island" }
}

/// How long the volume, brightness and Caps Lock overlays stay up.
enum HUDDuration: String, CaseIterable, Identifiable {
    case short
    case standard
    case long

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var seconds: TimeInterval {
        switch self {
        case .short: 1
        case .standard: 1.6
        case .long: 2.6
        }
    }
}

/// How long a notification card stays when the pointer isn't on it.
enum NotificationDuration: String, CaseIterable, Identifiable {
    case short
    case standard
    case long

    var id: Self { self }
    var title: String {
        switch self {
        case .short: "3 seconds"
        case .standard: "6 seconds"
        case .long: "10 seconds"
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .short: 3
        case .standard: 6
        case .long: 10
        }
    }
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
    case script
    case quickInput

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
        case .script: "Script"
        case .quickInput: "Quick add"
        }
    }

    /// Widgets whose content needs the taller row.
    var needsTallRow: Bool { self == .nowPlaying }

    /// Size when first added to Home.
    var defaultSize: WidgetSize {
        switch self {
        case .nowPlaying: .large
        case .calendar, .systemStats, .notes, .quickToggles, .shortcuts, .clipboard, .dayProgress, .agents, .script,
            .quickInput:
            .medium
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
        case .script: "terminal"
        case .quickInput: "text.badge.plus"
        }
    }
}

/// User settings, persisted in UserDefaults. Observed by the UI and by services.
@MainActor
@Observable
final class Preferences {
    static let shared: Preferences = {
        // Wisp Dev starts from scratch, so it shows first-run setup like a new install.
        #if !DEBUG
            importLegacyDefaults(into: .standard)
        #endif
        return Preferences()
    }()

    /// Copies settings saved under the old bundle ID once, before anything reads them.
    private static func importLegacyDefaults(into defaults: UserDefaults) {
        guard !defaults.bool(forKey: LegacyDefaults.importedFlagKey) else { return }
        let old = defaults.persistentDomain(forName: LegacyDefaults.oldDomain)
        for (key, value) in LegacyDefaults.entriesToCopy(from: old ?? [:]) where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: LegacyDefaults.importedFlagKey)
    }

    private enum Key {
        static let hotkey = "hotkey"
        static let quickPressTogglesCapsLock = "quickPressTogglesCapsLock"
        static let dictationEnabled = "dictationEnabled"
        static let dictationKey = "dictationKey"
        static let showOnExternalDisplays = "showOnExternalDisplays"
        static let hoverDelay = "hoverDelay"
        static let openTrigger = "openTrigger"
        static let shelfClosing = "shelfClosing"
        /// The earlier on/off setting, read once to carry it over.
        static let shelfAutoCloses = "shelfAutoCloses"
        static let animationSpeed = "animationSpeed"
        static let externalStyle = "externalStyle"
        static let glassEdge = "glassEdge"
        static let surfaceStyle = "surfaceStyle"
        static let lastSettingsPane = "lastSettingsPane"
        static let onboarded = "onboarded"
        static let profiles = "profiles"
        static let profilesVersion = "profilesVersion"
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
        static let terminalBarMode = "terminalBarMode"
        static let contextAlert = "contextAlert"
        static let contextThreshold = "contextThreshold"
        static let agentPrivacy = "agentPrivacy"
        static let agentToolActivity = "agentToolActivity"
        static let agentKeepAwake = "agentKeepAwake"
        static let agentHistory = "agentHistory"
        static let agentSummaries = "agentSummaries"
        static let toolAlert = "toolAlert"
        static let toolAlertMinutes = "toolAlertMinutes"
        static let nudgeAlert = "nudgeAlert"
        static let nudgeMinutes = "nudgeMinutes"
        static let budgetAlert = "budgetAlert"
        static let limitAlert = "limitAlert"
        static let dailyBudget = "dailyBudget"
        static let pushEnabled = "pushEnabled"
        static let pushServer = "pushServer"
        static let pushTopic = "pushTopic"
        static let pushReplyTopic = "pushReplyTopic"
        static let pushKinds = "pushKinds"
        static let pushMode = "pushMode"
        static let pushIdleMinutes = "pushIdleMinutes"
        static let pushTimeoutMinutes = "pushTimeoutMinutes"
        static let pushDetails = "pushDetails"
        static let cloudEnabled = "cloudEnabled"
        static let cloudSources = "cloudSources"
        static let cloudChecks = "cloudChecks"
        static let aiEnabled = "aiEnabled"
        static let aiEngine = "aiEngine"
        static let ollamaAddress = "ollamaAddress"
        static let ollamaModel = "ollamaModel"
        static let lyrics = "lyrics"
        static let artworkLookup = "artworkLookup"
        static let meetingActivity = "meetingActivity"
        static let meetingControls = "meetingControls"
        static let meetingShortcutControls = "meetingShortcutControls"
        static let lockScreenPlayer = "lockScreenPlayer"
        static let activityBubbles = "activityBubbles"
        static let theme = "theme"
        static let customAccent = "customAccent"
        static let customGlow = "customGlow"
        static let wallpaperTint = "wallpaperTint"
        static let shellOutline = "shellOutline"
        static let hudDuration = "hudDuration"
        static let volumeSteps = "volumeSteps"
        static let hudUsesAccent = "hudUsesAccent"
        static let batteryLowThreshold = "batteryLowThreshold"
        static let defaultTimerSeconds = "defaultTimerSeconds"
        static let firstBubbleOnLeft = "firstBubbleOnLeft"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let swipeGestures = "swipeGestures"
        static let displayStyles = "displayStyles"
        static let placement = "placement"
        static let islandSetting = "islandSetting"
        static let orbCentres = "orbCentres"
        static let orbReturnPlacements = "orbReturnPlacements"
        static let islandSpots = "islandSpots"
        static let displayPlacements = "displayPlacements"
        static let miniPlayerOrigin = "miniPlayerOrigin"
        static let windowForm = "windowForm"
        static let shelfWindowFrame = "shelfWindowFrame"
        static let windowSelection = "windowSelection"
        static let activityDisplay = "activityDisplay"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardLimit = "clipboardLimit"
        static let notificationsEnabled = "notificationsEnabled"
        static let hideSystemBanners = "hideSystemBanners"
        static let notificationDuration = "notificationDuration"
        static let blockedNotificationApps = "blockedNotificationApps"
        static let whatsAppReplies = "whatsAppReplies"
        static let telegramReplies = "telegramReplies"
        static let focusActivity = "focusActivity"
        static let pocketTrigger = "pocketTrigger"
        /// Earlier builds' name for the pocket setting, read once to carry it over.
        static let legacyPocketTrigger = "basketTrigger"
        static let scrubberSounds = "scrubberSounds"
        static let widgetGridOrder = "widgetGridOrder"
        static let widgetGridRows = "widgetGridRows"
        static let introducedWidgets = "introducedWidgets"
        static let favouriteShortcuts = "favouriteShortcuts"
        static let dropActions = "dropActions"
        static let ringConfig = "ringConfig"
        static let ringOnOrbClick = "ringOnOrbClick"
        static let ringButton = "ringButton"
        static let ringHotkey = "ringHotkey"
        static let scriptCommand = "scriptCommand"
        static let deviceActivity = "deviceActivity"
        static let accessoryBatteries = "accessoryBatteries"
        static let downloadActivity = "downloadActivity"
        static let downloadFolders = "downloadFolders"
        static let scriptInterval = "scriptInterval"
        static let doNotDisturbShortcut = "doNotDisturbShortcut"
        static let workdayStart = "workdayStart"
        static let workdayEnd = "workdayEnd"
        static let worldClockZones = "worldClockZones"
        static let appearance = "appearance"
        static let lookPresets = "lookPresets"
        static let lookBeforeProfile = "lookBeforeProfile"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Toggles the shelf. Hyper (Caps Lock) shortcuts need Accessibility access.
    var hotkey: Hotkey { didSet { defaults.set(hotkey.stringValue, forKey: Key.hotkey) } }

    /// Pressing Caps Lock on its own still toggles Caps Lock while it doubles as Hyper.
    var quickPressTogglesCapsLock: Bool {
        didSet { defaults.set(quickPressTogglesCapsLock, forKey: Key.quickPressTogglesCapsLock) }
    }

    /// Hold a Hyper key to dictate. Off by default: it asks for Speech Recognition and the microphone.
    var dictationEnabled: Bool { didSet { defaults.set(dictationEnabled, forKey: Key.dictationEnabled) } }
    var dictationKey: DictationKey { didSet { defaults.set(dictationKey.rawValue, forKey: Key.dictationKey) } }

    /// Show the shelf on displays without a notch.
    var showOnExternalDisplays: Bool {
        didSet { defaults.set(showOnExternalDisplays, forKey: Key.showOnExternalDisplays) }
    }

    /// Seconds the pointer must rest on the notch before it opens.
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }

    var openTrigger: OpenTrigger { didSet { defaults.set(openTrigger.rawValue, forKey: Key.openTrigger) } }
    /// What closes an open shelf: the pointer leaving, a click elsewhere, or only Esc and
    /// the shortcut.
    var shelfClosing: ShelfClosing { didSet { defaults.set(shelfClosing.rawValue, forKey: Key.shelfClosing) } }

    /// Every look setting; saved as one JSON value.
    var appearance: Appearance {
        didSet {
            defaults.set(try? JSONEncoder().encode(appearance), forKey: Key.appearance)
            // An edit by hand (a theme, a slider, a look) is the new base, so the next profile
            // switch must not put an older look back over it.
            if !applyingProfileLook { lookBase.editedByHand() }
        }
    }

    /// Set while a profile puts on (or takes off) its own look, which isn't an edit by hand.
    @ObservationIgnored private var applyingProfileLook = false

    /// Looks saved under a name in Settings › Appearance.
    var lookPresets: [AppearancePreset] {
        didSet { defaults.set(try? JSONEncoder().encode(lookPresets), forKey: Key.lookPresets) }
    }

    var animationSpeed: AnimationSpeed {
        get { appearance.animationSpeed }
        set { appearance.animationSpeed = newValue }
    }

    var externalStyle: ExternalStyle {
        didSet { defaults.set(externalStyle.rawValue, forKey: Key.externalStyle) }
    }

    var glassEdge: GlassEdge {
        get { appearance.glassEdge }
        set { appearance.glassEdge = newValue }
    }
    var surfaceStyle: SurfaceStyle {
        get { appearance.surface }
        set {
            appearance.surface = newValue
            updateActiveProfile { $0.surface = newValue.rawValue }
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
        // Not content, but without it the next launch imports the old build's settings again.
        LegacyDefaults.importedFlagKey,
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
        applyingProfileLook = true
        defer { applyingProfileLook = false }
        if let name = profile.look, let preset = lookPreset(named: name) {
            appearance = lookBase.putOn(preset.appearance, over: appearance)
        } else {
            if let earlier = lookBase.takeOff() { appearance = earlier }
            surfaceStyle = SurfaceStyle(rawValue: profile.surface) ?? surfaceStyle
        }
    }

    /// The look in use before a profile applied its own, put back by the next profile
    /// that has none. Saved, because the profile's look is saved as `appearance`: losing
    /// this on quit would leave the profile's look in place for good.
    @ObservationIgnored private var lookBase: LookBase {
        didSet {
            guard lookBase != oldValue else { return }
            defaults.set(lookBase.base.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.lookBeforeProfile)
        }
    }

    // MARK: Looks

    /// Wisp's looks, then the saved ones.
    var allLookPresets: [AppearancePreset] { AppearancePreset.builtIns + lookPresets }

    func lookPreset(named name: String) -> AppearancePreset? { allLookPresets.first { $0.name == name } }

    /// Applies a look chosen in Settings. Keeps the user's custom sound files, and saves the
    /// surface to the active profile as the surface picker does, so the profile doesn't put
    /// the old one back later.
    func applyLook(_ look: Appearance) {
        let next = look.keepingSounds(of: appearance)
        appearance = next
        updateActiveProfile { $0.surface = next.surface.rawValue }
    }

    func isCurrentLook(_ look: Appearance) -> Bool { look.keepingSounds(of: appearance) == appearance }

    /// Saves the current look under a name and returns the name used.
    @discardableResult
    func saveLook(named name: String) -> String {
        let unique = AppearancePreset.uniqueName(name, existing: lookPresets.map(\.name))
        lookPresets.append(AppearancePreset(name: unique, appearance: appearance))
        return unique
    }

    /// Adds an imported look, renaming it if the name is taken.
    @discardableResult
    func addLook(_ file: LookFile) -> String {
        let unique = AppearancePreset.uniqueName(file.name, existing: lookPresets.map(\.name))
        lookPresets.append(AppearancePreset(name: unique, appearance: file.appearance))
        return unique
    }

    func deleteLook(named name: String) {
        lookPresets.removeAll { $0.name == name }
        for index in profiles.indices where profiles[index].look == name { profiles[index].look = nil }
    }

    func setLook(_ name: String?, forProfile profileName: String) {
        guard let index = profiles.firstIndex(where: { $0.name == profileName }) else { return }
        profiles[index].look = name
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
        // A rule that switches to a missing profile would do nothing but still show as on.
        contextRules.removeAll { $0.profile == name }
        if activeProfile == name || homeProfile == name, let base = profile(named: ContextEngineState.baseProfile) {
            apply(base)
        }
    }

    /// Puts back a profile's Home that was edited while it was showing, without showing it.
    func restoreHome(_ layout: HomeLayout, toProfile name: String) {
        guard let index = profiles.firstIndex(where: { $0.name == name }) else { return }
        profiles[index].home = layout
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
    var adaptiveAccent: Bool {
        get { appearance.adaptiveAccent }
        set { appearance.adaptiveAccent = newValue }
    }

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

    /// The user's own actions for dropped files; the first two also appear as drop tiles.
    /// The radial ring's segments: the default ring and any per-app rings.
    var ringConfig: RingConfig {
        didSet { defaults.set(try? JSONEncoder().encode(ringConfig), forKey: Key.ringConfig) }
    }
    /// Clicking the orb opens the ring rather than the shelf (the ring's centre opens the shelf).
    var ringOnOrbClick: Bool { didSet { defaults.set(ringOnOrbClick, forKey: Key.ringOnOrbClick) } }
    /// The extra mouse button that opens the ring; off until chosen, since it takes the
    /// button away from every app.
    var ringButton: RingButton { didSet { defaults.set(ringButton.rawValue, forKey: Key.ringButton) } }
    /// A shortcut that opens the ring without the Hyper key; nil when unset.
    var ringHotkey: Hotkey? {
        didSet { defaults.set(ringHotkey?.stringValue ?? "", forKey: Key.ringHotkey) }
    }

    var dropActions: [DropAction] {
        didSet { defaults.set(try? JSONEncoder().encode(dropActions), forKey: Key.dropActions) }
    }

    /// What the Script widget runs, split into arguments without a shell.
    var scriptCommand: String { didSet { defaults.set(scriptCommand, forKey: Key.scriptCommand) } }
    /// Seconds between runs while the widget is on screen.
    var scriptInterval: Double { didSet { defaults.set(scriptInterval, forKey: Key.scriptInterval) } }

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
        // Mirror needs the camera and Script needs a command, so both wait to be turned on.
        for kind in WidgetKind.allCases where !seen.contains(kind.rawValue) && kind != .mirror && kind != .script {
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
    /// A pill when Bluetooth headphones connect, with their battery.
    var deviceActivity: Bool { didSet { defaults.set(deviceActivity, forKey: Key.deviceActivity) } }
    /// Mouse, keyboard and trackpad batteries in the Battery widget, with a warning at 20%.
    var accessoryBatteries: Bool { didSet { defaults.set(accessoryBatteries, forKey: Key.accessoryBatteries) } }
    /// A progress pill while a browser downloads into Downloads or a chosen folder. Off by
    /// default: turning it on can make macOS ask for access to the Downloads folder.
    var downloadActivity: Bool { didSet { defaults.set(downloadActivity, forKey: Key.downloadActivity) } }
    /// Folders watched besides Downloads, as plain paths (Wisp isn't sandboxed).
    var downloadFolders: [String] { didSet { defaults.set(downloadFolders, forKey: Key.downloadFolders) } }
    var capsLockHUD: Bool { didSet { defaults.set(capsLockHUD, forKey: Key.capsLockHUD) } }
    var mediaActivity: Bool { didSet { defaults.set(mediaActivity, forKey: Key.mediaActivity) } }
    /// A short sound when an agent asks for permission.
    var approvalSound: Bool { didSet { defaults.set(approvalSound, forKey: Key.approvalSound) } }
    /// What Claude Code's status bar shows once connected: Wisp's, the user's own, or nothing new.
    var terminalBarMode: TerminalBarMode {
        didSet { defaults.set(terminalBarMode.rawValue, forKey: Key.terminalBarMode) }
    }
    /// A notice when a session's context window passes `contextThreshold` percent.
    var contextAlert: Bool { didSet { defaults.set(contextAlert, forKey: Key.contextAlert) } }
    var contextThreshold: Int { didSet { defaults.set(contextThreshold, forKey: Key.contextThreshold) } }
    /// When agent commands, file paths and session names are hidden.
    var agentPrivacy: AgentPrivacy.Mode {
        didSet { defaults.set(agentPrivacy.rawValue, forKey: Key.agentPrivacy) }
    }
    /// The tool an agent is running shows in the pill; needs Claude Code's tool hooks.
    var agentToolActivity: Bool { didSet { defaults.set(agentToolActivity, forKey: Key.agentToolActivity) } }
    /// Stop the Mac sleeping while an agent is working (the display may still sleep).
    var agentKeepAwake: Bool { didSet { defaults.set(agentKeepAwake, forKey: Key.agentKeepAwake) } }
    /// Finished sessions are kept on this Mac (figures, tools, masked commands, no prompts).
    var agentHistory: Bool { didSet { defaults.set(agentHistory, forKey: Key.agentHistory) } }
    /// A finished session is summarised by the on-device AI, when AI is on.
    var agentSummaries: Bool { didSet { defaults.set(agentSummaries, forKey: Key.agentSummaries) } }
    /// A notice when one tool call runs longer than `toolAlertMinutes`; needs tool activity.
    var toolAlert: Bool { didSet { defaults.set(toolAlert, forKey: Key.toolAlert) } }
    var toolAlertMinutes: Int { didSet { defaults.set(toolAlertMinutes, forKey: Key.toolAlertMinutes) } }
    /// One more sound and pill when a session has waited for the user `nudgeMinutes`.
    var nudgeAlert: Bool { didSet { defaults.set(nudgeAlert, forKey: Key.nudgeAlert) } }
    var nudgeMinutes: Int { didSet { defaults.set(nudgeMinutes, forKey: Key.nudgeMinutes) } }
    /// Notices at 80% and 100% of `dailyBudget` dollars of spend in a day.
    var budgetAlert: Bool { didSet { defaults.set(budgetAlert, forKey: Key.budgetAlert) } }
    /// Notices at 80% and 95% of Claude's five-hour and weekly usage limits.
    var limitAlert: Bool { didSet { defaults.set(limitAlert, forKey: Key.limitAlert) } }
    var dailyBudget: Double { didSet { defaults.set(dailyBudget, forKey: Key.dailyBudget) } }
    /// Phone push through ntfy. Off by default: it sends to a server.
    var pushEnabled: Bool { didSet { defaults.set(pushEnabled, forKey: Key.pushEnabled) } }
    /// The ntfy server, `https://ntfy.sh` unless self-hosted.
    var pushServer: String { didSet { defaults.set(pushServer, forKey: Key.pushServer) } }
    /// Where Wisp publishes; the phone subscribes to it. Made the first time push is turned on.
    var pushTopic: String { didSet { defaults.set(pushTopic, forKey: Key.pushTopic) } }
    /// Where the phone's Allow and Deny buttons post; Wisp listens while approvals wait.
    var pushReplyTopic: String { didSet { defaults.set(pushReplyTopic, forKey: Key.pushReplyTopic) } }
    var pushKinds: Set<PushKind> {
        didSet { defaults.set(pushKinds.map(\.rawValue).sorted(), forKey: Key.pushKinds) }
    }
    var pushMode: PushMode { didSet { defaults.set(pushMode.rawValue, forKey: Key.pushMode) } }
    /// Minutes without input that count as away.
    var pushIdleMinutes: Int { didSet { defaults.set(pushIdleMinutes, forKey: Key.pushIdleMinutes) } }
    /// How long permission prompts wait while push is on, so the phone has time to answer.
    var pushTimeoutMinutes: Int { didSet { defaults.set(pushTimeoutMinutes, forKey: Key.pushTimeoutMinutes) } }
    /// Adds a masked summary (command, file name) to approval notifications.
    var pushDetails: Bool { didSet { defaults.set(pushDetails, forKey: Key.pushDetails) } }
    /// On-device AI for features that offer it. Off by default.
    var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled) } }
    var aiEngine: AIEngineKind { didSet { defaults.set(aiEngine.rawValue, forKey: Key.aiEngine) } }
    /// Ollama's address; only addresses on this Mac are used (`OllamaEndpoint.base`).
    var ollamaAddress: String { didSet { defaults.set(ollamaAddress, forKey: Key.ollamaAddress) } }
    /// The Ollama model to use; empty means the first one pulled.
    var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: Key.ollamaModel) } }
    /// The PermissionRequest hook timeout these settings ask for.
    var approvalTimeout: Int { HookInstaller.approvalTimeout(push: pushEnabled, minutes: pushTimeoutMinutes) }
    /// Cloud agent tasks in the Agents widget. Off by default: it asks Codex, GitHub and Cursor.
    var cloudEnabled: Bool { didSet { defaults.set(cloudEnabled, forKey: Key.cloudEnabled) } }
    /// Which cloud sources to ask; one whose CLI or key is missing is skipped anyway.
    var cloudSources: Set<CloudSource> {
        didSet { defaults.set(cloudSources.map(\.rawValue).sorted(), forKey: Key.cloudSources) }
    }
    /// Reads each recent pull request's CI with `gh pr checks`.
    var cloudChecks: Bool { didSet { defaults.set(cloudChecks, forKey: Key.cloudChecks) } }
    /// Fetch lyrics from LRCLIB for the playing song (sends title, artist and length).
    var lyrics: Bool { didSet { defaults.set(lyrics, forKey: Key.lyrics) } }
    /// Look up album art on iTunes when the player gives none (sends title and artist).
    var artworkLookup: Bool { didSet { defaults.set(artworkLookup, forKey: Key.artworkLookup) } }
    /// The meeting pill while the microphone is in use, and the Join card before calls.
    var meetingActivity: Bool { didSet { defaults.set(meetingActivity, forKey: Key.meetingActivity) } }
    /// Mute, camera, share and leave for Zoom, Teams and Meet, through Accessibility.
    var meetingControls: Bool { didSet { defaults.set(meetingControls, forKey: Key.meetingControls) } }
    /// Teams and Meet controls type shortcuts into the call window. Off by default: Teams marks
    /// no meeting window Wisp could confirm before typing.
    var meetingShortcutControls: Bool {
        didSet { defaults.set(meetingShortcutControls, forKey: Key.meetingShortcutControls) }
    }
    /// Show a player while the screen is locked, where macOS allows it.
    var lockScreenPlayer: Bool { didSet { defaults.set(lockScreenPlayer, forKey: Key.lockScreenPlayer) } }
    /// Extra live activities split off into round bubbles beside the pill.
    var activityBubbles: Bool { didSet { defaults.set(activityBubbles, forKey: Key.activityBubbles) } }
    /// The first bubble splits off to the left instead of the right.
    var firstBubbleOnLeft: Bool { didSet { defaults.set(firstBubbleOnLeft, forKey: Key.firstBubbleOnLeft) } }

    // MARK: Appearance

    var theme: ThemeID {
        get { appearance.theme }
        set { appearance.theme = newValue }
    }
    /// Colours for the Custom theme.
    var customAccent: RGB {
        get { appearance.customAccent }
        set { appearance.customAccent = newValue }
    }
    var customGlow: RGB {
        get { appearance.customGlow }
        set { appearance.customGlow = newValue }
    }
    /// Take the glow from the desktop picture instead of the theme.
    var wallpaperTint: Bool {
        get { appearance.wallpaperTint }
        set { appearance.wallpaperTint = newValue }
    }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    /// Two-finger swipes on the notch: down opens, sideways skips tracks.
    var swipeGestures: Bool { didSet { defaults.set(swipeGestures, forKey: Key.swipeGestures) } }
    /// Per-display choice by display UUID; missing means automatic.
    var displayStyles: [String: String] { didSet { defaults.set(displayStyles, forKey: Key.displayStyles) } }

    func displayStyle(for uuid: String) -> DisplayStyle {
        displayStyles[uuid].flatMap(DisplayStyle.init(rawValue:)) ?? .automatic
    }

    func setDisplayStyle(_ style: DisplayStyle, for uuid: String) {
        displayStyles[uuid] = style == .automatic ? nil : style.rawValue
    }

    /// Where the shell sits on displays without their own choice.
    var placement: Placement {
        didSet {
            defaults.set(placement.rawValue, forKey: Key.placement)
            // A new default puts islands that follow it back on their spot.
            let kept = islandSpots.filter { displayPlacements[$0.key] != nil }
            if kept != islandSpots { islandSpots = kept }
        }
    }
    var islandSetting: IslandSetting {
        didSet { defaults.set(islandSetting.rawValue, forKey: Key.islandSetting) }
    }
    /// Where each display's orb rests, as "x,y" by display UUID.
    var orbCentres: [String: String] { didSet { defaults.set(orbCentres, forKey: Key.orbCentres) } }
    /// The placement override each display had before its shell became an orb; "" means it
    /// followed the default.
    var orbReturnPlacements: [String: String] {
        didSet { defaults.set(orbReturnPlacements, forKey: Key.orbReturnPlacements) }
    }

    func orbCentre(for uuid: String) -> CGPoint? { orbCentres[uuid].flatMap(OrbGeometry.decode) }

    /// Turns the display's shell into an orb, at `centre` or where its orb last rested.
    func floatOrb(_ uuid: String, at centre: CGPoint? = nil) {
        if let centre, orbCentres[uuid] != OrbGeometry.encode(centre) { orbCentres[uuid] = OrbGeometry.encode(centre) }
        updateOrbPlacements { $0.float(uuid) }
    }

    /// Puts the orb back where the shell was before it floated, or at the top.
    func dockOrb(_ uuid: String) {
        updateOrbPlacements { $0.dock(uuid) }
    }

    func setForm(_ form: FormFactor, for uuid: String) {
        // The window form lives in `windowForm` and leaves every display's shell as it was.
        guard form != .window else { return }
        // The orb keeps a moved island's spot, so docking goes back there; other forms start fresh.
        if form != .orb { moveIslandBack(uuid) }
        updateOrbPlacements { $0.set(form, for: uuid) }
    }

    /// Where each display's dragged island rests, as "placement@x,y" by display UUID.
    var islandSpots: [String: String] { didSet { defaults.set(islandSpots, forKey: Key.islandSpots) } }

    func islandSpot(for uuid: String) -> IslandSpot? { islandSpots[uuid].flatMap(IslandSpot.init(encoded:)) }

    func moveIsland(_ uuid: String, to spot: IslandSpot) {
        if islandSpots[uuid] != spot.encoded { islandSpots[uuid] = spot.encoded }
    }

    func moveIslandBack(_ uuid: String) {
        if islandSpots[uuid] != nil { islandSpots[uuid] = nil }
    }

    private func updateOrbPlacements(_ change: (inout OrbPlacements) -> Void) {
        var state = OrbPlacements(overrides: displayPlacements, returns: orbReturnPlacements, standard: placement)
        change(&state)
        // Written only when changed, so observers don't rebuild for nothing.
        if state.returns != orbReturnPlacements { orbReturnPlacements = state.returns }
        if state.overrides != displayPlacements { displayPlacements = state.overrides }
    }
    /// Per-display placements by display UUID; a display missing here follows `placement`.
    var displayPlacements: [String: String] {
        didSet { defaults.set(displayPlacements, forKey: Key.displayPlacements) }
    }

    /// The display's own placement, or nil when it follows the default.
    func placementOverride(for uuid: String) -> Placement? {
        displayPlacements[uuid].flatMap(Placement.init(rawValue:))
    }

    func placement(for uuid: String) -> Placement { placementOverride(for: uuid) ?? placement }

    func setPlacementOverride(_ placement: Placement?, for uuid: String) {
        moveIslandBack(uuid)
        displayPlacements[uuid] = placement?.rawValue
    }

    // MARK: HUDs and alerts

    var hudDuration: HUDDuration { didSet { defaults.set(hudDuration.rawValue, forKey: Key.hudDuration) } }
    /// Notches on the volume scale per key press (macOS uses 16).
    var volumeSteps: Int { didSet { defaults.set(volumeSteps, forKey: Key.volumeSteps) } }
    /// Paint the volume and brightness bars in the accent instead of green and yellow.
    var hudUsesAccent: Bool { didSet { defaults.set(hudUsesAccent, forKey: Key.hudUsesAccent) } }
    var batteryLowThreshold: Int {
        didSet { defaults.set(batteryLowThreshold, forKey: Key.batteryLowThreshold) }
    }
    /// Low-battery alerts: the chosen level, then 10% as a last call.
    var batteryThresholds: [Int] { batteryLowThreshold > 10 ? [batteryLowThreshold, 10] : [batteryLowThreshold] }
    var defaultTimerSeconds: Double {
        didSet { defaults.set(defaultTimerSeconds, forKey: Key.defaultTimerSeconds) }
    }
    /// Where the mini player was last left, as "x,y" (its top-left corner).
    var miniPlayerOrigin: String? { didSet { defaults.set(miniPlayerOrigin, forKey: Key.miniPlayerOrigin) } }
    /// The Window form: the shelf opens in its own window instead of under the shell.
    var windowForm: Bool { didSet { defaults.set(windowForm, forKey: Key.windowForm) } }
    /// Where the shelf window was last left, as "x,y,width,height" (see `ShelfWindowFrame`).
    var shelfWindowFrame: String? { didSet { defaults.set(shelfWindowFrame, forKey: Key.shelfWindowFrame) } }
    /// The shelf window's last sidebar row, as `WindowDestination.rawValue`.
    var windowSelection: String? { didSet { defaults.set(windowSelection, forKey: Key.windowSelection) } }

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
    var notificationDuration: NotificationDuration {
        didSet { defaults.set(notificationDuration.rawValue, forKey: Key.notificationDuration) }
    }
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
            Key.ringOnOrbClick: true,
            Key.hoverDelay: 0.15,
            // Hover only peeks; a click opens, so the shelf never appears by accident.
            Key.openTrigger: OpenTrigger.click.rawValue,
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
            Key.terminalBarMode: TerminalBarMode.wisp.rawValue,
            Key.contextAlert: true,
            Key.contextThreshold: Int(ContextUsage.defaultThreshold),
            Key.agentPrivacy: AgentPrivacy.Mode.default.rawValue,
            Key.agentToolActivity: false,
            Key.agentKeepAwake: false,
            Key.agentHistory: true,
            Key.agentSummaries: true,
            Key.toolAlert: true,
            Key.toolAlertMinutes: AgentAlertRules.defaultToolMinutes,
            Key.nudgeAlert: false,
            Key.nudgeMinutes: AgentAlertRules.defaultNudgeMinutes,
            Key.budgetAlert: false,
            Key.limitAlert: true,
            Key.dailyBudget: 20.0,
            Key.pushEnabled: false,
            Key.pushServer: PushTopic.defaultServer,
            Key.pushKinds: PushKind.defaults.map(\.rawValue).sorted(),
            Key.pushMode: PushMode.default.rawValue,
            Key.pushIdleMinutes: PushPolicy.defaultIdleMinutes,
            Key.pushTimeoutMinutes: HookInstaller.defaultPushTimeoutMinutes,
            Key.pushDetails: false,
            Key.cloudEnabled: false,
            Key.cloudSources: CloudSource.allCases.map(\.rawValue),
            Key.cloudChecks: true,
            Key.aiEnabled: false,
            Key.aiEngine: AIEngineKind.default.rawValue,
            Key.ollamaAddress: OllamaEndpoint.defaultAddress,
            Key.lyrics: true,
            Key.artworkLookup: true,
            Key.meetingActivity: true,
            Key.meetingControls: true,
            Key.meetingShortcutControls: false,
            Key.lockScreenPlayer: true,
            Key.activityBubbles: true,
            Key.firstBubbleOnLeft: false,
            Key.theme: ThemeID.default.rawValue,
            Key.customAccent: ThemeCatalog.violet.hex,
            Key.customGlow: "#2EC4B6",
            Key.wallpaperTint: false,
            Key.shellOutline: false,
            Key.showMenuBarIcon: true,
            Key.swipeGestures: true,
            Key.hudDuration: HUDDuration.standard.rawValue,
            Key.volumeSteps: 16,
            Key.hudUsesAccent: false,
            Key.batteryLowThreshold: 20,
            Key.defaultTimerSeconds: 300.0,
            Key.scriptInterval: 60.0,
            Key.deviceActivity: true,
            Key.accessoryBatteries: true,
            Key.activityDisplay: ActivityDisplayTarget.pointer.rawValue,
            Key.clipboardEnabled: true,
            Key.clipboardLimit: 200,
            Key.notificationsEnabled: true,
            Key.hideSystemBanners: true,
            Key.notificationDuration: NotificationDuration.standard.rawValue,
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
        dictationEnabled = defaults.bool(forKey: Key.dictationEnabled)
        dictationKey = defaults.string(forKey: Key.dictationKey).flatMap(DictationKey.init(rawValue:)) ?? .space
        showOnExternalDisplays = defaults.bool(forKey: Key.showOnExternalDisplays)
        hoverDelay = defaults.double(forKey: Key.hoverDelay)
        openTrigger = defaults.string(forKey: Key.openTrigger).flatMap(OpenTrigger.init(rawValue:)) ?? .click
        shelfClosing = ShelfClosing(
            storedValue: defaults.string(forKey: Key.shelfClosing),
            legacyAutoClose: defaults.object(forKey: Key.shelfAutoCloses) == nil
                ? nil : defaults.bool(forKey: Key.shelfAutoCloses))
        // Earlier builds kept each look setting under its own key; carry them over once.
        appearance =
            defaults.data(forKey: Key.appearance).flatMap { try? JSONDecoder().decode(Appearance.self, from: $0) }
            ?? Appearance.migrated(
                from: LegacyLook(
                    theme: defaults.string(forKey: Key.theme),
                    customAccent: defaults.string(forKey: Key.customAccent),
                    customGlow: defaults.string(forKey: Key.customGlow),
                    wallpaperTint: defaults.bool(forKey: Key.wallpaperTint),
                    adaptiveAccent: defaults.bool(forKey: Key.adaptiveAccent),
                    shellOutline: defaults.bool(forKey: Key.shellOutline),
                    animationSpeed: defaults.string(forKey: Key.animationSpeed),
                    surface: defaults.string(forKey: Key.surfaceStyle),
                    glassEdge: defaults.string(forKey: Key.glassEdge)))
        lookPresets =
            defaults.data(forKey: Key.lookPresets).flatMap {
                try? JSONDecoder().decode([AppearancePreset].self, from: $0)
            } ?? []
        lookBase = LookBase(
            base: defaults.data(forKey: Key.lookBeforeProfile).flatMap {
                try? JSONDecoder().decode(Appearance.self, from: $0)
            })
        externalStyle = defaults.string(forKey: Key.externalStyle).flatMap(ExternalStyle.init(rawValue:)) ?? .notch
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
        terminalBarMode = defaults.string(forKey: Key.terminalBarMode).flatMap(TerminalBarMode.init(rawValue:)) ?? .wisp
        contextAlert = defaults.bool(forKey: Key.contextAlert)
        contextThreshold = min(max(defaults.integer(forKey: Key.contextThreshold), 50), 95)
        agentPrivacy =
            defaults.string(forKey: Key.agentPrivacy).flatMap(AgentPrivacy.Mode.init(rawValue:)) ?? .default
        agentToolActivity = defaults.bool(forKey: Key.agentToolActivity)
        agentKeepAwake = defaults.bool(forKey: Key.agentKeepAwake)
        agentHistory = defaults.bool(forKey: Key.agentHistory)
        agentSummaries = defaults.bool(forKey: Key.agentSummaries)
        toolAlert = defaults.bool(forKey: Key.toolAlert)
        toolAlertMinutes = min(max(defaults.integer(forKey: Key.toolAlertMinutes), 1), 60)
        nudgeAlert = defaults.bool(forKey: Key.nudgeAlert)
        nudgeMinutes = min(max(defaults.integer(forKey: Key.nudgeMinutes), 1), 30)
        budgetAlert = defaults.bool(forKey: Key.budgetAlert)
        limitAlert = defaults.bool(forKey: Key.limitAlert)
        let budget = defaults.double(forKey: Key.dailyBudget)
        dailyBudget = budget > 0 ? budget : 20
        pushEnabled = defaults.bool(forKey: Key.pushEnabled)
        pushServer = defaults.string(forKey: Key.pushServer) ?? PushTopic.defaultServer
        pushTopic = defaults.string(forKey: Key.pushTopic) ?? ""
        pushReplyTopic = defaults.string(forKey: Key.pushReplyTopic) ?? ""
        pushKinds = Set((defaults.stringArray(forKey: Key.pushKinds) ?? []).compactMap(PushKind.init(rawValue:)))
        pushMode = defaults.string(forKey: Key.pushMode).flatMap(PushMode.init(rawValue:)) ?? .default
        pushIdleMinutes = min(
            max(defaults.integer(forKey: Key.pushIdleMinutes), PushPolicy.idleMinutesRange.lowerBound),
            PushPolicy.idleMinutesRange.upperBound)
        pushTimeoutMinutes = min(
            max(defaults.integer(forKey: Key.pushTimeoutMinutes), HookInstaller.pushTimeoutMinutes.lowerBound),
            HookInstaller.pushTimeoutMinutes.upperBound)
        pushDetails = defaults.bool(forKey: Key.pushDetails)
        cloudEnabled = defaults.bool(forKey: Key.cloudEnabled)
        cloudSources = Set(
            (defaults.stringArray(forKey: Key.cloudSources) ?? []).compactMap(CloudSource.init(rawValue:)))
        cloudChecks = defaults.bool(forKey: Key.cloudChecks)
        aiEnabled = defaults.bool(forKey: Key.aiEnabled)
        aiEngine = defaults.string(forKey: Key.aiEngine).flatMap(AIEngineKind.init(rawValue:)) ?? .default
        ollamaAddress = defaults.string(forKey: Key.ollamaAddress) ?? OllamaEndpoint.defaultAddress
        ollamaModel = defaults.string(forKey: Key.ollamaModel) ?? ""
        lyrics = defaults.bool(forKey: Key.lyrics)
        artworkLookup = defaults.bool(forKey: Key.artworkLookup)
        meetingActivity = defaults.bool(forKey: Key.meetingActivity)
        meetingControls = defaults.bool(forKey: Key.meetingControls)
        meetingShortcutControls = defaults.bool(forKey: Key.meetingShortcutControls)
        lockScreenPlayer = defaults.bool(forKey: Key.lockScreenPlayer)
        activityBubbles = defaults.bool(forKey: Key.activityBubbles)
        firstBubbleOnLeft = defaults.bool(forKey: Key.firstBubbleOnLeft)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        swipeGestures = defaults.bool(forKey: Key.swipeGestures)
        displayStyles = (defaults.dictionary(forKey: Key.displayStyles) ?? [:]).compactMapValues { "\($0)" }
        placement = defaults.string(forKey: Key.placement).flatMap(Placement.init(rawValue:)) ?? .top
        islandSetting =
            defaults.string(forKey: Key.islandSetting).flatMap(IslandSetting.init(rawValue:)) ?? .automatic
        orbCentres = (defaults.dictionary(forKey: Key.orbCentres) ?? [:]).compactMapValues { "\($0)" }
        orbReturnPlacements =
            (defaults.dictionary(forKey: Key.orbReturnPlacements) ?? [:]).compactMapValues { "\($0)" }
        islandSpots = (defaults.dictionary(forKey: Key.islandSpots) ?? [:]).compactMapValues { "\($0)" }
        displayPlacements = (defaults.dictionary(forKey: Key.displayPlacements) ?? [:]).compactMapValues { "\($0)" }
        hudDuration = defaults.string(forKey: Key.hudDuration).flatMap(HUDDuration.init(rawValue:)) ?? .standard
        volumeSteps = defaults.integer(forKey: Key.volumeSteps)
        hudUsesAccent = defaults.bool(forKey: Key.hudUsesAccent)
        batteryLowThreshold = defaults.integer(forKey: Key.batteryLowThreshold)
        defaultTimerSeconds = defaults.double(forKey: Key.defaultTimerSeconds)
        miniPlayerOrigin = defaults.string(forKey: Key.miniPlayerOrigin)
        windowForm = defaults.bool(forKey: Key.windowForm)
        shelfWindowFrame = defaults.string(forKey: Key.shelfWindowFrame)
        windowSelection = defaults.string(forKey: Key.windowSelection)
        activityDisplay =
            defaults.string(forKey: Key.activityDisplay).flatMap(ActivityDisplayTarget.init(rawValue:)) ?? .pointer
        clipboardEnabled = defaults.bool(forKey: Key.clipboardEnabled)
        clipboardLimit = max(defaults.integer(forKey: Key.clipboardLimit), 20)
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        hideSystemBanners = defaults.bool(forKey: Key.hideSystemBanners)
        notificationDuration =
            defaults.string(forKey: Key.notificationDuration).flatMap(NotificationDuration.init(rawValue:)) ?? .standard
        blockedNotificationApps = defaults.stringArray(forKey: Key.blockedNotificationApps) ?? []
        whatsAppReplies = defaults.bool(forKey: Key.whatsAppReplies)
        telegramReplies = defaults.bool(forKey: Key.telegramReplies)
        focusActivity = defaults.bool(forKey: Key.focusActivity)
        scrubberSounds = defaults.bool(forKey: Key.scrubberSounds)
        widgetGridOrder =
            (defaults.stringArray(forKey: Key.widgetGridOrder) ?? []).compactMap(WidgetKind.init(rawValue:))
        widgetGridRows = WidgetGrid.clampedRows(defaults.integer(forKey: Key.widgetGridRows))
        favouriteShortcuts = defaults.stringArray(forKey: Key.favouriteShortcuts) ?? []
        scriptCommand = defaults.string(forKey: Key.scriptCommand) ?? ""
        deviceActivity = defaults.bool(forKey: Key.deviceActivity)
        accessoryBatteries = defaults.bool(forKey: Key.accessoryBatteries)
        downloadActivity = defaults.bool(forKey: Key.downloadActivity)
        downloadFolders = defaults.stringArray(forKey: Key.downloadFolders) ?? []
        scriptInterval = ScriptOutput.clampedInterval(defaults.double(forKey: Key.scriptInterval))
        ringConfig =
            defaults.data(forKey: Key.ringConfig).flatMap { try? JSONDecoder().decode(RingConfig.self, from: $0) }
            ?? RingConfig.defaults
        ringOnOrbClick = defaults.bool(forKey: Key.ringOnOrbClick)
        ringButton = defaults.string(forKey: Key.ringButton).flatMap(RingButton.init(rawValue:)) ?? .off
        ringHotkey = defaults.string(forKey: Key.ringHotkey).flatMap(Hotkey.init(string:))
        dropActions =
            defaults.data(forKey: Key.dropActions).flatMap { try? JSONDecoder().decode([DropAction].self, from: $0) }
            ?? []
        doNotDisturbShortcut = defaults.string(forKey: Key.doNotDisturbShortcut) ?? ""
        workdayStart = defaults.integer(forKey: Key.workdayStart)
        workdayEnd = defaults.integer(forKey: Key.workdayEnd)
        worldClockZones = defaults.stringArray(forKey: Key.worldClockZones) ?? []
        pocketTrigger =
            (defaults.string(forKey: Key.pocketTrigger) ?? defaults.string(forKey: Key.legacyPocketTrigger))
            .flatMap(PocketTrigger.init(rawValue:)) ?? .shake
        introduceNewWidgets()
        // First run with profiles: the everyday profile starts as the user's current setup.
        let saved = defaults.data(forKey: Key.profiles).flatMap {
            try? JSONDecoder().decode([Profile].self, from: $0)
        }
        profiles =
            saved.map { Profile.upgrade($0, from: defaults.integer(forKey: Key.profilesVersion)) }
            ?? Profile.builtIns.map { builtIn in
                guard builtIn.name == ContextEngineState.baseProfile else { return builtIn }
                return Profile(
                    name: builtIn.name, home: homeLayout, defaultPage: builtIn.defaultPage,
                    surface: surfaceStyle.rawValue)
            }
        // Observers don't run in init: save the upgrade so the version below stays true.
        if let saved {
            defaults.set(try? JSONEncoder().encode(profiles), forKey: Key.profiles)
            homeLayout = Profile.upgradedHome(homeLayout, profile: homeProfile, before: saved, after: profiles)
            defaults.set(try? JSONEncoder().encode(homeLayout), forKey: Key.homeLayout)
        }
        defaults.set(Profile.builtInsVersion, forKey: Key.profilesVersion)
    }
}

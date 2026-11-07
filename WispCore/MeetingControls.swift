import Foundation

/// A button on the meeting controls.
public enum MeetingControl: String, CaseIterable, Sendable {
    case mute
    case camera
    case share
    case leave
}

/// A call app Wisp can drive.
public enum MeetingApp: Equatable, Sendable {
    case zoom
    case teams
    /// Google Meet in a Chromium browser, by the browser's bundle id.
    case meet(browser: String)

    public var bundleID: String {
        switch self {
        case .zoom: "us.zoom.xos"
        case .teams: "com.microsoft.teams2"
        case .meet(let browser): browser
        }
    }
}

/// Modifier keys for a shortcut.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1)
    public static let shift = KeyModifiers(rawValue: 2)
}

/// A keyboard shortcut by virtual key code (the `kVK_ANSI_*` values from Carbon's Events.h).
public struct KeyShortcut: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static let keyD: UInt16 = 0x02
    static let keyE: UInt16 = 0x0E
    static let keyH: UInt16 = 0x04
    static let keyM: UInt16 = 0x2E
    static let keyO: UInt16 = 0x1F
}

/// How one control is driven in one app.
public enum MeetingControlStrategy: Equatable, Sendable {
    /// Press a menu bar item. `engaged` titles show while the control is on (muted, camera
    /// on, sharing), `idle` titles while it is off. The app's menu tells the state.
    case menu(idle: [String], engaged: [String])
    /// A documented keyboard shortcut that toggles. The app doesn't say which way it went.
    case shortcut(KeyShortcut)
}

/// A control ready to show: its state when the app tells it, and its label.
public struct MeetingControlState: Equatable, Sendable, Identifiable {
    public let control: MeetingControl
    /// Nil when the app doesn't report it (shortcut-driven apps).
    public let engaged: Bool?

    public init(control: MeetingControl, engaged: Bool?) {
        self.control = control
        self.engaged = engaged
    }

    public var id: MeetingControl { control }

    public var label: String {
        switch (control, engaged) {
        case (.mute, true): "Unmute"
        case (.mute, false): "Mute"
        case (.mute, nil): "Mic"
        case (.camera, true): "Stop video"
        case (.camera, false): "Start video"
        case (.camera, nil): "Camera"
        case (.share, true): "Stop share"
        case (.share, _): "Share"
        case (.leave, _): "Leave"
        }
    }

    /// The tooltip. Shortcut apps don't report state, so their buttons say they only toggle.
    public var help: String {
        switch (control, engaged) {
        case (.mute, nil): "Toggles the call's microphone, without confirming which way it went"
        case (.camera, nil): "Toggles the call's camera, without confirming which way it went"
        case (.leave, _): "Leave the call (tap twice)"
        default: label
        }
    }

    public var symbol: String {
        switch (control, engaged) {
        case (.mute, true): "mic.slash.fill"
        case (.mute, _): "mic.fill"
        case (.camera, false): "video.slash.fill"
        case (.camera, _): "video.fill"
        case (.share, true): "rectangle.on.rectangle.slash"
        case (.share, _): "rectangle.on.rectangle"
        case (.leave, _): "phone.down.fill"
        }
    }
}

public enum MeetingControls {
    /// Chromium browsers, where Meet's shortcuts reach the page. Safari is left out: its own
    /// menu shortcuts (Command-D adds a bookmark) may take the keys first.
    public static let meetBrowsers: [String] = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// Zoom's in-meeting menu titles, from the Localizable.strings of Zoom 7.1.9 for every
    /// language it ships. Older versions use title case ("Mute Audio"), which matching ignores.
    static let zoomMute = (
        idle: [
            "Mute audio", "Audio stummschalten", "Silenciar audio", "Désactiver le son", "Bisukan audio",
            "Disattiva audio", "オーディオのミュート", "오디오 음소거", "Audio dempen", "Wycisz dźwięk", "Desativar áudio",
            "Выключить звук", "Inaktivera ljud", "Sesi kapat", "Tắt tiếng âm thanh", "静音", "靜音",
        ],
        engaged: [
            "Unmute audio", "Stummschaltung für Audio aufheben", "Reactivar audio", "Réactiver le son",
            "Bunyikan audio", "Attiva audio", "オーディオのミュート解除", "오디오 음소거 해제", "Audio dempen opheffen",
            "Wyłącz wyciszenie dźwięku", "Ativar áudio", "Включить звук", "Aktivera ljud", "Sesi aç",
            "Bỏ tắt tiếng âm thanh", "解除静音", "解除靜音",
        ]
    )

    static let zoomCamera = (
        idle: [
            "Start video", "Video starten", "Iniciar vídeo", "Démarrer la vidéo", "Mulai video", "Avvia video",
            "ビデオをオンにする", "비디오 시작", "Uruchom wideo", "Начать видео", "Starta video", "Videoyu başlat",
            "Bắt đầu video", "开启视频", "開啟視訊",
        ],
        engaged: [
            "Stop video", "Video beenden", "Detener vídeo", "Arrêter la vidéo", "Hentikan video", "Disattiva video",
            "ビデオをオフにする", "비디오 중지", "Zatrzymaj wideo", "Interromper vídeo", "Остановить видео",
            "Stoppa video", "Videoyu durdur", "Dừng video", "停止视频", "停止視訊",
        ]
    )

    static let zoomShare = (
        idle: [
            "Start share", "Share starten", "Iniciar compartir", "Commencer à partager", "Mulai berbagi",
            "Avvia condivisione", "共有の開始", "공유 시작", "Delen starten", "Rozpocznij udostępnianie",
            "Iniciar compartilhamento", "Начать совместное использование", "Starta delning", "Paylaşımı başlat",
            "Bắt đầu chia sẻ", "开始共享", "開始分享",
        ],
        engaged: [
            "Stop share", "Freigabe stoppen", "Dejar de compartir", "Arrêter le partage", "Hentikan berbagi",
            "Interrompi condivisione", "共有の停止", "공유 중지", "Delen stoppen", "Zatrzymaj udostępnianie",
            "Interromper compartilhamento", "Остановить совместное использование", "Stoppa delning",
            "Paylaşımı durdur", "Dừng chia sẻ", "停止共享", "停止分享",
        ]
    )

    /// Leaving, or ending for a host; Zoom asks before either goes through.
    static let zoomLeave = [
        "Leave meeting", "Meeting verlassen", "Salir de la reunión", "Quitter la réunion", "Keluar dari rapat",
        "Esci dalla riunione", "ミーティングを退出", "회의 나가기", "Vergadering verlaten", "Opuść spotkanie",
        "Sair da reunião", "Выйти из конференции", "Lämna mötet", "Toplantıdan çık", "Rời khỏi cuộc họp", "离开会议",
        "離開會議", "End meeting", "Meeting beenden", "Finalizar reunión", "Mettre fin à la réunion", "Akhiri rapat",
        "Termina riunione", "ミーティングを終了", "회의 종료", "Vergadering beëindigen", "Zakończ spotkanie",
        "Encerrar reunião", "Завершить конференцию", "Avsluta mötet", "Toplantıyı sonlandır", "Kết thúc cuộc họp",
        "结束会议", "結束會議",
    ]

    /// The controls each app supports and how. Teams and Meet use their documented shortcuts
    /// (Microsoft's "Keyboard shortcuts for Microsoft Teams", Google's Meet shortcut list);
    /// neither documents a direct share shortcut, nor Meet one for leaving, so those are left out.
    public static func strategies(for app: MeetingApp) -> [(MeetingControl, MeetingControlStrategy)] {
        switch app {
        case .zoom:
            [
                (.mute, .menu(idle: zoomMute.idle, engaged: zoomMute.engaged)),
                (.camera, .menu(idle: zoomCamera.idle, engaged: zoomCamera.engaged)),
                (.share, .menu(idle: zoomShare.idle, engaged: zoomShare.engaged)),
                (.leave, .menu(idle: zoomLeave, engaged: [])),
            ]
        case .teams:
            [
                (.mute, .shortcut(KeyShortcut(keyCode: KeyShortcut.keyM, modifiers: [.command, .shift]))),
                (.camera, .shortcut(KeyShortcut(keyCode: KeyShortcut.keyO, modifiers: [.command, .shift]))),
                (.leave, .shortcut(KeyShortcut(keyCode: KeyShortcut.keyH, modifiers: [.command, .shift]))),
            ]
        case .meet:
            [
                (.mute, .shortcut(KeyShortcut(keyCode: KeyShortcut.keyD, modifiers: [.command]))),
                (.camera, .shortcut(KeyShortcut(keyCode: KeyShortcut.keyE, modifiers: [.command]))),
            ]
        }
    }

    public static func strategy(for control: MeetingControl, in app: MeetingApp) -> MeetingControlStrategy? {
        strategies(for: app).first { $0.0 == control }?.1
    }

    /// Keystrokes go to the frontmost app, so shortcut apps come forward first. Zoom's menu
    /// works from behind, except leaving: its confirmation should be in view.
    public static func bringsForward(_ app: MeetingApp, for control: MeetingControl) -> Bool {
        switch strategy(for: control, in: app) {
        case .shortcut: true
        case .menu: control == .leave
        case nil: false
        }
    }

    /// Whether the app reads its controls from the menu bar.
    public static func usesMenu(_ app: MeetingApp) -> Bool {
        strategies(for: app).contains {
            if case .menu = $0.1 { true } else { false }
        }
    }

    /// The app to drive, from the apps holding the microphone: a call app first, then a
    /// Chromium browser whose front window is a Meet call (`meetWindows`, bundle ids the app
    /// layer checked). Browsers record through helper processes, so a helper's id counts for
    /// its browser.
    public static func app(inputApps: [String], meetWindows: Set<String>) -> MeetingApp? {
        if inputApps.contains("us.zoom.xos") { return .zoom }
        if inputApps.contains("com.microsoft.teams2") { return .teams }
        for browser in meetBrowsers where meetWindows.contains(browser) {
            if inputApps.contains(where: { $0 == browser || $0.hasPrefix(browser + ".") }) {
                return .meet(browser: browser)
            }
        }
        return nil
    }

    /// Whether a browser window shows a Meet call: its URL is on meet.google.com, or, when
    /// the browser doesn't give the URL, its title is Meet's call title ("Meet - abc-defg-hij").
    public static func isMeetWindow(title: String?, url: String?) -> Bool {
        if let url, let host = URL(string: url)?.host?.lowercased() { return host == "meet.google.com" }
        guard let title else { return false }
        return ["Meet - ", "Meet – ", "Meet — "].contains { title.hasPrefix($0) }
    }

    /// The controls to show, with their state. Menu controls show only while their item is
    /// in the app's menu (Zoom lists them during a call), so an unknown version or language
    /// shows nothing rather than a dead button.
    public static func states(for app: MeetingApp, menuTitles: [String]) -> [MeetingControlState] {
        let present = Set(menuTitles.map(normalize))
        return strategies(for: app).compactMap { control, strategy in
            switch strategy {
            case .shortcut:
                return MeetingControlState(control: control, engaged: nil)
            case .menu(let idle, let engaged):
                if engaged.contains(where: { present.contains(normalize($0)) }) {
                    return MeetingControlState(control: control, engaged: true)
                }
                if idle.contains(where: { present.contains(normalize($0)) }) {
                    return MeetingControlState(control: control, engaged: false)
                }
                return nil
            }
        }
    }

    /// Whether a menu item is the one that drives `control`.
    public static func menuItem(_ title: String, drives control: MeetingControl, in app: MeetingApp) -> Bool {
        guard case .menu(let idle, let engaged) = strategy(for: control, in: app) else { return false }
        let wanted = normalize(title)
        return (idle + engaged).contains { normalize($0) == wanted }
    }

    /// Case, spacing and a trailing ellipsis vary between versions.
    static func normalize(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["…", "..."] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

extension MeetingControls {
    /// Whether a calendar invite is for the call `app` drives, so the Join card only offers
    /// that app's controls for its own meeting.
    public static func invite(_ link: URL, matches app: MeetingApp) -> Bool {
        guard let host = link.host?.lowercased() else { return false }
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        switch app {
        case .zoom: return on("zoom.us")
        case .teams: return on("teams.microsoft.com") || on("teams.live.com")
        case .meet: return host == "meet.google.com"
        }
    }

    /// Apps driven by typing shortcuts. Their call window can't always be confirmed (Teams
    /// marks none), so they're a separate opt-in.
    public static func usesShortcuts(_ app: MeetingApp) -> Bool {
        strategies(for: app).contains {
            if case .shortcut = $0.1 { true } else { false }
        }
    }

    /// The Join card is for the next meeting, so it never offers Leave.
    public static func joinCardStates(_ states: [MeetingControlState]) -> [MeetingControlState] {
        states.filter { $0.control != .leave }
    }

    /// Roles that take typed text; a shortcut sent there could land in the field instead.
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Whether a shortcut may be typed into the app now, from what Accessibility reports about
    /// its focused window and focused element. The keyboard must not be in the browser's own
    /// address bar (a text field outside the page). Meet needs its call tab in the focused
    /// window; Teams needs a focused window.
    public static func mayType(_ app: MeetingApp, focus: FocusSnapshot) -> Bool {
        guard focus.appIsFrontmost, focus.readSeconds <= FocusSnapshot.freshFor else { return false }
        if let role = focus.focusedRole, textRoles.contains(role), !focus.focusedInWebArea { return false }
        switch app {
        case .zoom: return false
        case .teams: return focus.hasFocusedWindow
        case .meet: return isMeetWindow(title: focus.windowTitle, url: focus.windowURL)
        }
    }

    /// Who gets the keyboard back after a press. Nobody when Wisp didn't move focus, or after
    /// Leave went through (its confirmation and the call ending should stay in view). The
    /// window that was focused when the call's own app was in front (another window of the
    /// same browser). Otherwise the app that was in front.
    public static func handBack(
        movedFocus: Bool, sent: Bool, control: MeetingControl, previousPID: Int32?, targetPID: Int32,
        previousWindow: String?, callWindow: String?
    ) -> HandBack {
        guard movedFocus, let previousPID else { return .none }
        if sent, control == .leave { return .none }
        if previousPID != targetPID { return .app(previousPID) }
        guard let previousWindow, previousWindow != callWindow else { return .none }
        return .window(title: previousWindow)
    }
}

/// What Accessibility says about the call app, for deciding whether a shortcut may be typed.
public struct FocusSnapshot: Equatable, Sendable {
    public var appIsFrontmost: Bool
    public var windowTitle: String?
    public var windowURL: String?
    /// The app has a focused window. Teams doesn't mark its meeting window (no documented
    /// title or subrole), so this is all Teams can be checked for; hence shortcut apps are opt-in.
    public var hasFocusedWindow: Bool
    public var focusedRole: String?
    /// The focused element sits inside the page (an AXWebArea), not the browser's own chrome.
    public var focusedInWebArea: Bool
    /// How long reading it took. A slow read may describe a window that has since changed.
    public var readSeconds: TimeInterval = 0
    public static let freshFor: TimeInterval = 0.2

    public init(
        appIsFrontmost: Bool, windowTitle: String? = nil, windowURL: String? = nil,
        hasFocusedWindow: Bool = false, focusedRole: String? = nil, focusedInWebArea: Bool = false
    ) {
        self.appIsFrontmost = appIsFrontmost
        self.windowTitle = windowTitle
        self.windowURL = windowURL
        self.hasFocusedWindow = hasFocusedWindow
        self.focusedRole = focusedRole
        self.focusedInWebArea = focusedInWebArea
    }
}

/// Where the keyboard goes back after a meeting control press.
public enum HandBack: Equatable, Sendable {
    case none
    case app(Int32)
    /// The call's own app was in front: raise the window that was focused, by title.
    case window(title: String)
}

/// Leave takes two taps: the first arms it for a few seconds and asks "Leave?", a second one
/// in that time sends it.
public struct LeaveConfirmation: Equatable, Sendable {
    public static let window: TimeInterval = 3
    public private(set) var armedAt: Date?

    public init() {}

    public func isArmed(now: Date) -> Bool {
        guard let armedAt else { return false }
        let age = now.timeIntervalSince(armedAt)
        return age >= 0 && age < Self.window
    }

    /// A second tap sooner than this is a double click, not a decision.
    public static let minimumGap: TimeInterval = 0.5

    /// Returns true when this tap should send Leave. A tap too soon after arming does nothing.
    public mutating func tap(now: Date) -> Bool {
        if isArmed(now: now), let armed = armedAt {
            guard now.timeIntervalSince(armed) >= Self.minimumGap else { return false }
            armedAt = nil
            return true
        }
        armedAt = now
        return false
    }

    public func label(now: Date) -> String { isArmed(now: now) ? "Leave?" : "Leave" }
}

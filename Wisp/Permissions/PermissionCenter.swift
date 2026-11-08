import AVFoundation
import AppKit
import Contacts
import CoreGraphics
import EventKit
import Speech
import WispCore

/// Every macOS permission Wisp can use, with a status check and a deep link.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility
    case fullDiskAccess
    case screenRecording
    case contacts
    case automation
    case calendars
    case camera
    case microphone
    case speechRecognition
    case systemAudio

    var id: Self { self }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .fullDiskAccess: "Full Disk Access"
        case .screenRecording: "Screen Recording"
        case .contacts: "Contacts"
        case .automation: "Automation"
        case .calendars: "Calendars"
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .speechRecognition: "Speech Recognition"
        case .systemAudio: "System Audio Recording"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: "Caps Lock shortcut, volume and brightness keys, pasting, hiding system banners"
        case .fullDiskAccess:
            "Reading notifications, Messages chats and Focus status. Click + or drag Wisp into the list, then switch it on"
        case .screenRecording: "Watching a window region and Capture text"
        case .contacts: "Photos and names on notifications"
        case .automation: "Replying in Messages, meeting controls, Up Next in Music, Music fallback"
        case .calendars: "Calendar and Day Progress widgets"
        case .camera: "Mirror widget"
        case .microphone: "Dictation, only while you hold the key"
        case .speechRecognition: "Dictation, transcribed on this Mac"
        case .systemAudio:
            "Per-app volume. macOS asks the first time you turn an app down; Wisp can tell it's on only once it hears that app"
        }
    }

    /// Nil when macOS can't say yet (Automation, while neither Finder nor System Events can answer;
    /// System Audio Recording, which has no status check, until a tap has heard something).
    @MainActor var isGranted: Bool? {
        switch self {
        case .accessibility: AccessibilityPermission.isTrusted
        case .fullDiskAccess: Self.hasFullDiskAccess
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .contacts: CNContactStore.authorizationStatus(for: .contacts) == .authorized
        case .automation: AutomationPermission.status
        case .calendars: EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .camera: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized
        case .systemAudio: SystemAudioPermission.status
        }
    }

    /// Every status by id, for spotting changes.
    @MainActor static var statuses: [String: Bool?] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.isGranted) })
    }

    private var settingsAnchor: String {
        switch self {
        case .accessibility: "Privacy_Accessibility"
        case .fullDiskAccess: "Privacy_AllFiles"
        case .screenRecording: "Privacy_ScreenCapture"
        case .contacts: "Privacy_Contacts"
        case .automation: "Privacy_Automation"
        case .calendars: "Privacy_Calendars"
        case .camera: "Privacy_Camera"
        case .microphone: "Privacy_Microphone"
        case .speechRecognition: "Privacy_SpeechRecognition"
        // The Screen & System Audio Recording pane.
        case .systemAudio: "Privacy_ScreenCapture"
        }
    }

    /// The last Allow clicked, so the grant that answers it can bring Wisp forward.
    @MainActor static var lastRequest: PermissionRequest?

    private static let askedScreenRecordingKey = "askedScreenRecording"

    /// Whether Wisp has shown the Screen Recording prompt, which macOS shows only once.
    static var askedScreenRecording: Bool { UserDefaults.standard.bool(forKey: askedScreenRecordingKey) }

    /// For features that capture the screen: asks for Screen Recording and returns what to tell
    /// the user. The first time that's the system prompt; after that the prompt never shows
    /// again, so System Settings opens, and a grant there reaches Wisp only after it's reopened.
    @MainActor static func askForScreenRecording() -> String {
        let askedBefore = askedScreenRecording
        screenRecording.request()
        return askedBefore
            ? "Turn on Screen Recording, then quit and reopen Wisp" : "Allow Screen Recording, then try again"
    }

    @MainActor func request() {
        Self.lastRequest = PermissionRequest(id: rawValue, at: .now)
        switch self {
        case .accessibility: AccessibilityPermission.requestAccess()
        // macOS asks only the first time; after that the switch is in System Settings. Wisp
        // can't tell whether the prompt is showing or was used up by an older version (before
        // the flag existed), so it opens Settings whenever access is still off, and a press
        // never does nothing.
        case .screenRecording:
            UserDefaults.standard.set(true, forKey: Self.askedScreenRecordingKey)
            if !CGRequestScreenCaptureAccess(), !CGPreflightScreenCaptureAccess() { openSettings() }
        // macOS asks only once. After that, and for a denial, the switch is in System Settings,
        // which lists an app only once it has asked.
        case .contacts:
            guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return openSettings() }
            Task { _ = try? await CNContactStore().requestAccess(for: .contacts) }
        case .camera:
            guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return openSettings() }
            Task { _ = await AVCaptureDevice.requestAccess(for: .video) }
        case .microphone:
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return openSettings() }
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        case .speechRecognition:
            guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return openSettings() }
            Task { _ = await DictationEngine.requestSpeechAccess() }
        case .calendars:
            guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return openSettings() }
            Task { _ = try? await EKEventStore().requestFullAccessToEvents() }
        case .fullDiskAccess:
            // No prompt, and Wisp isn't listed until added by hand: show a guide to drag it in.
            FullDiskAccessGuide.shared.show()
        case .automation: AutomationPermission.request()
        // No prompt to show on demand: macOS asks when a tap first plays, so open the list.
        case .systemAudio: openSettings()
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The notification store's group container is readable only with Full Disk Access.
    static var hasFullDiskAccess: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted").path
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }
}

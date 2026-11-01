import AVFoundation
import AppKit
import Contacts
import CoreGraphics
import EventKit
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
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: "Caps Lock shortcut, volume and brightness keys, pasting, hiding system banners"
        case .fullDiskAccess:
            "Reading notifications, Messages chats and Focus status. Click + or drag Wisp into the list, then switch it on"
        case .screenRecording: "Recording the screen from the notch"
        case .contacts: "Photos and names on notifications"
        case .automation: "Replying in Messages, meeting controls, Music fallback"
        case .calendars: "Calendar and Day Progress widgets"
        case .camera: "Mirror widget"
        }
    }

    /// Nil when macOS can't say yet (Automation, while neither Finder nor System Events can answer).
    @MainActor var isGranted: Bool? {
        switch self {
        case .accessibility: AccessibilityPermission.isTrusted
        case .fullDiskAccess: Self.hasFullDiskAccess
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .contacts: CNContactStore.authorizationStatus(for: .contacts) == .authorized
        case .automation: AutomationPermission.status
        case .calendars: EKEventStore.authorizationStatus(for: .event) == .fullAccess
        case .camera: AVCaptureDevice.authorizationStatus(for: .video) == .authorized
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
        }
    }

    /// The last Allow clicked, so the grant that answers it can bring Wisp forward.
    @MainActor static var lastRequest: PermissionRequest?

    @MainActor func request() {
        Self.lastRequest = PermissionRequest(id: rawValue, at: .now)
        switch self {
        case .accessibility: AccessibilityPermission.requestAccess()
        // macOS asks only the first time; after that the switch is in System Settings.
        case .screenRecording: if !CGRequestScreenCaptureAccess() { openSettings() }
        // macOS asks only once. After that, and for a denial, the switch is in System Settings,
        // which lists an app only once it has asked.
        case .contacts:
            guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return openSettings() }
            Task { _ = try? await CNContactStore().requestAccess(for: .contacts) }
        case .camera:
            guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return openSettings() }
            Task { _ = await AVCaptureDevice.requestAccess(for: .video) }
        case .calendars:
            guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return openSettings() }
            Task { _ = try? await EKEventStore().requestFullAccessToEvents() }
        case .fullDiskAccess:
            // No prompt, and Wisp isn't listed until added by hand: show a guide to drag it in.
            FullDiskAccessGuide.shared.show()
        case .automation: AutomationPermission.request()
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

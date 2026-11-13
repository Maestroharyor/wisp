import AppKit
import CoreGraphics
import Foundation
import WispCore

/// Watches the screen lock and fast user switching. macOS sends "screen is locked" for both,
/// so a lock is only reported once `SessionLock` confirms it, and switching to another account
/// is reported on its own so Wisp can step out of the way until this session is back.
@MainActor
final class SessionMonitor {
    enum Change {
        /// A real lock, held for a moment in this session on the console.
        case locked
        case unlocked
        /// Another account is in front.
        case resigned
        /// This account is back in front.
        case resumed
    }

    var onChange: @MainActor (Change) -> Void = { _ in }

    private var lock = SessionLock()
    private var confirmTask: Task<Void, Never>?
    private var distributed: [NSObjectProtocol] = []
    private var workspace: [NSObjectProtocol] = []

    /// Whether this session is the one in front.
    var isActive: Bool { lock.sessionActive }
    /// A confirmed lock that hasn't been unlocked yet.
    var isLocked: Bool { lock.confirmed }

    func start() {
        let center = DistributedNotificationCenter.default()
        for (name, event) in [
            ("com.apple.screenIsLocked", SessionLock.Event.screenLocked),
            ("com.apple.screenIsUnlocked", .screenUnlocked),
        ] {
            distributed.append(
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(event) }
                })
        }
        let shared = NSWorkspace.shared.notificationCenter
        for (name, event) in [
            (NSWorkspace.sessionDidResignActiveNotification, SessionLock.Event.sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionResumed),
        ] {
            workspace.append(
                shared.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.handle(event) }
                })
        }
    }

    func stop() {
        confirmTask?.cancel()
        distributed.forEach(DistributedNotificationCenter.default().removeObserver)
        workspace.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        distributed = []
        workspace = []
    }

    private func handle(_ event: SessionLock.Event) {
        switch lock.handle(event) {
        case .none:
            return
        case .confirmLater:
            confirmTask?.cancel()
            confirmTask = Task { [weak self] in
                try? await Task.sleep(for: SessionLock.settle)
                guard !Task.isCancelled else { return }
                self?.confirm()
            }
        case .unlock:
            confirmTask?.cancel()
            onChange(.unlocked)
        case .suspend:
            confirmTask?.cancel()
            onChange(.resigned)
        case .resume:
            onChange(.resumed)
        }
    }

    private func confirm() {
        if lock.confirm(onConsole: Self.onConsole) { onChange(.locked) }
    }

    /// Whether this login session owns the display. Unknown counts as yes, so a missing key
    /// can't keep a real lock from counting.
    private static var onConsole: Bool {
        // The CoreGraphics session dictionary is untyped; read the one Boolean it documents.
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return session[kCGSessionOnConsoleKey] as? Bool ?? true
    }
}

import AppKit
import OSLog

/// Quits Wisp and opens it again. Some grants (Screen Recording) may only reach a fresh process.
@MainActor
enum Relaunch {
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "permissions")

    /// A copy opened straight from a disk image or Downloads runs from a temporary path that
    /// may be gone once it quits, so reopening it could leave nothing running.
    static var isAvailable: Bool { !Bundle.main.bundlePath.contains("/AppTranslocation/") }

    static func now() {
        guard isAvailable else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Waits for this process to exit so two copies never draw two notches. The pid and
        // path are arguments, not part of the script.
        process.arguments = [
            "-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
            "relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path,
        ]
        do {
            try process.run()
        } catch {
            log.error("Couldn't start the relaunch helper: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }
}

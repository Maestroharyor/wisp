import AppKit

/// Quits Wisp and opens it again. Some grants (Screen Recording) only reach a fresh process.
@MainActor
enum Relaunch {
    static func now() {
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
            return
        }
        NSApp.terminate(nil)
    }
}

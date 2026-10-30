import Foundation

/// Runs AppleScript through `osascript`, off the main thread and with a time limit, so a
/// hung player or a pending Automation prompt can't freeze the notch.
enum AppleScriptRunner {
    static func run(_ source: String, timeout: Duration = .seconds(3)) async -> String? {
        let output = try? await ProcessRunner.run("/usr/bin/osascript", ["-e", source], timeout: timeout)
        let text = output?.trimmingCharacters(in: .newlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

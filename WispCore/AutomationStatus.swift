import Foundation

/// Automation is granted per target app; this sums up the answers from asking macOS
/// (without a prompt) about the apps Wisp always controls.
public enum AutomationStatus {
    static let allowed: Int32 = 0
    static let notRunning: Int32 = -600  // procNotFound: macOS can't answer for a closed app.

    /// True when every app that answered allows Wisp, false when any denies it or hasn't been
    /// asked yet, nil when none could answer.
    public static func summary(_ results: [Int32]) -> Bool? {
        let answers = results.filter { $0 != notRunning }
        guard !answers.isEmpty else { return nil }
        return answers.allSatisfy { $0 == allowed }
    }
}

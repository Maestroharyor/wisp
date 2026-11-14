import Foundation

/// When the process scan for monitored agents runs: while an Agents view shows, or an agent it
/// found still runs. Views say when they appear and go, but a view can go without saying so (its
/// onDisappear never fires), so each tick also checks that the shelf or window holding the views
/// is on screen. Once neither has been for `grace`, no view can be showing and the count starts
/// over, so the scan stops by itself.
public struct MonitorScan: Equatable, Sendable {
    public static let grace: TimeInterval = 60

    public enum Step: Equatable, Sendable {
        /// Read the process table now.
        case scan
        /// Skip this tick but keep the loop: a view may still be on screen.
        case wait
        /// Nothing wants the scan; end the loop.
        case stop
    }

    private var viewers = 0
    private var hiddenSince: Date?

    public init() {}

    public mutating func viewAppeared() {
        viewers += 1
        hiddenSince = nil
    }

    public mutating func viewDisappeared() {
        viewers = max(0, viewers - 1)
    }

    /// Whether a loop should run. `tracking` is an agent found earlier that still runs.
    public func wanted(tracking: Bool) -> Bool { viewers > 0 || tracking }

    /// What the loop does at `now`. `surfaceVisible` is the shelf or window being on screen.
    public mutating func tick(surfaceVisible: Bool, tracking: Bool, now: Date) -> Step {
        if surfaceVisible {
            hiddenSince = nil
        } else if viewers > 0 {
            let since = hiddenSince ?? now
            hiddenSince = since
            if now.timeIntervalSince(since) >= Self.grace {
                viewers = 0
                hiddenSince = nil
            }
        }
        if tracking || (viewers > 0 && surfaceVisible) { return .scan }
        return viewers > 0 ? .wait : .stop
    }
}

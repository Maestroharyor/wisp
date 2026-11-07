import Foundation
import Observation
import WispCore

/// Lists and runs the user's Shortcuts through the `shortcuts` command-line tool.
@MainActor
@Observable
final class ShortcutsRunner {
    private(set) var available: [String] = []
    private(set) var running: String?
    var onNotice: (String, String) -> Void = { _, _ in }

    @ObservationIgnored private var lastRefresh: Date?

    private static let tool = "/usr/bin/shortcuts"

    /// For the shelf page, which rebuilds on every switch. Settings call `refresh` so a
    /// Shortcut made a moment ago shows up there.
    func refreshIfStale() {
        guard RefreshRule.shortcuts.isDue(lastRefresh: lastRefresh, now: .now) else { return }
        refresh()
    }

    func refresh() {
        Task {
            let output = (try? await ProcessRunner.run(Self.tool, ["list"])) ?? ""
            available = ShortcutList.parse(output)
            // A failed or empty list is asked for again next time rather than kept for five minutes.
            lastRefresh = available.isEmpty ? nil : .now
        }
    }

    func run(_ name: String) {
        guard running == nil else { return }
        running = name
        Task {
            let ok = (try? await ProcessRunner.run(Self.tool, ["run", name])) != nil
            running = nil
            onNotice(ok ? "checkmark.circle.fill" : "xmark.circle.fill", ok ? name : "\(name) failed")
        }
    }
}

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

    private static let tool = "/usr/bin/shortcuts"

    func refresh() {
        Task {
            let output = (try? await ProcessRunner.run(Self.tool, ["list"])) ?? ""
            available = ShortcutList.parse(output)
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

import Foundation
import OSLog
import WispCore

/// Runs the user's Drop Actions on dropped files, one process after another, and reports
/// the result as a notice. Never logs file names or command lines.
@MainActor
final class DropActionRunner {
    var onNotice: (String, String) -> Void = { _, _ in }
    private let log = Logger(subsystem: "com.maestro.wisp", category: "drop-actions")

    func run(_ action: DropAction, on urls: [URL]) {
        guard let runs = action.invocations(for: urls.map(\.path)) else {
            onNotice("xmark.circle.fill", "\(action.name) can't run")
            return
        }
        Task {
            let failure = await Self.perform(runs)
            if let failure {
                log.notice("drop action failed: \(failure, privacy: .public)")
                onNotice("xmark.circle.fill", "\(action.name) failed")
            } else {
                onNotice("checkmark.circle.fill", action.name)
            }
        }
    }

    /// Nil on success, otherwise a short reason without user data.
    private nonisolated static func perform(_ runs: [[String]]) async -> String? {
        for argv in runs {
            guard let program = argv.first else { continue }
            do {
                _ = try await ProcessRunner.run(
                    program, Array(argv.dropFirst()), timeout: .seconds(300), maxOutput: 64 << 10,
                    environment: ProcessRunner.userEnvironment)
            } catch let failure as ProcessRunner.Failure {
                return "exit \(failure.status)"
            } catch is ProcessRunner.TimedOut {
                return "timed out"
            } catch {
                return "could not start"
            }
        }
        return nil
    }
}

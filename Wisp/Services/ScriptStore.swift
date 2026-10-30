import Foundation
import Observation
import WispCore

/// Runs the Script widget's command and keeps its latest output. Runs only while the
/// widget is on screen (the view drives it), so a closed shelf costs nothing.
@MainActor
@Observable
final class ScriptStore {
    private(set) var lines: [String] = []
    private(set) var problem: String?
    private(set) var ranAt: Date?
    private(set) var running = false
    /// The command the current output belongs to, so a new command never shows old output.
    @ObservationIgnored private var ranCommand: String?

    /// Runs `command` now unless output from the last `interval` seconds is still fresh.
    func refresh(command: String, interval: Double, force: Bool = false) async {
        if command != ranCommand {
            lines = []
            problem = nil
            ranAt = nil
        }
        if !force, let ranAt, Date.now.timeIntervalSince(ranAt) < interval { return }
        guard !running else { return }
        guard let words = CommandLineText.split(command), let program = words.first else {
            lines = []
            problem = command.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "Close the quote in the command."
            return
        }
        running = true
        defer { running = false }
        let head = program.hasPrefix("/") ? program : "/usr/bin/env"
        let arguments = program.hasPrefix("/") ? Array(words.dropFirst()) : words
        do {
            let output = try await ProcessRunner.run(
                head, arguments, timeout: .seconds(15), maxOutput: 32 << 10,
                environment: ProcessRunner.userEnvironment, includeErrors: true)
            lines = ScriptOutput.lines(from: output, limit: 4)
            problem = nil
        } catch let failure as ProcessRunner.Failure {
            lines = ScriptOutput.lines(from: failure.output, limit: 3)
            problem = "Exited with \(failure.status)"
        } catch is ProcessRunner.TimedOut {
            problem = "Took longer than 15 seconds"
        } catch {
            problem = "Couldn't start the command"
        }
        ranAt = .now
        ranCommand = command
    }
}

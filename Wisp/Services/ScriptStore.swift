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
    /// The command most recently asked for; it can change while another one is running.
    @ObservationIgnored private var wantedCommand: String?

    private struct Outcome {
        /// Nil keeps the output already shown (a timeout says nothing new).
        var lines: [String]?
        var problem: String?
    }

    /// Runs `command` now unless output from the last `interval` seconds is still fresh.
    func refresh(command: String, interval: Double, force: Bool = false) async {
        wantedCommand = command
        if command != ranCommand {
            lines = []
            problem = nil
            ranAt = nil
        }
        if !force, let ranAt, Date.now.timeIntervalSince(ranAt) < interval { return }
        // A run in progress picks up the new command when it finishes.
        guard !running else { return }
        running = true
        defer { running = false }
        var current = command
        while true {
            let outcome = await run(current)
            guard let wanted = wantedCommand, wanted != current else {
                if let fresh = outcome.lines { lines = fresh }
                problem = outcome.problem
                ranAt = .now
                ranCommand = current
                return
            }
            // The command changed while this one ran; its output belongs to nothing on screen.
            current = wanted
        }
    }

    private func run(_ command: String) async -> Outcome {
        guard let words = CommandLineText.split(command), let program = words.first else {
            let empty = command.trimmingCharacters(in: .whitespaces).isEmpty
            return Outcome(lines: [], problem: empty ? nil : "Close the quote in the command.")
        }
        let head = program.hasPrefix("/") ? program : "/usr/bin/env"
        let arguments = program.hasPrefix("/") ? Array(words.dropFirst()) : words
        do {
            let output = try await ProcessRunner.run(
                head, arguments, timeout: .seconds(15), maxOutput: 32 << 10,
                environment: ProcessRunner.userEnvironment, includeErrors: true)
            return Outcome(lines: ScriptOutput.lines(from: output, limit: 4))
        } catch let failure as ProcessRunner.Failure {
            return Outcome(
                lines: ScriptOutput.lines(from: failure.output, limit: 3), problem: "Exited with \(failure.status)")
        } catch is ProcessRunner.TimedOut {
            return Outcome(lines: nil, problem: "Took longer than 15 seconds")
        } catch {
            return Outcome(lines: nil, problem: "Couldn't start the command")
        }
    }
}

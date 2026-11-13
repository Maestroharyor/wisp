import Foundation
import WispCore

/// `wisp-agent statusline`: Claude Code's statusLine command. Forwards the session snapshot
/// to Wisp without waiting, then prints the bar: Wisp's own, the user's chained command's
/// output (`--chain '<command>'`), or nothing (`--quiet`). `--saved '<command>'` only keeps
/// the user's displaced bar for when Wisp's is turned off. The bar never depends on Wisp
/// running, and every path exits 0.
enum StatusLineCommand {
    /// `appID` is the app this helper ships in, whose settings colour the context bar.
    static func run(
        arguments: [String], socketPath: String, terminal: String?, environment: [String: String], appID: String?
    ) -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let process = AgentProcess.ownerOfThisProcess()
        let context = TerminalContext(
            environment: environment, tty: process.flatMap { TerminalContext.controllingTTY(of: $0.pid) })
        if let message = AgentProtocol.envelope(
            kind: .statusline, source: .claude, terminal: terminal, process: process, context: context,
            payload: input)
        {
            SocketSend.send(message, to: socketPath, timeout: 0.05)
        }
        if let chained = value(after: "--chain", in: arguments) {
            FileHandle.standardOutput.write(runShell(chained, input: input))
        } else if !arguments.contains("--quiet") {
            let thresholds = contextThresholds(appID: appID)
            FileHandle.standardOutput.write(
                Data((bar(for: input, environment: environment, thresholds: thresholds) + "\n").utf8))
        }
        exit(0)
    }

    static func bar(
        for input: Data, environment: [String: String], thresholds: ContextUsage.Thresholds = .standard
    ) -> String {
        let snapshot = StatusLineSnapshot.decode(input)
        let branch =
            snapshot.branch == nil
            ? GitHead.branch(cwd: snapshot.cwd, read: { try? String(contentsOfFile: $0, encoding: .utf8) }) : nil
        return StatusBarRenderer.bar(for: snapshot, branch: branch, environment: environment, thresholds: thresholds)
    }

    /// Wisp's Warn at and Critical at, read from its settings; the defaults when it has none.
    private static func contextThresholds(appID: String?) -> ContextUsage.Thresholds {
        guard let appID else { return .standard }
        return .stored { key in
            var valid: DarwinBoolean = false
            let value = CFPreferencesGetAppIntegerValue(key as CFString, appID as CFString, &valid)
            return valid.boolValue ? Double(value) : nil
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        zip(arguments, arguments.dropFirst()).first { $0.0 == flag }?.1
    }

    /// The user's own bar, given the same stdin. Like Claude Code, a failed run shows nothing.
    private static func runShell(_ command: String, input: Data) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        do {
            try process.run()
        } catch {
            return Data()
        }
        // Snapshots are a few KB, well inside the pipe buffer, so this write can't block.
        try? stdin.fileHandleForWriting.write(contentsOf: input)
        try? stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? output : Data()
    }
}

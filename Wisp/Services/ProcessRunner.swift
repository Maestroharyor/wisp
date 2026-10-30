import Foundation

/// Runs a command off the main thread and returns what it printed.
enum ProcessRunner {
    struct Failure: Error {
        let status: Int32
        /// What it printed before failing, so callers can show a reason.
        let output: String
    }

    struct TimedOut: Error {}

    /// GUI apps get a bare PATH; add the usual install places so `{tool}` resolves the way
    /// it does in Terminal.
    static var userEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin"]
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = ([path] + extra).joined(separator: ":")
        return environment
    }

    /// Output past `maxOutput` bytes is dropped (the process keeps running), and a process
    /// still going after `timeout` is stopped.
    static func run(
        _ path: String, _ arguments: [String], timeout: Duration? = nil, maxOutput: Int = 4 << 20,
        environment: [String: String]? = nil, includeErrors: Bool = false
    ) async throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = output
        process.standardError = includeErrors ? output : FileHandle.nullDevice
        let collected = OutputBuffer(limit: maxOutput)
        // Read as it arrives; waiting until exit would hang once the pipe buffer fills.
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                collected.append(data)
            }
        }

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                output.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
                return
            }
            if let timeout {
                Task.detached {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning {
                        collected.timedOut = true
                        process.terminate()
                    }
                }
            }
        }
        output.fileHandleForReading.readabilityHandler = nil
        if let rest = try? output.fileHandleForReading.readToEnd() { collected.append(rest) }
        if collected.timedOut { throw TimedOut() }
        let text = collected.text
        guard status == 0 else { throw Failure(status: status, output: text) }
        return text
    }
}

/// Collects a child's output from the pipe's reading thread.
private final class OutputBuffer: @unchecked Sendable {
    // Safe: every access goes through `lock`.
    private let lock = NSLock()
    private var data = Data()
    private var flagged = false
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ chunk: Data) {
        lock.withLock {
            let room = limit - data.count
            if room > 0 { data.append(chunk.prefix(room)) }
        }
    }

    var timedOut: Bool {
        get { lock.withLock { flagged } }
        set { lock.withLock { flagged = newValue } }
    }

    var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}

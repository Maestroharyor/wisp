import Darwin
import Foundation
import WispCore

/// `wisp status`, `wisp watch` and `wisp spend`: asks Wisp over its socket and prints the
/// answer. What gets printed is built by `AgentCLI`; this is only the I/O.
enum CLICommand {
    private static let timeout: TimeInterval = 2

    static func run(_ command: AgentCLI.Command, socketPath: String, environment: [String: String]) -> Never {
        switch command {
        case .help:
            print(AgentCLI.usage, terminator: "")
            exit(0)
        case .invalid(let message):
            fail(message + "\n\n" + AgentCLI.usage, code: 2)
        case .status(let json):
            let report = fetch(.status, socketPath: socketPath)
            print(json ? AgentCLI.json(report) : AgentCLI.table(report, width: width(environment)), terminator: "")
            exit(0)
        case .spend(let json):
            let report = fetch(.spend, socketPath: socketPath)
            print(json ? AgentCLI.json(report) : AgentCLI.spend(report), terminator: "")
            exit(0)
        case .watch:
            watch(socketPath: socketPath, environment: environment)
        }
    }

    private enum Outcome {
        case report(AgentReport)
        case problem(String)
    }

    private static func ask(_ query: AgentQuery, socketPath: String) -> Outcome {
        guard let message = AgentProtocol.envelope(kind: .query, source: .claude, terminal: nil, payload: query.payload)
        else { return .problem(AgentCLI.tooOld) }
        switch SocketSend.request(message, to: socketPath, timeout: timeout) {
        case .notRunning: return .problem(AgentCLI.notRunning)
        case .timedOut: return .problem("Wisp didn't answer.")
        case .data(let data):
            return AgentReport.decode(data).map(Outcome.report) ?? .problem(AgentCLI.tooOld)
        }
    }

    private static func fetch(_ query: AgentQuery, socketPath: String) -> AgentReport {
        switch ask(query, socketPath: socketPath) {
        case .report(let report): return report
        case .problem(let message): fail(message, code: 1)
        }
    }

    /// Redraws every second on the alternate screen until Ctrl-C, which puts the terminal back.
    private static func watch(socketPath: String, environment: [String: String]) -> Never {
        let leave = "\u{1B}[?25h\u{1B}[?1049l"
        print("\u{1B}[?1049h\u{1B}[?25l", terminator: "")
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler {
            print(leave, terminator: "")
            fflush(stdout)
            exit(0)
        }
        interrupt.resume()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler {
            let body: String
            switch ask(.status, socketPath: socketPath) {
            case .report(let report): body = AgentCLI.table(report, width: width(environment))
            // Wisp may come back; keep trying.
            case .problem(let message): body = message + "\n"
            }
            let clock = Date.now.formatted(date: .omitted, time: .standard)
            print("\u{1B}[H\u{1B}[2J" + "wisp watch · \(clock) · Ctrl-C to stop\n\n" + body, terminator: "")
            fflush(stdout)
        }
        timer.resume()
        // Keep both sources alive for as long as the main queue runs.
        withExtendedLifetime((interrupt, timer)) { dispatchMain() }
    }

    /// The terminal's width: the window size, then `COLUMNS`, then 100.
    private static func width(_ environment: [String: String]) -> Int {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
        return environment["COLUMNS"].flatMap(Int.init) ?? 100
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data((message.hasSuffix("\n") ? message : message + "\n").utf8))
        exit(code)
    }
}

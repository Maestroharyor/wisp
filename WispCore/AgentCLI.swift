import Foundation

/// The `wisp` command line: parsing and everything it prints, so the helper only does the I/O.
public enum AgentCLI {
    public enum Command: Equatable, Sendable {
        case status(json: Bool)
        case watch
        case spend(json: Bool)
        case help
        /// A usage error, with the message to print.
        case invalid(String)
    }

    /// The command `arguments` (argv, program name first) ask for, or nil for a hook call.
    /// Hooks run `wisp-agent` with no command (or `--source codex`), so anything this
    /// doesn't know under that name stays a hook call; under the `wisp` link it's an error.
    public static func parse(arguments: [String]) -> Command? {
        let program = URL(fileURLWithPath: arguments.first ?? "").lastPathComponent
        let asWisp = program == linkName
        let rest = Array(arguments.dropFirst())
        guard let name = rest.first else { return asWisp ? .help : nil }
        let options = Array(rest.dropFirst())
        let command: Command
        switch name {
        case "status": command = .status(json: options.contains("--json"))
        case "spend": command = .spend(json: options.contains("--json"))
        case "watch": command = .watch
        case "help", "--help", "-h": command = .help
        default: return asWisp ? .invalid("Unknown command: \(name)") : nil
        }
        let allowed: Set<String> = command == .watch || command == .help ? [] : ["--json"]
        if let bad = options.first(where: { !allowed.contains($0) }) { return .invalid("Unknown option: \(bad)") }
        return command
    }

    public static let linkName = "wisp"

    public static let usage = """
        Usage: wisp <command>

          status [--json]  Live coding agent sessions
          watch            The same, updated every second (Ctrl-C to stop)
          spend [--json]   Spend today and over the last 7 days, by project
          help             This help

        Reads from Wisp, which must be running.

        """
    public static let notRunning = "Wisp isn't running."
    public static let tooOld = "This Wisp is too old for this command; update Wisp."

    // MARK: Status

    /// The sessions as a table no wider than `width`.
    public static func table(_ report: AgentReport, width: Int) -> String {
        var out = ""
        if report.sessions.isEmpty {
            out = "No live sessions.\n"
        } else {
            let header = ["PROJECT", "BRANCH", "AGENT", "STATE", "MODEL", "CTX", "COST", "TOOL", "TIME"]
            let rows = report.sessions.map(cells)
            var widths = header.indices.map { column in
                ([header[column]] + rows.map { $0[column] }).map(\.count).max() ?? 0
            }
            // Tool, then project, then branch give up space until the table fits.
            let gaps = (header.count - 1) * 2
            for (column, least) in [(7, 12), (0, 10), (1, 8)] {
                let over = widths.reduce(gaps, +) - width
                guard over > 0 else { break }
                widths[column] = max(least, widths[column] - over)
            }
            for line in [header] + rows {
                let padded = line.indices.map { column in
                    let cell = cut(line[column], to: widths[column])
                    return column == line.count - 1
                        ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
                }
                out += padded.joined(separator: "  ") + "\n"
            }
        }
        if let hidden = report.hidden { out += "\nDetails hidden \(hidden).\n" }
        return out
    }

    private static func cells(_ row: AgentReport.Row) -> [String] {
        let tool = row.tool.map { tool in row.toolSeconds.map { "\(tool) · \(AgentSession.time($0))" } ?? tool }
        return [
            row.project, row.branch ?? "-", row.agent.split(separator: " ").first.map(String.init) ?? row.agent,
            row.state, row.model ?? "-", row.contextPercent.map { "\(Int($0.rounded()))%" } ?? "-",
            row.cost.map { money($0, estimate: !row.costIsReal) } ?? "-", tool ?? "-",
            row.turnSeconds.map(AgentSession.time) ?? "-",
        ]
    }

    // MARK: Spend

    /// Today and the week with a 7-day bar, then the week by project.
    public static func spend(_ report: AgentReport) -> String {
        guard let spend = report.spend else { return "" }
        // Spend comes partly from Wisp's estimates, so it's always marked as one.
        var out = "Today   \(money(spend.today))\n"
        out += "7 days  \(money(spend.week))  \(bars(spend.days))\n"
        guard !spend.projects.isEmpty else { return out }
        let name = max("PROJECT".count, spend.projects.map(\.project.count).max() ?? 0)
        let today = max("TODAY".count, spend.projects.map { money($0.today).count }.max() ?? 0)
        out += "\n" + "PROJECT".padding(toLength: name, withPad: " ", startingAt: 0) + "  "
        out += "TODAY".padding(toLength: today, withPad: " ", startingAt: 0) + "  7 DAYS\n"
        for project in spend.projects {
            out += project.project.padding(toLength: name, withPad: " ", startingAt: 0) + "  "
            out += money(project.today).padding(toLength: today, withPad: " ", startingAt: 0) + "  "
            out += money(project.week) + "\n"
        }
        return out
    }

    static func bars(_ values: [Double]) -> String {
        let levels = Array("▁▂▃▄▅▆▇█")
        let top = values.max() ?? 0
        return String(
            values.map { value in
                guard top > 0 else { return levels[0] }
                return levels[min(levels.count - 1, Int((value / top * Double(levels.count - 1)).rounded()))]
            })
    }

    // MARK: JSON

    public static func json(_ report: AgentReport) -> String {
        report.encoded(pretty: true).map { String(decoding: $0, as: UTF8.self) + "\n" } ?? "{}\n"
    }

    private static func money(_ dollars: Double, estimate: Bool = true) -> String {
        (estimate ? "~" : "") + String(format: "$%.2f", dollars)
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(max(0, limit - 1))) + "…"
    }
}

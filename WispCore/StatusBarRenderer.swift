import Foundation

/// The one-line terminal bar `wisp-agent statusline` prints:
/// `◆ wisp  main  ▕████████░░▏ 78%  Opus  $0.41  +120 −34`.
/// Segments that don't fit the terminal are dropped from the right.
public enum StatusBarRenderer {
    public struct Input: Equatable, Sendable {
        public var project: String
        public var branch: String?
        public var contextPercent: Double?
        public var model: String?
        public var cost: Double?
        public var linesAdded: Int
        public var linesRemoved: Int

        public init(
            project: String, branch: String? = nil, contextPercent: Double? = nil, model: String? = nil,
            cost: Double? = nil, linesAdded: Int = 0, linesRemoved: Int = 0
        ) {
            self.project = project
            self.branch = branch
            self.contextPercent = contextPercent
            self.model = model
            self.cost = cost
            self.linesAdded = linesAdded
            self.linesRemoved = linesRemoved
        }

        public init(snapshot: StatusLineSnapshot, branch: String?) {
            self.init(
                project: snapshot.project, branch: snapshot.branch ?? branch, contextPercent: snapshot.contextPercent,
                model: snapshot.model, cost: snapshot.cost, linesAdded: snapshot.linesAdded ?? 0,
                linesRemoved: snapshot.linesRemoved ?? 0)
        }
    }

    /// A run of text and its 256-colour code (nil: the terminal's own colour).
    public struct Span: Equatable, Sendable {
        public let text: String
        public let color: Int?
    }

    static let separator = "  "
    static let barCells = 10

    /// The bar `wisp-agent statusline` prints for a snapshot, honouring the terminal's
    /// `COLUMNS` and `NO_COLOR` (set and not empty means plain text, per no-color.org).
    /// `branch` is the one read from `.git/HEAD`; a worktree branch in the snapshot wins.
    public static func bar(for snapshot: StatusLineSnapshot, branch: String?, environment: [String: String]) -> String {
        let noColor = environment["NO_COLOR"].map { !$0.isEmpty } ?? false
        return render(
            Input(snapshot: snapshot, branch: branch), columns: environment["COLUMNS"].flatMap(Int.init),
            color: !noColor)
    }

    /// The bar's text. `columns` nil means no width limit; `color` false gives plain text
    /// (`NO_COLOR`).
    public static func render(_ input: Input, columns: Int?, color: Bool) -> String {
        line(input, columns: columns).map { span in
            guard color, let code = span.color else { return span.text }
            return "\u{1B}[38;5;\(code)m\(span.text)\u{1B}[0m"
        }.joined()
    }

    /// The spans that fit in `columns`, separators included, for the bar and its preview.
    public static func line(_ input: Input, columns: Int?) -> [Span] {
        var kept = segments(input)
        while kept.count > 1, let columns, width(kept) > columns { kept.removeLast() }
        if let columns, let first = kept.first, width(kept) > columns {
            kept = [truncated(first, to: columns)]
        }
        var result: [Span] = []
        for (index, segment) in kept.enumerated() {
            if index > 0 { result.append(Span(text: separator, color: nil)) }
            result += segment
        }
        return result
    }

    static func segments(_ input: Input) -> [[Span]] {
        var result: [[Span]] = [
            [
                Span(text: "◆", color: cubeColor(hue: ProjectColor.hue(for: input.project))),
                Span(text: " " + input.project, color: nil),
            ]
        ]
        if let branch = input.branch, !branch.isEmpty { result.append([Span(text: branch, color: 245)]) }
        if let percent = input.contextPercent {
            let filled = min(barCells, max(0, Int((percent / 100 * Double(barCells)).rounded())))
            let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: barCells - filled)
            result.append([Span(text: "▕\(bar)▏ \(Int(percent.rounded()))%", color: contextColor(percent))])
        }
        if let model = input.model, !model.isEmpty { result.append([Span(text: model, color: nil)]) }
        if let cost = input.cost { result.append([Span(text: costText(cost), color: nil)]) }
        if input.linesAdded > 0 || input.linesRemoved > 0 {
            result.append([
                Span(text: "+\(input.linesAdded)", color: 114), Span(text: " ", color: nil),
                Span(text: "−\(input.linesRemoved)", color: 174),
            ])
        }
        return result
    }

    static func costText(_ cost: Double) -> String {
        cost >= 100 ? "$\(Int(cost.rounded()))" : String(format: "$%.2f", cost)
    }

    /// Wisp violet below 70%, amber to 89%, red from 90%.
    static func contextColor(_ percent: Double) -> Int {
        switch ContextUsage.level(percent) {
        case .normal: 105
        case .warning: 214
        case .critical: 203
        }
    }

    /// The xterm 6×6×6 colour cube entry nearest a hue at the saturation and brightness the
    /// app uses for project colours (0.5, 1).
    static func cubeColor(hue: Double) -> Int {
        let (r, g, b) = rgb(hue: hue, saturation: 0.5, brightness: 1)
        let level = { (value: Double) in Int((value * 5).rounded()) }
        return 16 + 36 * level(r) + 6 * level(g) + level(b)
    }

    /// An xterm 256-colour code as RGB (0...1), for drawing the bar's preview in Settings.
    /// Codes below 16 depend on the terminal's theme, so they read as mid grey.
    public static func rgb(code: Int) -> (red: Double, green: Double, blue: Double) {
        switch code {
        case 16...231:
            let levels: [Double] = [0, 95, 135, 175, 215, 255]
            let index = code - 16
            return (levels[index / 36] / 255, levels[index / 6 % 6] / 255, levels[index % 6] / 255)
        case 232...255:
            let grey = Double(8 + 10 * (code - 232)) / 255
            return (grey, grey, grey)
        default:
            return (0.5, 0.5, 0.5)
        }
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (Double, Double, Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let fraction = sector - sector.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch Int(sector) % 6 {
        case 0: return (brightness, t, p)
        case 1: return (q, brightness, p)
        case 2: return (p, brightness, t)
        case 3: return (p, q, brightness)
        case 4: return (t, p, brightness)
        default: return (brightness, p, q)
        }
    }

    private static func width(_ segments: [[Span]]) -> Int {
        segments.reduce(0) { $0 + $1.reduce(0) { $0 + $1.text.count } } + max(0, segments.count - 1) * separator.count
    }

    private static func truncated(_ segment: [Span], to columns: Int) -> [Span] {
        var remaining = max(columns, 1)
        var result: [Span] = []
        for span in segment where remaining > 0 {
            if span.text.count <= remaining {
                result.append(span)
                remaining -= span.text.count
            } else {
                result.append(Span(text: String(span.text.prefix(remaining - 1)) + "…", color: span.color))
                remaining = 0
            }
        }
        return result
    }
}

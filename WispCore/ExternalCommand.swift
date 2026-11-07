import Foundation

/// A live activity a script, Shortcut or link posts to the notch.
public struct ExternalActivity: Equatable, Sendable {
    public let id: String
    public var title: String
    public var symbol: String
    /// 0 to 1, or nil for an activity without a measurable end.
    public var progress: Double?
    /// Who last started or updated it. Set by `ExternalActivities`, not by the caller.
    public var source: ExternalActivitySource?

    public init(id: String, title: String, symbol: String, progress: Double? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.progress = progress
    }

    public static let defaultSymbol = "bolt.fill"

    /// The SF Symbols an outside caller may use. A fixed list keeps the notch from showing
    /// whatever a web page passes in. All are from SF Symbols 3 or earlier, so macOS 14 has them.
    public static let symbols = [
        "bolt.fill", "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "terminal.fill",
        "testtube.2", "shippingbox.fill", "server.rack", "cloud.fill", "icloud.and.arrow.up.fill",
        "arrow.down.circle.fill", "arrow.up.circle.fill", "arrow.triangle.2.circlepath", "paperplane.fill",
        "doc.fill", "folder.fill", "film.fill", "music.note", "photo.fill", "printer.fill", "clock.fill",
        "hourglass", "bell.fill", "star.fill", "flag.fill", "checkmark.circle.fill", "xmark.octagon.fill",
        "exclamationmark.triangle.fill", "sparkles", "cup.and.saucer.fill",
    ]

    static let titleLimit = 60
    static let idLimit = 64
}

/// The way an outside activity reached Wisp, shown in its details.
public enum ExternalActivitySource: Equatable, Sendable {
    /// A `wisp://activity` link.
    case link
    /// `wisp activity` in a terminal or script, over the helper's socket.
    case command
    case shortcut

    /// The details view's line about where it came from.
    public var label: String {
        switch self {
        case .link: "From a wisp:// link"
        case .command: "From the wisp command"
        case .shortcut: "From Shortcuts"
        }
    }
}

/// Changes to an activity; nil leaves a field as it was.
public struct ExternalActivityUpdate: Equatable, Sendable {
    public let id: String
    public var title: String?
    public var symbol: String?
    public var progress: Double?

    public init(id: String, title: String?, symbol: String?, progress: Double?) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.progress = progress
    }
}

public enum ExternalActivityAction: Equatable, Sendable {
    case start(ExternalActivity)
    case update(ExternalActivityUpdate)
    case end(id: String)

    public var id: String {
        switch self {
        case .start(let activity): activity.id
        case .update(let update): update.id
        case .end(let id): id
        }
    }
}

/// Pages a link or Shortcut can open; the same names profiles store for their page.
public enum ExternalPage: String, CaseIterable, Sendable {
    case home
    case tray
    case media
    case widgets
}

public struct ExternalCommandError: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) { self.message = message }
}

/// What the `wisp activity` command, a `wisp://` link or the socket's `activity` message asks
/// Wisp to do. There is deliberately no case that approves or denies an agent's request: any
/// web page can open a link, so links (and everything parsed here) stay harmless.
public enum ExternalCommand: Equatable, Sendable {
    case activity(ExternalActivityAction)
    case openPage(ExternalPage)
    case switchProfile(String)
    case startTimer(minutes: Int)

    /// `wisp` for Wisp and `wisp-dev` for Wisp Dev, so the two builds don't fight over links.
    public static let schemes: Set<String> = ["wisp", "wisp-dev"]
    public static let timerMinutes = 1...180
    static let profileNameLimit = 60

    public typealias Parsed = Result<ExternalCommand, ExternalCommandError>

    // MARK: Command line

    /// `start|update|end --id <id> [--title <text>] [--symbol <name>] [--progress <0-1>]`,
    /// the arguments after `wisp activity`.
    public static func parse(activityArguments arguments: [String]) -> Parsed {
        guard let verb = arguments.first else { return .failure(ExternalCommandError(missingAction)) }
        var fields: [String: String] = [:]
        var rest = arguments.dropFirst()[...]
        while let option = rest.popFirst() {
            guard option.hasPrefix("--") else { return .failure(ExternalCommandError("Unknown option: \(option)")) }
            let parts = option.dropFirst(2).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts.first ?? "")
            guard ActivityField(rawValue: name) != nil else {
                return .failure(ExternalCommandError("Unknown option: \(option)"))
            }
            if parts.count == 2 {
                fields[name] = String(parts[1])
            } else if let value = rest.popFirst() {
                fields[name] = value
            } else {
                return .failure(ExternalCommandError("--\(name) needs a value."))
            }
        }
        return activity(verb: verb, fields: fields, prefix: "--").map(ExternalCommand.activity)
    }

    // MARK: Links

    /// `wisp://open?page=tray`, `wisp://profile?name=Work`, `wisp://timer?minutes=25` and
    /// `wisp://activity/start?id=…&title=…&symbol=…&progress=…` (also `update` and `end`).
    public static func parse(url: URL) -> Parsed {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .failure(ExternalCommandError("Not a Wisp link.")) }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        let host = (components.host ?? "").lowercased()
        let path = components.path.split(separator: "/").map(String.init)
        switch host {
        case "open":
            let name = query["page"] ?? path.first ?? ExternalPage.home.rawValue
            guard let page = ExternalPage(rawValue: name.lowercased()) else {
                return .failure(ExternalCommandError("Unknown page: \(name)"))
            }
            return .success(.openPage(page))
        case "profile":
            return profileName(query["name"]).map(ExternalCommand.switchProfile)
        case "timer":
            return timerMinutes(query["minutes"]).map { .startTimer(minutes: $0) }
        case "activity":
            guard let verb = path.first else { return .failure(ExternalCommandError(missingAction)) }
            let known = query.filter { ActivityField(rawValue: $0.key) != nil }
            return activity(verb: verb, fields: known, prefix: "").map(ExternalCommand.activity)
        default:
            return .failure(ExternalCommandError("Unknown link: \(host.isEmpty ? "(none)" : host)"))
        }
    }

    /// A profile name as typed: trimmed, not empty, not absurdly long.
    public static func profileName(_ raw: String?) -> Result<String, ExternalCommandError> {
        let name = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(ExternalCommandError("Missing name.")) }
        guard name.count <= profileNameLimit else { return .failure(ExternalCommandError("Unknown profile.")) }
        return .success(name)
    }

    static func timerMinutes(_ raw: String?) -> Result<Int, ExternalCommandError> {
        guard let value = raw.flatMap({ Int($0) }), timerMinutes.contains(value) else {
            return .failure(
                ExternalCommandError(
                    "minutes must be a whole number from \(timerMinutes.lowerBound) to \(timerMinutes.upperBound)."))
        }
        return .success(value)
    }

    // MARK: Activity fields

    enum ActivityField: String {
        case id
        case title
        case symbol
        case progress
    }

    static let missingAction = "Missing action: start, update or end."

    /// For Shortcuts: the same rules, with fields named as in a link (`id`, `title`, ...).
    public static func parse(activityVerb verb: String, fields: [String: String]) -> Result<
        ExternalActivityAction, ExternalCommandError
    > {
        activity(verb: verb, fields: fields, prefix: "")
    }

    /// One set of rules for every way in. `prefix` is how the caller spells a field in its
    /// messages ("--id" on the command line, "id" in a link).
    static func activity(verb: String, fields: [String: String], prefix: String) -> Result<
        ExternalActivityAction, ExternalCommandError
    > {
        func fail(_ message: String) -> Result<ExternalActivityAction, ExternalCommandError> {
            .failure(ExternalCommandError(message))
        }
        guard ["start", "update", "end"].contains(verb) else { return fail("Unknown action: \(verb)") }
        guard let id = fields["id"], !id.isEmpty else { return fail("Missing \(prefix)id.") }
        guard id.count <= ExternalActivity.idLimit, id.allSatisfy(isIDCharacter) else {
            return fail(
                "\(prefix)id may only use letters, digits, dots, dashes and underscores, "
                    + "up to \(ExternalActivity.idLimit) characters.")
        }
        if verb == "end" { return .success(.end(id: id)) }

        let title = fields["title"].map(cleanTitle)
        if let title, title.count > ExternalActivity.titleLimit {
            return fail("\(prefix)title can be at most \(ExternalActivity.titleLimit) characters.")
        }
        if let title, title.unicodeScalars.count > titleScalarLimit {
            return fail("\(prefix)title has too many accents or joined symbols.")
        }
        let symbol = fields["symbol"]
        if let symbol, !ExternalActivity.symbols.contains(symbol) {
            return fail("Unknown symbol: \(symbol). Run wisp activity --help for the list.")
        }
        var progress: Double?
        if let raw = fields["progress"] {
            guard let value = Double(raw), value.isFinite, (0...1).contains(value) else {
                return fail("\(prefix)progress must be a number from 0 to 1.")
            }
            progress = value
        }
        let named = title.flatMap { $0.isEmpty ? nil : $0 }
        if verb == "update" {
            return .success(.update(ExternalActivityUpdate(id: id, title: named, symbol: symbol, progress: progress)))
        }
        guard let named else { return fail("Missing \(prefix)title.") }
        return .success(
            .start(
                ExternalActivity(
                    id: id, title: named, symbol: symbol ?? ExternalActivity.defaultSymbol, progress: progress)))
    }

    /// Room for 60 characters built from several scalars (flags, skin tones), but not for one
    /// "character" stacked with hundreds of combining marks.
    static let titleScalarLimit = 4 * ExternalActivity.titleLimit

    /// Zero-width non-joiner and joiner, and the tag characters that spell subdivision flags.
    private static let keptFormatScalars: Set<UInt32> = Set([0x200C, 0x200D]).union(0xE0020...0xE007F)

    /// Control characters and line or paragraph separators become spaces, and format characters
    /// (bidi overrides, invisible marks) go, so a title can't break the pill's line or reorder the
    /// text around it. Joiners and tag characters stay, since emoji sequences (and subdivision
    /// flags such as Scotland's) and some scripts need them.
    static func cleanTitle(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: scalars.append(" ")
            case .format where !keptFormatScalars.contains(scalar.value): continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isIDCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "._-".contains(character))
    }
}

// MARK: Socket payload

extension ExternalActivityAction {
    /// The `activity` message's payload: `{"action": "start", "id": …, "title": …, …}`.
    public var payload: Data {
        var fields: [String: JSONValue] = ["id": .string(id)]
        switch self {
        case .start(let activity):
            fields["action"] = .string("start")
            fields["title"] = .string(activity.title)
            fields["symbol"] = .string(activity.symbol)
            if let progress = activity.progress { fields["progress"] = .number(progress) }
        case .update(let update):
            fields["action"] = .string("update")
            if let title = update.title { fields["title"] = .string(title) }
            if let symbol = update.symbol { fields["symbol"] = .string(symbol) }
            if let progress = update.progress { fields["progress"] = .number(progress) }
        case .end:
            fields["action"] = .string("end")
        }
        return (try? JSONEncoder().encode(JSONValue.object(fields))) ?? Data()
    }

    /// Checked with the same rules as the command line, since anything can write to the socket.
    public static func parse(json: JSONValue) -> Result<ExternalActivityAction, ExternalCommandError> {
        guard let verb = json["action"]?.stringValue else {
            return .failure(ExternalCommandError(ExternalCommand.missingAction))
        }
        var fields: [String: String] = [:]
        for name in ["id", "title", "symbol"] {
            if let value = json[name]?.stringValue { fields[name] = value }
        }
        if let progress = json["progress"] {
            // A number or a string both read as text, so a bad value fails the range check.
            fields["progress"] = progress.doubleValue.map { String($0) } ?? progress.stringValue ?? "?"
        }
        return ExternalCommand.activity(verb: verb, fields: fields, prefix: "")
    }
}

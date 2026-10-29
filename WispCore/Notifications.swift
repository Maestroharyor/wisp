import Foundation

/// One delivered notification, decoded from the system notification database.
public struct NotificationRecord: Sendable, Equatable, Identifiable {
    public let recID: Int64
    public let appID: String
    public let title: String
    public let subtitle: String
    public let body: String
    public let threadID: String?
    public let date: Date
    public let uuid: String?

    public var id: Int64 { recID }

    public init(
        recID: Int64, appID: String, title: String, subtitle: String, body: String, threadID: String?, date: Date,
        uuid: String?
    ) {
        self.recID = recID
        self.appID = appID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadID = threadID
        self.date = date
        self.uuid = uuid
    }

    /// The `record.data` column is a binary plist: the app id, a date and a request
    /// dictionary with abbreviated keys (titl, subt, body, thre).
    private struct Payload: Decodable {
        struct Request: Decodable {
            let titl: String?
            let subt: String?
            let body: String?
            let thre: String?
        }
        let app: String?
        let req: Request?
    }

    /// Returns nil for undecodable records or ones with nothing to show.
    /// `deliveredDate` is seconds since 2001 (Core Data reference date).
    public static func decode(recID: Int64, appIdentifier: String, data: Data, deliveredDate: Double, uuid: String?)
        -> NotificationRecord?
    {
        guard let payload = try? PropertyListDecoder().decode(Payload.self, from: data) else { return nil }
        let title = payload.req?.titl ?? ""
        let body = payload.req?.body ?? ""
        guard !title.isEmpty || !body.isEmpty else { return nil }
        return NotificationRecord(
            recID: recID,
            appID: appIdentifier.isEmpty ? (payload.app ?? "") : appIdentifier,
            title: title,
            subtitle: payload.req?.subt ?? "",
            body: body,
            threadID: payload.req?.thre,
            date: Date(timeIntervalSinceReferenceDate: deliveredDate),
            uuid: uuid
        )
    }
}

/// Turns database polls into notifications worth showing: locks a baseline on the
/// first read so history never replays, advances a cursor, limits floods, and drops
/// blocked apps, Wisp's own notifications and duplicates.
public struct NotificationFeed: Sendable {
    public private(set) var cursor: Int64?
    public var maxPerPoll: Int
    public var blockedApps: Set<String>
    public let ownBundleID: String
    private var recentUUIDs: [String] = []

    public init(ownBundleID: String, maxPerPoll: Int = 3, blockedApps: Set<String> = []) {
        self.ownBundleID = ownBundleID
        self.maxPerPoll = maxPerPoll
        self.blockedApps = blockedApps
    }

    /// `baseline` is the newest record id at the time of the first read; it is only
    /// used while no cursor is set.
    public mutating func ingest(_ records: [NotificationRecord], baseline: Int64?) -> [NotificationRecord] {
        guard let current = cursor else {
            cursor = max(baseline ?? 0, records.map(\.recID).max() ?? 0)
            return []
        }
        let fresh = records.filter { $0.recID > current }.sorted { $0.recID < $1.recID }
        cursor = max(current, fresh.last?.recID ?? current)

        var shown: [NotificationRecord] = []
        for record in fresh where record.appID != ownBundleID && !blockedApps.contains(record.appID) {
            if let uuid = record.uuid {
                guard !recentUUIDs.contains(uuid) else { continue }
                recentUUIDs.append(uuid)
            }
            shown.append(record)
        }
        if recentUUIDs.count > 200 { recentUUIDs.removeFirst(recentUUIDs.count - 200) }
        return Array(shown.suffix(maxPerPoll))
    }
}

public enum ReplyChannel: String, Sendable, Equatable {
    case iMessage
    case whatsApp
    case telegram
}

public enum ReplyRouting {
    public static func channel(for bundleID: String) -> ReplyChannel? {
        switch bundleID {
        case "com.apple.MobileSMS", "com.apple.iChat": .iMessage
        case "net.whatsapp.WhatsApp", "desktop.WhatsApp", "WhatsApp": .whatsApp
        case "ru.keepcoder.Telegram", "org.telegram.desktop": .telegram
        default: nil
        }
    }
}

public enum AppleScriptText {
    /// A double-quoted AppleScript string literal.
    public static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// A recent Messages chat, read from chat.db.
public struct ChatCandidate: Sendable, Equatable {
    public let guid: String
    public let lastIncomingText: String?
    public let displayName: String?
    public let handle: String?

    public init(guid: String, lastIncomingText: String?, displayName: String?, handle: String?) {
        self.guid = guid
        self.lastIncomingText = lastIncomingText
        self.displayName = displayName
        self.handle = handle
    }
}

/// Finds which Messages chat a notification came from.
public enum ChatMatcher {
    /// Order of evidence: the exact message text, then the group name, then the
    /// sender handle. Candidates are newest first.
    public static func pick(_ chats: [ChatCandidate], title: String, body: String) -> String? {
        if !body.isEmpty, let chat = chats.first(where: { $0.lastIncomingText == body }) { return chat.guid }
        if let chat = chats.first(where: { $0.displayName.map { !$0.isEmpty && $0 == title } ?? false }) {
            return chat.guid
        }
        return chats.first { $0.handle.map { !$0.isEmpty && $0 == title } ?? false }?.guid
    }
}

/// Focus (Do Not Disturb) state from ~/Library/DoNotDisturb/DB.
public struct FocusModeState: Sendable, Equatable {
    public let isOn: Bool
    public let name: String?
    public let symbol: String?

    public init(isOn: Bool, name: String?, symbol: String?) {
        self.isOn = isOn
        self.name = name
        self.symbol = symbol
    }

    private struct Assertions: Decodable {
        struct Entry: Decodable {
            struct Record: Decodable {
                struct Details: Decodable { let assertionDetailsModeIdentifier: String? }
                let assertionDetails: Details?
            }
            let storeAssertionRecords: [Record]?
        }
        let data: [Entry]
    }

    private struct Modes: Decodable {
        struct Entry: Decodable {
            struct Configuration: Decodable {
                struct Mode: Decodable {
                    let name: String?
                    let symbolImageName: String?
                }
                let mode: Mode?
            }
            let modeConfigurations: [String: Configuration]?
        }
        let data: [Entry]
    }

    /// Nil when the assertions file cannot be read as expected.
    public static func parse(assertions: Data, modes: Data?) -> FocusModeState? {
        guard let parsed = try? JSONDecoder().decode(Assertions.self, from: assertions) else { return nil }
        let records = parsed.data.flatMap { $0.storeAssertionRecords ?? [] }
        guard let identifier = records.compactMap({ $0.assertionDetails?.assertionDetailsModeIdentifier }).first
        else { return FocusModeState(isOn: false, name: nil, symbol: nil) }

        let configuration =
            modes
            .flatMap { try? JSONDecoder().decode(Modes.self, from: $0) }?
            .data.compactMap { $0.modeConfigurations?[identifier]?.mode }.first
        let isDefault = identifier.hasSuffix("donotdisturb.mode.default")
        return FocusModeState(
            isOn: true,
            name: configuration?.name ?? (isDefault ? "Do Not Disturb" : "Focus"),
            symbol: configuration?.symbolImageName ?? "moon.fill"
        )
    }
}

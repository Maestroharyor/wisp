import Foundation
import WispCore

/// Reads the macOS notification store (needs Full Disk Access). The store's location
/// has moved between releases, so each known path is tried in turn.
final class NotificationDatabase {
    private static let relativePaths = [
        "Library/Group Containers/group.com.apple.usernoted/db2/db",
        "Library/Group Containers/group.com.apple.UserNotifications/db2/db",
        "Library/Application Support/NotificationCenter/db2/db",
    ]

    private let reader: SQLiteReader

    init?() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard
            let reader = Self.relativePaths.lazy
                .map({ home.appendingPathComponent($0).path })
                .compactMap(SQLiteReader.init(path:))
                .first
        else { return nil }
        self.reader = reader
    }

    /// The newest record id, used to lock the baseline on first read.
    func latestRecordID() throws -> Int64 {
        try reader.query("SELECT MAX(rec_id) FROM record").first?.first?.int64 ?? 0
    }

    func records(after recID: Int64, limit: Int64 = 50) throws -> [NotificationRecord] {
        let rows = try reader.query(
            """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date, r.uuid
            FROM record r JOIN app a ON r.app_id = a.app_id
            WHERE r.rec_id > ? ORDER BY r.rec_id ASC LIMIT ?
            """,
            [recID, limit]
        )
        return rows.compactMap { row in
            guard row.count == 5, let id = row[0].int64, let data = row[2].data else { return nil }
            return NotificationRecord.decode(
                recID: id,
                appIdentifier: row[1].string ?? "",
                data: data,
                deliveredDate: row[3].double ?? Date.now.timeIntervalSinceReferenceDate,
                uuid: row[4].data.map { $0.map { String(format: "%02x", $0) }.joined() } ?? row[4].string
            )
        }
    }
}

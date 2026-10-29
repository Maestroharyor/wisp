import Foundation
import SQLite3

/// Minimal read-only SQLite access for system databases (notifications, Messages).
/// Opens with SQLITE_OPEN_READONLY, which works alongside the owner's WAL writer.
final class SQLiteReader {
    enum Value {
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob(Data)
        case null

        var int64: Int64? {
            if case .integer(let value) = self { return value }
            return nil
        }

        var double: Double? {
            switch self {
            case .real(let value): value
            case .integer(let value): Double(value)
            default: nil
            }
        }

        var string: String? {
            if case .text(let value) = self { return value }
            return nil
        }

        var data: Data? {
            if case .blob(let value) = self { return value }
            return nil
        }
    }

    private var handle: OpaquePointer?

    /// Nil when the file is missing or unreadable (usually: no Full Disk Access).
    init?(path: String) {
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        // Opening can succeed lazily; touch the schema to confirm access.
        guard (try? query("SELECT 1 FROM sqlite_master LIMIT 1")) != nil else {
            sqlite3_close(handle)
            return nil
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    struct QueryError: Error {
        let message: String
    }

    func query(_ sql: String, _ arguments: [Int64] = []) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw QueryError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, argument) in arguments.enumerated() {
            sqlite3_bind_int64(statement, Int32(index + 1), argument)
        }

        var rows: [[Value]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { throw QueryError(message: String(cString: sqlite3_errmsg(handle))) }
            rows.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
        }
        return rows
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, index).map { .text(String(cString: $0)) } ?? .null
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard let bytes = sqlite3_column_blob(statement, index), count > 0 else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }
}

import AppKit
import WispCore

/// Replies to iMessage/SMS notifications: finds the chat in ~/Library/Messages/chat.db
/// (Full Disk Access) and sends through the Messages app's AppleScript interface.
@MainActor
enum MessagesReply {
    static func send(_ text: String, title: String, body: String) -> Bool {
        let quotedText = AppleScriptText.quoted(text)
        if let guid = chatGUID(title: title, body: body) {
            return run("tell application \"Messages\" to send \(quotedText) to chat id \(AppleScriptText.quoted(guid))")
        }
        // No chat match: a phone number or email in the title can be messaged directly.
        guard title.contains("@") || title.contains(where: \.isNumber) else { return false }
        return run(
            """
            tell application "Messages"
                set target to participant \(AppleScriptText.quoted(title)) of (1st account whose service type = iMessage)
                send \(quotedText) to target
            end tell
            """)
    }

    private static func chatGUID(title: String, body: String) -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
            .path
        guard let reader = SQLiteReader(path: path),
            let rows = try? reader.query(
                """
                SELECT c.guid, m.text, c.display_name, h.id
                FROM message m
                JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
                JOIN chat c ON c.ROWID = cmj.chat_id
                LEFT JOIN handle h ON h.ROWID = m.handle_id
                WHERE m.is_from_me = 0
                ORDER BY m.date DESC LIMIT 60
                """)
        else { return nil }

        var seen: Set<String> = []
        let candidates = rows.compactMap { row -> ChatCandidate? in
            guard row.count == 4, let guid = row[0].string, seen.insert(guid).inserted else { return nil }
            return ChatCandidate(
                guid: guid, lastIncomingText: row[1].string, displayName: row[2].string, handle: row[3].string)
        }
        return ChatMatcher.pick(candidates, title: title, body: body)
    }

    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}

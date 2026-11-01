import AppKit
import WispCore

/// Replies to iMessage/SMS notifications: finds the chat in ~/Library/Messages/chat.db
/// (Full Disk Access) and sends through the Messages app's AppleScript interface.
/// Both run off the main thread: the first send waits on the Automation prompt, and the
/// event taps on the main run loop would stall (and be disabled) meanwhile.
enum MessagesReply {
    static func send(_ text: String, title: String, body: String) async -> Bool {
        let quotedText = AppleScriptText.quoted(text)
        if let guid = await Task.detached(operation: { chatGUID(title: title, body: body) }).value {
            return await run(
                "tell application \"Messages\" to send \(quotedText) to chat id \(AppleScriptText.quoted(guid))")
        }
        // No chat match: a phone number or email in the title can be messaged directly.
        guard title.contains("@") || title.contains(where: \.isNumber) else { return false }
        return await run(
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

    /// osascript exits non-zero when the send fails. The limit leaves time to answer the
    /// Automation prompt on first use.
    private static func run(_ source: String) async -> Bool {
        do {
            _ = try await ProcessRunner.run("/usr/bin/osascript", ["-e", source], timeout: .seconds(60))
            return true
        } catch {
            return false
        }
    }
}

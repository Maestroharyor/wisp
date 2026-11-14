import Foundation

/// Where an edit sits in its file, so an approval card can number its lines. The app reads the
/// file (inside the session's folder, at most `maxBytes`, never in private mode) and hands the
/// text here. Nothing of the file is kept, logged or sent.
public enum FileAnchor {
    /// Files larger than this aren't read.
    public static let maxBytes = 2 * 1024 * 1024

    /// The file and the text an edit replaces in it.
    public struct Target: Equatable, Sendable {
        public let path: String
        public let text: String
    }

    /// What to look for: an Edit's `old_string`, or a MultiEdit's when it has one edit. Nil for
    /// anything else, including `replace_all`, which changes every copy and so has no one place.
    public static func target(tool: String, input: JSONValue?) -> Target? {
        guard let path = input?["file_path"]?.stringValue else { return nil }
        let edit: JSONValue?
        switch tool {
        case "Edit":
            edit = input
        case "MultiEdit":
            guard case .array(let edits) = input?["edits"], edits.count == 1 else { return nil }
            edit = edits.first
        default:
            return nil
        }
        if case .bool(true)? = edit?["replace_all"] { return nil }
        guard let text = edit?["old_string"]?.stringValue, !text.isEmpty else { return nil }
        return Target(path: path, text: text)
    }

    /// The 1-based line where `needle` starts in `text`; nil when it's missing, found more than
    /// once, empty, or the text is over `maxBytes`. Compared as bytes, so "\r\n" counts as one line.
    public static func line(of needle: String, in text: String) -> Int? {
        let haystack = Data(text.utf8)
        let target = Data(needle.utf8)
        guard !target.isEmpty, haystack.count <= maxBytes, let first = haystack.range(of: target) else { return nil }
        let rest = (first.lowerBound + 1)..<haystack.endIndex
        if !rest.isEmpty, haystack.range(of: target, in: rest) != nil { return nil }
        let newline = UInt8(ascii: "\n")
        return haystack[haystack.startIndex..<first.lowerBound].reduce(1) { $0 + ($1 == newline ? 1 : 0) }
    }

    /// `path` made absolute against `folder`; nil when it's blank, or relative with no folder.
    public static func absolute(_ path: String, folder: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") { return trimmed }
        guard folder.hasPrefix("/") else { return nil }
        return (folder as NSString).appendingPathComponent(trimmed)
    }

    /// Whether `path` (absolute, with ".." resolved) lies under `folder`. The folder itself and
    /// the root folder don't count, so a session started in "/" reads nothing.
    public static func isInside(_ path: String, folder: String) -> Bool {
        guard path.hasPrefix("/"), folder.hasPrefix("/") else { return false }
        let base = (folder as NSString).standardizingPath
        let file = (path as NSString).standardizingPath
        guard base != "/" else { return false }
        return file.hasPrefix(base + "/")
    }

    /// The path for a card's title: relative to the project, else with the home folder as "~".
    public static func relativePath(_ path: String, folder: String, home: String = NSHomeDirectory()) -> String {
        guard path.hasPrefix("/") else { return path }
        let file = (path as NSString).standardizingPath
        if isInside(file, folder: folder) {
            return String(file.dropFirst((folder as NSString).standardizingPath.count + 1))
        }
        if isInside(file, folder: home) {
            return "~/" + String(file.dropFirst((home as NSString).standardizingPath.count + 1))
        }
        return file
    }

    /// A diff's number, counted from 1 within the edit, as a line in the file once the edit's
    /// first line (`anchor`) is known.
    public static func shift(_ number: Int?, anchor: Int?) -> Int? {
        guard let number, let anchor else { return nil }
        return number + anchor - 1
    }
}

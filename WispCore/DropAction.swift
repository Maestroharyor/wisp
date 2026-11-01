import Foundation

/// A user-defined thing to do with dropped files: run a Shortcut, or a command.
/// Commands are split into arguments here and run directly, never through a shell, so
/// file names with spaces or quotes can't change what runs.
public struct DropAction: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: Codable, Equatable, Sendable {
        /// A command line; `{file}` runs it once per file, `{files}` passes them all,
        /// and without either the files are appended.
        case command(String)
        /// A Shortcut by name, given each file as input.
        case shortcut(String)
    }

    public var id: UUID
    public var name: String
    public var symbol: String
    public var kind: Kind

    public init(id: UUID = UUID(), name: String, symbol: String = "bolt.fill", kind: Kind) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.kind = kind
    }

    /// What's wrong with the action as typed, or nil when it can run.
    public var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the action a name." }
        switch kind {
        case .command(let line):
            guard let words = CommandLineText.split(line) else { return "Close the quote." }
            return words.isEmpty ? "Type a command." : nil
        case .shortcut(let shortcut):
            return shortcut.trimmingCharacters(in: .whitespaces).isEmpty ? "Choose a Shortcut." : nil
        }
    }

    /// The processes to run, as full argument lists (executable first). Nil when the
    /// action isn't valid or there are no files.
    public func invocations(for files: [String]) -> [[String]]? {
        guard problem == nil, !files.isEmpty else { return nil }
        switch kind {
        case .shortcut(let shortcut):
            return [["/usr/bin/shortcuts", "run", shortcut] + files.flatMap { ["-i", $0] }]
        case .command(let line):
            guard let words = CommandLineText.split(line), let program = words.first else { return nil }
            // Bare names are found on PATH by env, the way Terminal would find them.
            let head = program.hasPrefix("/") ? [program] : ["/usr/bin/env", program]
            let arguments = Array(words.dropFirst())
            if arguments.contains(where: { $0.contains(Self.eachFile) }) {
                return files.map { file in
                    head + arguments.map { $0.replacingOccurrences(of: Self.eachFile, with: file) }
                }
            }
            if arguments.contains(Self.allFiles) {
                return [head + arguments.flatMap { $0 == Self.allFiles ? files : [$0] }]
            }
            return [head + arguments + files]
        }
    }

    public static let eachFile = "{file}"
    public static let allFiles = "{files}"
}

/// Splits a command line into words with shell-style quoting ('single', "double" and
/// backslash escapes) and nothing else: no globbing, variables, pipes or substitution.
public enum CommandLineText {
    public static func split(_ line: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                // As in a POSIX shell, a backslash inside double quotes only escapes these.
                if quote == "\"", !"$`\"\\\n".contains(character) { current.append("\\") }
                if character != "\n" || quote != "\"" { current.append(character) }
                escaped = false
                inWord = true
                continue
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\", open == "\"" {
                    escaped = true
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "\\":
                escaped = true
            case "\"", "'":
                quote = character
                inWord = true
            case " ", "\t", "\n":
                if inWord {
                    words.append(current)
                    current = ""
                    inWord = false
                }
            default:
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if inWord { words.append(current) }
        return words
    }
}

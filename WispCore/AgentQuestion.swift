import Foundation

/// One question from Claude Code's AskUserQuestion tool, answered from the notch.
public struct AgentQuestion: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let label: String
        public let detail: String?
    }

    public let question: String
    /// The short chip Claude gives the question ("Colour").
    public let header: String
    public let options: [Option]
    public let multiSelect: Bool

    /// The questions in the tool's input; malformed ones are skipped.
    public static func parse(_ input: JSONValue?) -> [AgentQuestion] {
        guard case .array(let items) = input?["questions"] else { return [] }
        return items.compactMap { item in
            guard let question = item["question"]?.stringValue, !question.isEmpty else { return nil }
            var options: [Option] = []
            if case .array(let raw) = item["options"] {
                options = raw.compactMap { option in
                    option["label"]?.stringValue.map { Option(label: $0, detail: option["description"]?.stringValue) }
                }
            }
            var multiSelect = false
            if case .bool(let value) = item["multiSelect"] { multiSelect = value }
            return AgentQuestion(
                question: question, header: item["header"]?.stringValue ?? "", options: options,
                multiSelect: multiSelect)
        }
    }

    /// The answer Claude Code expects: picked labels joined with commas, then any text typed
    /// under "Other". Nil when nothing was given.
    public static func answer(picked: [String], other: String) -> String? {
        let typed = other.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = picked + (typed.isEmpty ? [] : [typed])
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// The hook's reply answering an AskUserQuestion: an allow whose `updatedInput` carries the
/// original questions and an answer for each, keyed by the question's text.
public enum QuestionReply {
    public static func json(input: JSONValue, answers: [String: String]) -> String? {
        var updated: [String: JSONValue] = ["answers": .object(answers.mapValues(JSONValue.string))]
        updated["questions"] = input["questions"] ?? .array([])
        return PermissionReply.json(allow: true, updatedInput: .object(updated))
    }
}

// Prints the HTML for Sparkle's update window.
// Usage: release-notes <version> <notes-url> < prs.json
// prs.json is an array of {"title": ..., "body": ...} for the pull requests in the release.
// Compiled together with WispCore/ReleaseNotes.swift by release.yml.
import Foundation

struct PullRequest: Decodable {
    let title: String
    let body: String
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: release-notes <version> <notes-url> < prs.json\n".utf8))
    exit(2)
}
do {
    let pulls = try JSONDecoder().decode([PullRequest].self, from: FileHandle.standardInput.readDataToEndOfFile())
    let entries = pulls.compactMap { ReleaseNotes.Entry(title: $0.title, body: $0.body) }
    print(ReleaseNotes.html(version: arguments[1], entries: entries, notesURL: arguments[2]), terminator: "")
} catch {
    FileHandle.standardError.write(Data("release-notes: \(error)\n".utf8))
    exit(1)
}

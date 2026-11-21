import XCTest

@testable import WispCore

final class SettingsFileWriterTests: XCTestCase {
    private var folder = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wisp-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    private func text(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    func testANewFileIsWrittenWithItsFolderAndNoCopies() throws {
        let url = folder.appendingPathComponent(".claude/settings.local.json")
        try SettingsFileWriter.backUpOnce(url)
        try SettingsFileWriter.write(Data("new".utf8), to: url)
        XCTAssertEqual(text(url), "new")
        XCTAssertNil(text(url.appendingPathExtension("wisp-backup")))
        XCTAssertNil(text(url.appendingPathExtension("wisp-previous")))
    }

    func testReplaceWritesWithoutCopies() throws {
        let url = folder.appendingPathComponent(".claude/settings.local.json")
        try SettingsFileWriter.replace(Data("old".utf8), at: url)
        try SettingsFileWriter.replace(Data("new".utf8), at: url)
        XCTAssertEqual(text(url), "new")
        XCTAssertNil(text(url.appendingPathExtension("wisp-backup")))
        XCTAssertNil(text(url.appendingPathExtension("wisp-previous")))
    }

    func testTheFirstBackupKeepsTheOriginalAndLaterOnesDont() throws {
        let url = folder.appendingPathComponent("settings.json")
        try Data("original".utf8).write(to: url)
        try SettingsFileWriter.backUpOnce(url)
        try SettingsFileWriter.write(Data("second".utf8), to: url)
        try SettingsFileWriter.backUpOnce(url)
        try SettingsFileWriter.write(Data("third".utf8), to: url)
        XCTAssertEqual(text(url), "third")
        XCTAssertEqual(text(url.appendingPathExtension("wisp-backup")), "original")
        XCTAssertEqual(text(url.appendingPathExtension("wisp-previous")), "second")
    }

    /// Dotfile managers (stow, chezmoi) keep settings as a link into a repo; writing must go
    /// through the link, not replace it with a plain file.
    func testWritingThroughASymlinkKeepsTheLink() throws {
        let target = folder.appendingPathComponent("dotfiles/settings.json")
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: target)
        let link = folder.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try SettingsFileWriter.write(Data("written".utf8), to: link)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        XCTAssertEqual(text(target), "written")
        XCTAssertEqual(text(link.appendingPathExtension("wisp-previous")), "original")

        try SettingsFileWriter.replace(Data("replaced".utf8), at: link)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
        XCTAssertEqual(text(target), "replaced")
    }

    /// A settings file can hold API keys in its `env` block; its copies must be no more readable.
    func testCopiesKeepTheFilesPermissions() throws {
        let url = folder.appendingPathComponent("settings.json")
        try Data("secret".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        try SettingsFileWriter.backUpOnce(url)
        try SettingsFileWriter.write(Data("next".utf8), to: url)
        try SettingsFileWriter.saveBackup(Data("again".utf8), of: url)
        for copy in ["wisp-backup", "wisp-previous"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.appendingPathExtension(copy).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, copy)
        }
        XCTAssertEqual(text(url.appendingPathExtension("wisp-backup")), "again")
    }
}

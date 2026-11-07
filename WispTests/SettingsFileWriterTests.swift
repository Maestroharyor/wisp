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
}

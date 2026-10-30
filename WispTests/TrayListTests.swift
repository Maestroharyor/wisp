import XCTest

@testable import WispCore

final class TrayListTests: XCTestCase {
    private let a = URL(fileURLWithPath: "/tmp/a.png")
    private let b = URL(fileURLWithPath: "/tmp/b.pdf")
    private let c = URL(fileURLWithPath: "/tmp/c.txt")

    func testAddsNewestFirstWithoutDuplicates() {
        var tray = TrayList()
        tray.add([a, b])
        tray.add([b, c])
        XCTAssertEqual(tray.urls, [c, a, b])
    }

    func testSelectionToggleSelectAllAndRemove() {
        var tray = TrayList()
        tray.add([a, b, c])
        tray.toggleSelection(a)
        XCTAssertEqual(tray.selected, [a])
        tray.selectAll()
        XCTAssertEqual(tray.selected, [a, b, c])
        tray.toggleSelectAll()
        XCTAssertEqual(tray.selected, [])
        tray.toggleSelection(b)
        tray.removeSelected()
        XCTAssertEqual(Set(tray.urls), [a, c])
        XCTAssertEqual(tray.selected, [])
    }

    func testActionTargetsSelectionOrEverything() {
        var tray = TrayList()
        tray.add([a, b])
        XCTAssertEqual(Set(tray.actionTargets), [a, b])
        tray.toggleSelection(a)
        XCTAssertEqual(tray.actionTargets, [a])
    }

    func testPruneMissingFiles() {
        var tray = TrayList()
        tray.add([a, b])
        tray.toggleSelection(a)
        tray.prune { $0 != a }
        XCTAssertEqual(tray.urls, [b])
        XCTAssertEqual(tray.selected, [])
    }

    func testArchiveNaming() {
        XCTAssertEqual(ArchiveNaming.name(for: [a], existing: []), "a.zip")
        XCTAssertEqual(ArchiveNaming.name(for: [a, b], existing: []), "Archive.zip")
        XCTAssertEqual(ArchiveNaming.name(for: [a], existing: ["a.zip"]), "a 2.zip")
        XCTAssertEqual(ArchiveNaming.name(for: [a, b], existing: ["Archive.zip", "Archive 2.zip"]), "Archive 3.zip")
    }

    func testStagedNamesStayUniqueAcrossFolders() {
        let urls = [
            URL(fileURLWithPath: "/a/report.pdf"),
            URL(fileURLWithPath: "/b/report.pdf"),
            URL(fileURLWithPath: "/c/report.pdf"),
            URL(fileURLWithPath: "/c/notes"),
        ]
        XCTAssertEqual(
            ArchiveNaming.stagedNames(for: urls), ["report.pdf", "report 2.pdf", "report 3.pdf", "notes"])
    }

    func testStagedNamesKeepFoldersWithoutExtension() {
        let urls = [URL(fileURLWithPath: "/a/Photos"), URL(fileURLWithPath: "/b/Photos")]
        XCTAssertEqual(ArchiveNaming.stagedNames(for: urls), ["Photos", "Photos 2"])
    }
}

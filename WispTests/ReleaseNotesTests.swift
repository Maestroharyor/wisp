import XCTest

@testable import WispCore

final class ReleaseNotesTests: XCTestCase {
    private let template = """
        ## Summary

        Stuff.

        ## Release note

        <!-- One line for the changelog, written for people who use Wisp. "None" for internal changes. -->
        %@

        ## Checklist

        - [x] Done
        """

    private func body(_ note: String) -> String { template.replacingOccurrences(of: "%@", with: note) }

    func testReadsTheReleaseNoteSection() {
        let note = "Finishing setup opens the notch."
        XCTAssertEqual(ReleaseNotes.note(fromBody: body(note)), note)
    }

    func testEmptyNoneAndCommentOnlyNotesAreNil() {
        XCTAssertNil(ReleaseNotes.note(fromBody: body("")))
        XCTAssertNil(ReleaseNotes.note(fromBody: body("None")))
        XCTAssertNil(ReleaseNotes.note(fromBody: body("none.")))
        XCTAssertNil(ReleaseNotes.note(fromBody: "No sections at all"))
    }

    func testMultilineNotesJoinIntoOneParagraph() {
        XCTAssertEqual(ReleaseNotes.note(fromBody: body("First line\nsecond line.")), "First line second line.")
    }

    func testTypesMapToSections() {
        XCTAssertEqual(ReleaseNotes.Entry(title: "feat: add x (#3)", body: body("X is here."))?.section, .new)
        XCTAssertEqual(ReleaseNotes.Entry(title: "fix(notch): y (#4)", body: body("Y works."))?.section, .fixed)
        XCTAssertEqual(ReleaseNotes.Entry(title: "perf: z", body: body("Z is faster."))?.section, .improved)
        XCTAssertEqual(ReleaseNotes.Entry(title: "feat!: big change", body: body("Big."))?.section, .new)
    }

    func testInternalChangesAreSkipped() {
        for title in ["docs: a", "chore(main): release 0.1.2 (#9)", "ci: b", "test: c", "build: d", "refactor: e"] {
            XCTAssertNil(ReleaseNotes.Entry(title: title, body: body("Something.")), title)
        }
        XCTAssertNil(ReleaseNotes.Entry(title: "not conventional", body: body("Something.")))
    }

    func testAFeatureOrFixWithoutANoteFallsBackToItsTitle() {
        let entry = ReleaseNotes.Entry(title: "fix: permission flow and opening the notch after setup (#8)", body: "")
        XCTAssertEqual(entry?.text, "Permission flow and opening the notch after setup.")
    }

    func testAnExplicitNoneSkipsEvenAFix() {
        XCTAssertNil(ReleaseNotes.Entry(title: "fix: internal tidy (#10)", body: body("None")))
    }

    func testHTMLEscapesNotesAndFormatsCode() {
        let entry = ReleaseNotes.Entry(title: "feat: x", body: body("Use `make run` <script>alert(1)</script> & more."))
        let html = ReleaseNotes.html(version: "0.1.3", entries: [entry].compactMap { $0 }, notesURL: "https://e.x/n")
        XCTAssertTrue(html.contains("<code>make run</code>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; more."))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testAnUnpairedBacktickStaysAsText() {
        XCTAssertEqual(ReleaseNotes.inline("a `b` c `d"), "a <code>b</code> c `d")
    }

    func testSectionsAreOrderedAndEmptyOnesOmitted() {
        let entries = [
            ReleaseNotes.Entry(title: "fix: a", body: body("A fixed.")),
            ReleaseNotes.Entry(title: "feat: b", body: body("B added.")),
        ].compactMap { $0 }
        let html = ReleaseNotes.html(version: "0.1.3", entries: entries, notesURL: "https://e.x/n")
        let new = html.range(of: ">New<")
        let fixed = html.range(of: ">Fixed<")
        XCTAssertNotNil(new)
        XCTAssertNotNil(fixed)
        if let new, let fixed { XCTAssertLessThan(new.lowerBound, fixed.lowerBound) }
        XCTAssertFalse(html.contains(">Improved<"))
        XCTAssertTrue(html.contains("What’s new in Wisp 0.1.3"))
        XCTAssertTrue(html.contains("href=\"https://e.x/n\""))
    }

    func testNoEntriesStillSaysSomething() {
        let html = ReleaseNotes.html(version: "0.1.3", entries: [], notesURL: "https://e.x/n")
        XCTAssertTrue(html.contains("Small fixes and improvements."))
    }
}

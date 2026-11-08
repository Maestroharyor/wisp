import CoreGraphics
import XCTest

@testable import WispCore

final class TextCaptureTests: XCTestCase {
    /// A line of text in Vision's space: normalised, origin at the bottom left.
    private func line(_ text: String, x: CGFloat = 0.1, top: CGFloat, height: CGFloat = 0.05, width: CGFloat = 0.3)
        -> RecognizedLine
    {
        RecognizedLine(text: text, box: CGRect(x: x, y: top - height, width: width, height: height))
    }

    // MARK: Joining lines

    func testJoinsLinesTopToBottom() {
        let lines = [line("second", top: 0.84), line("first", top: 0.9)]
        XCTAssertEqual(CapturedText.join(lines), "first\nsecond")
    }

    func testJoinsWordsOnOneRowLeftToRight() {
        let lines = [line("world", x: 0.5, top: 0.9), line("hello", x: 0.1, top: 0.905)]
        XCTAssertEqual(CapturedText.join(lines), "hello world")
    }

    func testLeavesABlankLineAtAParagraphGap() {
        let lines = [line("one", top: 0.9), line("two", top: 0.84), line("three", top: 0.6)]
        XCTAssertEqual(CapturedText.join(lines), "one\ntwo\n\nthree")
    }

    func testJoinsAWordBrokenByAHyphen() {
        let lines = [line("the recog-", top: 0.9), line("nised text", top: 0.84)]
        XCTAssertEqual(CapturedText.join(lines), "the recognised text")
    }

    func testKeepsAHyphenBeforeACapital() {
        let lines = [line("Wisp-", top: 0.9), line("Core", top: 0.84)]
        XCTAssertEqual(CapturedText.join(lines), "Wisp-\nCore")
    }

    func testDropsEmptyLines() {
        XCTAssertEqual(CapturedText.join([line("  ", top: 0.9), line("kept", top: 0.8)]), "kept")
        XCTAssertEqual(CapturedText.join([]), "")
    }

    func testCleanTidiesSpacesAndBlankLines() {
        XCTAssertEqual(CapturedText.clean("  a\t\tb  \r\n\n\n\nc \u{000C}"), "a b\n\nc")
    }

    // MARK: Codes

    func testWebAddressIsALink() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a?b=1"))
        XCTAssertEqual(ScannedCode(payload: " https://example.com/a?b=1 "), .link(url))
    }

    func testOtherSchemesAreText() {
        XCTAssertEqual(ScannedCode(payload: "javascript:alert(1)"), .text("javascript:alert(1)"))
        XCTAssertEqual(ScannedCode(payload: "https://"), .text("https://"))
    }

    func testEmptyPayloadIsNil() {
        XCTAssertNil(ScannedCode(payload: "  "))
    }

    func testWiFiCodeGivesNetworkAndPassword() {
        XCTAssertEqual(
            ScannedCode(payload: "WIFI:T:WPA;S:Home;P:pass;H:false;;"), .wifi(network: "Home", password: "pass"))
        XCTAssertEqual(
            ScannedCode(payload: "WIFI:T:WPA;S:Home;P:se\\;cret;;"), .wifi(network: "Home", password: "se;cret"))
        XCTAssertEqual(ScannedCode(payload: "WIFI:S:Cafe;T:nopass;;"), .wifi(network: "Cafe", password: nil))
    }

    func testWiFiWithoutNetworkIsText() {
        XCTAssertEqual(ScannedCode(payload: "WIFI:T:WPA;P:x;;"), .text("WIFI:T:WPA;P:x;;"))
    }

    func testCodeCopyTextAndNotice() throws {
        let link = ScannedCode.link(try XCTUnwrap(URL(string: "https://www.example.com/path")))
        XCTAssertEqual(link.copyText, "https://www.example.com/path")
        XCTAssertEqual(link.notice, "Copied link to example.com")
        let wifi = ScannedCode.wifi(network: "Home", password: "secret")
        XCTAssertEqual(wifi.copyText, "secret")
        XCTAssertEqual(wifi.notice, "Copied Wi-Fi password for Home")
        let open = ScannedCode.wifi(network: "Cafe", password: nil)
        XCTAssertEqual(open.copyText, "Cafe")
        XCTAssertEqual(open.notice, "Copied network name; Cafe has no password")
        XCTAssertEqual(ScannedCode.text("ABC-123").notice, "Copied code")
    }

    // MARK: Result

    func testCodeWinsOverText() {
        let result = CaptureResult(lines: [line("Scan me", top: 0.9)], codes: ["https://example.com"])
        XCTAssertEqual(result.copyText, "https://example.com")
        XCTAssertEqual(result.notice, "Copied link to example.com")
    }

    func testSeveralCodesAreCopiedTogether() {
        let result = CaptureResult(lines: [], codes: ["one", "two", "one"])
        XCTAssertEqual(result.copyText, "one\ntwo")
        XCTAssertEqual(result.notice, "Copied 2 codes")
    }

    func testTextResultCountsWords() {
        let result = CaptureResult(lines: [line("hello there", top: 0.9), line("world", top: 0.84)], codes: [])
        XCTAssertEqual(result.copyText, "hello there\nworld")
        XCTAssertEqual(result.notice, "Copied 3 words")
        XCTAssertEqual(CaptureResult(lines: [line("hi", top: 0.9)], codes: []).notice, "Copied 1 word")
    }

    func testNothingFound() {
        let result = CaptureResult(lines: [line(" ", top: 0.9)], codes: [" "])
        XCTAssertNil(result.copyText)
        XCTAssertEqual(result.notice, "No text found")
    }

    // MARK: PDF text

    func testPDFTextJoinsPagesAndHyphens() {
        let text = PDFText.clean(pages: ["Intro-\nduction  here\n", "  ", "Page\u{000C} two"])
        XCTAssertEqual(text, "Introduction here\n\nPage two")
    }

    func testReadsEveryPageOfAShortDocument() {
        XCTAssertEqual(PDFText.pageIndices(count: 3, limit: 10), [0, 1, 2])
        XCTAssertEqual(PDFText.pageIndices(count: 0, limit: 10), [])
    }

    func testReadsTheStartAndEndOfALongDocument() {
        XCTAssertEqual(PDFText.pageIndices(count: 100, limit: 6), [0, 1, 2, 3, 98, 99])
    }

    func testSummaryNoticeNamesTheFile() {
        XCTAssertEqual(PDFText.notice(fileName: "Report.pdf"), "Copied a summary of Report.pdf")
    }

    func testProgressAndPartialNoticesShareTheShownName() {
        let long = String(repeating: "b", count: 50) + ".pdf"
        let shown = String(repeating: "b", count: 39) + "…"
        XCTAssertEqual(PDFText.shownName(long), shown)
        XCTAssertEqual(PDFText.shownName("My  report.pdf"), "My report.pdf")
        XCTAssertEqual(PDFText.progress(fileName: long), "Summarising \(shown)…")
        XCTAssertEqual(PDFText.partialNotice(fileName: "A.pdf"), "Copied a partial summary of A.pdf")
    }

    func testSummaryNoticeCutsALongName() {
        let notice = PDFText.notice(fileName: String(repeating: "a", count: 60) + ".pdf")
        XCTAssertEqual(notice, "Copied a summary of " + String(repeating: "a", count: 39) + "…")
    }

    // MARK: Secrets and quotes

    func testWiFiPasswordIsSecret() {
        XCTAssertTrue(CaptureResult(lines: [], codes: ["WIFI:S:Home;P:secret;;"]).isSecret)
        XCTAssertFalse(CaptureResult(lines: [], codes: ["WIFI:S:Cafe;T:nopass;;"]).isSecret)
        XCTAssertFalse(CaptureResult(lines: [], codes: ["https://example.com"]).isSecret)
        XCTAssertFalse(CaptureResult(lines: [line("text", top: 0.9)], codes: []).isSecret)
    }

    func testWiFiValuesLoseTheirQuotes() {
        XCTAssertEqual(
            ScannedCode(payload: "WIFI:S:\"Home\";P:\"secret\";;"), .wifi(network: "Home", password: "secret"))
    }

    func testCodesAreDedupedOnThePayload() {
        // Different payloads stay separate even when they would copy the same password.
        let result = CaptureResult(lines: [], codes: ["WIFI:S:A;P:x;;", "WIFI:S:B;P:x;;", " WIFI:S:A;P:x;; "])
        XCTAssertEqual(result, .codes([.wifi(network: "A", password: "x"), .wifi(network: "B", password: "x")]))
    }
}

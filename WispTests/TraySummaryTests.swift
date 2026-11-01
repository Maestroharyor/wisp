import XCTest

@testable import WispCore

final class TraySummaryTests: XCTestCase {
    func testFormatsBytesInDecimalUnitsLikeFinder() {
        XCTAssertEqual(TraySummary.bytes(0), "0 B")
        XCTAssertEqual(TraySummary.bytes(999), "999 B")
        XCTAssertEqual(TraySummary.bytes(1_000), "1 KB")
        XCTAssertEqual(TraySummary.bytes(820_400), "820 KB")
        XCTAssertEqual(TraySummary.bytes(3_420_000), "3.4 MB")
        XCTAssertEqual(TraySummary.bytes(12_000_000), "12 MB")
        XCTAssertEqual(TraySummary.bytes(1_500_000_000), "1.5 GB")
        XCTAssertEqual(TraySummary.bytes(9_960), "10 KB", "rounding up to 10 drops the decimal")
        XCTAssertEqual(TraySummary.bytes(999_600), "1 MB", "rounding up to 1000 moves to the next unit")
        XCTAssertEqual(TraySummary.bytes(1_040), "1 KB")
    }

    func testHeaderCountsFilesAndTotalSize() {
        XCTAssertEqual(TraySummary.header(sizes: [1_200_000, 2_200_000], selectedSizes: []), "2 files · 3.4 MB")
        XCTAssertEqual(TraySummary.header(sizes: [500], selectedSizes: []), "1 file · 500 B")
    }

    func testHeaderDescribesTheSelection() {
        XCTAssertEqual(
            TraySummary.header(sizes: [1_200_000, 2_200_000], selectedSizes: [1_200_000]), "1 selected · 1.2 MB")
    }

    func testHeaderLeavesOutUnknownSizes() {
        XCTAssertEqual(TraySummary.header(sizes: [], selectedSizes: [], count: 3), "3 files")
    }

    func testDetailShowsKindAndSize() {
        XCTAssertEqual(TraySummary.detail(pathExtension: "png", size: 1_200_000), "PNG · 1.2 MB")
        XCTAssertEqual(TraySummary.detail(pathExtension: "", size: 40), "File · 40 B")
        XCTAssertEqual(TraySummary.detail(pathExtension: "jpg", size: nil), "JPG")
    }
}

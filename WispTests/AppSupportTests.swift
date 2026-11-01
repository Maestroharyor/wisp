import XCTest

@testable import WispCore

final class AppSupportTests: XCTestCase {
    func testDevelopmentBuildsGetTheirOwnFolder() {
        XCTAssertEqual(AppSupport.folderName(bundleID: "com.ayomideodewale.wisp"), "Wisp")
        XCTAssertEqual(AppSupport.folderName(bundleID: "com.ayomideodewale.wisp.dev"), "Wisp Dev")
        XCTAssertEqual(AppSupport.folderName(bundleID: nil), "Wisp")
    }

    func testSocketPath() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(
            AppSupport.socketURL(home: home, bundleID: "com.ayomideodewale.wisp.dev").path,
            "/Users/me/Library/Application Support/Wisp Dev/agents.sock")
        XCTAssertEqual(
            AppSupport.socketURL(home: home, bundleID: "com.ayomideodewale.wisp").path,
            "/Users/me/Library/Application Support/Wisp/agents.sock")
    }

    func testTheAppAroundAHelper() {
        let helper = URL(fileURLWithPath: "/Applications/Wisp.app/Contents/MacOS/wisp-agent")
        XCTAssertEqual(AppSupport.appBundle(containingHelper: helper).path, "/Applications/Wisp.app")
    }
}

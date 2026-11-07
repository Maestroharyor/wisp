import XCTest

@testable import WispCore

final class ExternalCommandTests: XCTestCase {
    private func url(_ text: String) throws -> URL { try XCTUnwrap(URL(string: text)) }

    private func failure(_ result: Result<ExternalCommand, ExternalCommandError>) -> String? {
        if case .failure(let error) = result { return error.message }
        return nil
    }

    // MARK: Command line

    func testStartReadsEveryOption() {
        let result = ExternalCommand.parse(
            activityArguments: [
                "start", "--id", "build", "--title", "Building Wisp", "--symbol", "hammer.fill",
                "--progress", "0.25",
            ])
        let activity = ExternalActivity(id: "build", title: "Building Wisp", symbol: "hammer.fill", progress: 0.25)
        XCTAssertEqual(result, .success(.activity(.start(activity))))
    }

    func testStartFillsTheDefaultSymbolAndLeavesProgressOut() {
        let result = ExternalCommand.parse(activityArguments: ["start", "--id", "a", "--title", "Upload"])
        let activity = ExternalActivity(id: "a", title: "Upload", symbol: ExternalActivity.defaultSymbol, progress: nil)
        XCTAssertEqual(result, .success(.activity(.start(activity))))
    }

    func testOptionsAcceptTheEqualsForm() {
        let result = ExternalCommand.parse(activityArguments: ["update", "--id=a", "--progress=1"])
        XCTAssertEqual(
            result, .success(.activity(.update(ExternalActivityUpdate(id: "a", title: nil, symbol: nil, progress: 1)))))
    }

    func testEndNeedsOnlyTheID() {
        XCTAssertEqual(
            ExternalCommand.parse(activityArguments: ["end", "--id", "a"]), .success(.activity(.end(id: "a"))))
    }

    func testStartNeedsATitle() {
        XCTAssertEqual(failure(ExternalCommand.parse(activityArguments: ["start", "--id", "a"])), "Missing --title.")
    }

    func testEveryActionNeedsAnID() {
        XCTAssertEqual(failure(ExternalCommand.parse(activityArguments: ["end"])), "Missing --id.")
    }

    func testUnknownActionsAndOptionsAreErrors() {
        XCTAssertEqual(failure(ExternalCommand.parse(activityArguments: [])), "Missing action: start, update or end.")
        XCTAssertEqual(failure(ExternalCommand.parse(activityArguments: ["stop"])), "Unknown action: stop")
        XCTAssertEqual(
            failure(ExternalCommand.parse(activityArguments: ["end", "--id", "a", "--colour", "red"])),
            "Unknown option: --colour")
        XCTAssertEqual(
            failure(ExternalCommand.parse(activityArguments: ["end", "--id"])), "--id needs a value.")
    }

    func testProgressMustBeBetweenZeroAndOne() {
        for bad in ["1.5", "-0.1", "nan", "half"] {
            XCTAssertEqual(
                failure(ExternalCommand.parse(activityArguments: ["update", "--id", "a", "--progress", bad])),
                "--progress must be a number from 0 to 1.", bad)
        }
    }

    func testSymbolsComeFromTheAllowedList() {
        XCTAssertEqual(
            failure(
                ExternalCommand.parse(activityArguments: [
                    "start", "--id", "a", "--title", "x", "--symbol", "apple.logo",
                ])),
            "Unknown symbol: apple.logo. Run wisp activity --help for the list.")
        for symbol in ExternalActivity.symbols {
            let result = ExternalCommand.parse(
                activityArguments: ["start", "--id", "a", "--title", "x", "--symbol", symbol])
            XCTAssertNil(failure(result), symbol)
        }
    }

    func testIDsAreShortAndPlain() {
        XCTAssertEqual(
            failure(ExternalCommand.parse(activityArguments: ["end", "--id", "has space"])),
            "--id may only use letters, digits, dots, dashes and underscores, up to 64 characters.")
        XCTAssertEqual(
            failure(ExternalCommand.parse(activityArguments: ["end", "--id", String(repeating: "a", count: 65)])),
            "--id may only use letters, digits, dots, dashes and underscores, up to 64 characters.")
        XCTAssertNil(failure(ExternalCommand.parse(activityArguments: ["end", "--id", "ci.build-2_x"])))
    }

    func testTitlesAreTrimmedAndCapped() {
        let padded = ExternalCommand.parse(activityArguments: ["start", "--id", "a", "--title", "  Deploy \n"])
        XCTAssertEqual(
            padded,
            .success(
                .activity(.start(ExternalActivity(id: "a", title: "Deploy", symbol: ExternalActivity.defaultSymbol)))))
        XCTAssertEqual(
            failure(ExternalCommand.parse(activityArguments: ["start", "--id", "a", "--title", "   "])),
            "Missing --title.")
        XCTAssertEqual(
            failure(
                ExternalCommand.parse(
                    activityArguments: ["start", "--id", "a", "--title", String(repeating: "x", count: 61)])),
            "--title can be at most 60 characters.")
    }

    private func startTitle(_ title: String) -> String? {
        let result = ExternalCommand.parse(activityArguments: ["start", "--id", "a", "--title", title])
        if case .success(.activity(.start(let activity))) = result { return activity.title }
        return nil
    }

    func testControlCharactersInTitlesBecomeSpaces() {
        XCTAssertEqual(startTitle("Deploy\nprod\tnow"), "Deploy prod now")
        XCTAssertEqual(startTitle("Bell\u{07}"), "Bell")
    }

    // Bidi overrides could make the pill read differently from what was sent.
    func testFormatCharactersInTitlesAreRemoved() {
        XCTAssertEqual(startTitle("abc\u{202E}fdp.exe"), "abcfdp.exe")
        XCTAssertEqual(startTitle("in\u{2066}vis\u{2069}ible\u{200B}\u{FEFF}"), "invisible")
        XCTAssertNil(startTitle("\u{202E}\u{200B}"))
    }

    func testEmojiSequencesKeepTheirJoiner() {
        let family = "\u{1F469}\u{200D}\u{1F4BB} Coding"
        XCTAssertEqual(startTitle(family), family)
    }

    // Persian and other scripts use the non-joiner inside words.
    func testNonJoinerStays() {
        let word = "\u{0645}\u{06CC}\u{200C}\u{062E}\u{0648}\u{0627}\u{0647}\u{0645}"
        XCTAssertEqual(startTitle(word), word)
    }

    func testTagCharactersOfSubdivisionFlagsStay() {
        let scotland = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F} Deploy"
        XCTAssertEqual(startTitle(scotland), scotland)
    }

    func testLineAndParagraphSeparatorsBecomeSpaces() {
        XCTAssertEqual(startTitle("One\u{2028}two\u{2029}three"), "One two three")
    }

    func testTitlesAreCappedByScalarsToo() {
        // One character with hundreds of combining marks.
        let stacked = "a" + String(repeating: "\u{0301}", count: 300)
        XCTAssertEqual(stacked.count, 1)
        XCTAssertEqual(
            failure(ExternalCommand.parse(activityArguments: ["start", "--id", "a", "--title", stacked])),
            "--title has too many accents or joined symbols.")
    }

    // MARK: URLs

    func testURLOpensAPage() throws {
        XCTAssertEqual(ExternalCommand.parse(url: try url("wisp://open?page=tray")), .success(.openPage(.tray)))
        XCTAssertEqual(ExternalCommand.parse(url: try url("wisp://open")), .success(.openPage(.home)))
        XCTAssertEqual(failure(ExternalCommand.parse(url: try url("wisp://open?page=secret"))), "Unknown page: secret")
    }

    func testURLSwitchesProfile() throws {
        XCTAssertEqual(
            ExternalCommand.parse(url: try url("wisp://profile?name=Deep%20work")),
            .success(.switchProfile("Deep work")))
        XCTAssertEqual(failure(ExternalCommand.parse(url: try url("wisp://profile"))), "Missing name.")
    }

    func testURLStartsATimer() throws {
        XCTAssertEqual(
            ExternalCommand.parse(url: try url("wisp://timer?minutes=25")), .success(.startTimer(minutes: 25)))
        for bad in ["0", "181", "ten", ""] {
            XCTAssertEqual(
                failure(ExternalCommand.parse(url: try url("wisp://timer?minutes=\(bad)"))),
                "minutes must be a whole number from 1 to 180.", bad)
        }
    }

    func testURLShowsAnActivityWithTheSameRulesAsTheCommandLine() throws {
        let start = try url("wisp://activity/start?id=build&title=Building&symbol=hammer.fill&progress=0.5")
        XCTAssertEqual(
            ExternalCommand.parse(url: start),
            .success(
                .activity(
                    .start(ExternalActivity(id: "build", title: "Building", symbol: "hammer.fill", progress: 0.5)))))
        XCTAssertEqual(
            ExternalCommand.parse(url: try url("wisp://activity/end?id=build")), .success(.activity(.end(id: "build"))))
        XCTAssertEqual(
            failure(ExternalCommand.parse(url: try url("wisp://activity/start?id=a&title=x&progress=2"))),
            "progress must be a number from 0 to 1.")
        XCTAssertEqual(
            failure(ExternalCommand.parse(url: try url("wisp://activity"))), "Missing action: start, update or end.")
    }

    func testDevelopmentBuildsHaveTheirOwnScheme() throws {
        XCTAssertEqual(ExternalCommand.parse(url: try url("wisp-dev://open?page=media")), .success(.openPage(.media)))
        XCTAssertEqual(failure(ExternalCommand.parse(url: try url("https://open?page=media"))), "Not a Wisp link.")
    }

    // Any web page can open a wisp:// link, so none may answer an agent's request.
    func testURLsCanNeverApproveOrDeny() throws {
        for text in ["wisp://approve", "wisp://deny", "wisp://allow", "wisp://agent/approve?id=x", "wisp://answer"] {
            XCTAssertNotNil(failure(ExternalCommand.parse(url: try url(text))), text)
        }
    }

    // MARK: Socket payload

    func testPayloadRoundTrips() throws {
        let actions: [ExternalActivityAction] = [
            .start(ExternalActivity(id: "a", title: "Tests", symbol: "testtube.2", progress: 0.1)),
            .update(ExternalActivityUpdate(id: "a", title: nil, symbol: nil, progress: 0.9)),
            .end(id: "a"),
        ]
        for action in actions {
            let json = try JSONDecoder().decode(JSONValue.self, from: action.payload)
            XCTAssertEqual(ExternalActivityAction.parse(json: json), .success(action))
        }
    }

    func testPayloadIsValidatedLikeTheCommandLine() throws {
        let json = try JSONDecoder().decode(
            JSONValue.self, from: Data(#"{"action":"start","id":"a","title":"x","symbol":"rm -rf"}"#.utf8))
        XCTAssertEqual(
            ExternalActivityAction.parse(json: json),
            .failure(ExternalCommandError("Unknown symbol: rm -rf. Run wisp activity --help for the list.")))
    }
}

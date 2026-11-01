import XCTest

@testable import WispCore

final class AgentPrivacyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 0)

    func testModesDecideWhenDetailsHide() {
        XCTAssertFalse(AgentPrivacy.hidden(mode: .never, onCall: true, manual: false))
        XCTAssertTrue(AgentPrivacy.hidden(mode: .duringCalls, onCall: true, manual: false))
        XCTAssertFalse(AgentPrivacy.hidden(mode: .duringCalls, onCall: false, manual: false))
        XCTAssertTrue(AgentPrivacy.hidden(mode: .always, onCall: false, manual: false))
    }

    func testManualHideAlwaysWins() {
        for mode in AgentPrivacy.Mode.allCases {
            XCTAssertTrue(AgentPrivacy.hidden(mode: mode, onCall: false, manual: true))
        }
    }

    func testDuringCallsIsTheDefault() {
        XCTAssertEqual(AgentPrivacy.Mode.default, .duringCalls)
        XCTAssertEqual(AgentPrivacy.Mode(rawValue: "always"), .always)
    }

    func testOnCallNeedsTheMicAndACall() {
        XCTAssertTrue(AgentPrivacy.onCall(micInUse: true, inputBundleIDs: ["us.zoom.xos"], meetingInProgress: false))
        XCTAssertTrue(
            AgentPrivacy.onCall(micInUse: true, inputBundleIDs: ["com.google.Chrome"], meetingInProgress: true))
        XCTAssertFalse(
            AgentPrivacy.onCall(micInUse: true, inputBundleIDs: ["com.apple.VoiceMemos"], meetingInProgress: false))
        XCTAssertFalse(AgentPrivacy.onCall(micInUse: false, inputBundleIDs: ["us.zoom.xos"], meetingInProgress: true))
    }

    /// Meet, Teams and Zoom run in browsers without a calendar event, so for hiding a browser
    /// on the mic counts as a call: hiding during dictation beats showing during a call.
    func testABrowserOnTheMicCountsWithoutAMeeting() {
        for browser in ["com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox"] {
            XCTAssertTrue(AgentPrivacy.onCall(micInUse: true, inputBundleIDs: [browser], meetingInProgress: false))
        }
        XCTAssertFalse(
            AgentPrivacy.onCall(micInUse: false, inputBundleIDs: ["com.apple.Safari"], meetingInProgress: false))
    }

    func testReasonSaysWhyDetailsAreHidden() {
        XCTAssertEqual(AgentPrivacy.reason(mode: .never, onCall: true, manual: true), "until you show them")
        XCTAssertEqual(
            AgentPrivacy.reason(mode: .always, onCall: false, manual: false), "by Settings › Agents › Privacy")
        XCTAssertEqual(AgentPrivacy.reason(mode: .duringCalls, onCall: true, manual: false), "during a call")
        XCTAssertNil(AgentPrivacy.reason(mode: .duringCalls, onCall: false, manual: false))
        XCTAssertNil(AgentPrivacy.reason(mode: .never, onCall: true, manual: false))
        for mode in AgentPrivacy.Mode.allCases {
            for onCall in [true, false] {
                for manual in [true, false] {
                    XCTAssertEqual(
                        AgentPrivacy.reason(mode: mode, onCall: onCall, manual: manual) != nil,
                        AgentPrivacy.hidden(mode: mode, onCall: onCall, manual: manual))
                }
            }
        }
    }

    /// The manual switch on, then a call starts: turning the switch off can't show anything,
    /// so the call is the reason given.
    func testACallOutranksTheManualSwitch() {
        XCTAssertEqual(AgentPrivacy.reason(mode: .duringCalls, onCall: true, manual: true), "during a call")
        XCTAssertTrue(AgentPrivacy.hidden(mode: .duringCalls, onCall: true, manual: false))
    }

    func testSummaryAndNoticeDropTheCommandWhenHidden() {
        XCTAssertEqual(AgentPrivacy.summary("rm -rf build", hidden: false), "rm -rf build")
        XCTAssertNil(AgentPrivacy.summary("rm -rf build", hidden: true))
        XCTAssertNil(AgentPrivacy.summary("", hidden: false))
        XCTAssertEqual(AgentPrivacy.allowedNotice(tool: "Bash", summary: "ls -la", hidden: false), "Allowed ls -la")
        XCTAssertEqual(AgentPrivacy.allowedNotice(tool: "Bash", summary: "ls -la", hidden: true), "Allowed Bash")
        XCTAssertEqual(AgentPrivacy.allowedNotice(tool: nil, summary: "", hidden: false), "Allowed a tool")
    }

    func testHiddenFactsKeepTheirLabelsButNotTheirValues() {
        var session = AgentSession(id: "abc-123", project: "wisp", state: .idle, turnStarted: now, updated: now)
        session.cwd = "/Users/me/secret/wisp"
        session.branch = "main"
        session.extras.sessionName = "Fix the leak"
        let hidden = Dictionary(uniqueKeysWithValues: session.facts(now: now, hidden: true).map { ($0.label, $0) })
        XCTAssertEqual(hidden["Folder"]?.value, AgentPrivacy.placeholder)
        XCTAssertEqual(hidden["Name"]?.value, AgentPrivacy.placeholder)
        XCTAssertEqual(hidden["Session ID"]?.value, AgentPrivacy.placeholder)
        XCTAssertEqual(hidden["Branch"]?.value, "main")
        XCTAssertEqual(hidden["Folder"]?.isPrivate, true)
        XCTAssertEqual(hidden["Branch"]?.isPrivate, false)
        let shown = Dictionary(uniqueKeysWithValues: session.facts(now: now).map { ($0.label, $0.value) })
        XCTAssertEqual(shown["Folder"], "/Users/me/secret/wisp")
        XCTAssertEqual(shown["Session ID"], "abc-123")
    }
}

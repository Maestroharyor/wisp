import XCTest

@testable import WispCore

final class ContextRulesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func rule(
        _ id: String, _ trigger: ContextTrigger, _ profile: String, priority: Int = 0, enabled: Bool = true
    )
        -> ContextRule
    {
        ContextRule(id: id, trigger: trigger, profile: profile, priority: priority, enabled: enabled)
    }

    func testMatchingRuleWins() {
        let rules = [rule("code", .frontApp(["com.apple.dt.Xcode"]), "Code")]
        let state = ContextState(frontApp: "com.apple.dt.Xcode")
        XCTAssertEqual(ContextRules.match(rules, state: state), "Code")
    }

    func testOnlyFocusRulesSwapHome() {
        let focus = rule("work", .focus("Work"), "Work")
        let coding = rule("code", .frontApp(["com.apple.dt.Xcode"]), "Code")
        XCTAssertTrue(ContextRules.swapsHome(focus))
        XCTAssertFalse(ContextRules.swapsHome(coding))
        XCTAssertFalse(ContextRules.swapsHome(nil))
    }

    func testMatchingRuleReturnsTheWinningRule() {
        let rules = [
            rule("music", .mediaPlaying, "Music", priority: 1), rule("work", .focus("Work"), "Work", priority: 3),
        ]
        let state = ContextState(mediaPlaying: true, focus: "Work")
        XCTAssertEqual(ContextRules.matchingRule(rules, state: state)?.id, "work")
    }

    func testHigherPriorityWins() {
        let rules = [
            rule("music", .mediaPlaying, "Music", priority: 1),
            rule("meet", .focus("Work"), "Meeting", priority: 5),
        ]
        let state = ContextState(frontApp: nil, mediaPlaying: true, focus: "Work")
        XCTAssertEqual(ContextRules.match(rules, state: state), "Meeting")
    }

    func testDisabledRulesAreIgnored() {
        let rules = [rule("music", .mediaPlaying, "Music", enabled: false)]
        XCTAssertNil(ContextRules.match(rules, state: ContextState(frontApp: nil, mediaPlaying: true)))
    }

    func testOtherTriggers() {
        XCTAssertTrue(ContextTrigger.agentWaiting.matches(ContextState(agentWaiting: true)))
        XCTAssertTrue(ContextTrigger.externalDisplay.matches(ContextState(externalDisplay: true)))
        XCTAssertFalse(ContextTrigger.focus("Work").matches(ContextState(focus: "Sleep")))
    }

    func testManualChoiceHoldsForThirtyMinutes() {
        var engine = ContextEngineState(debounce: 2, manualHold: 1800)
        engine.chooseManually("Work", at: start)
        XCTAssertNil(engine.propose("Music", at: start.addingTimeInterval(60)))
        XCTAssertNil(engine.propose("Music", at: start.addingTimeInterval(1799)))
        XCTAssertNil(
            engine.propose("Music", at: start.addingTimeInterval(1801)), "needs to stay stable for the debounce")
        XCTAssertEqual(engine.propose("Music", at: start.addingTimeInterval(1804)), "Music")
    }

    func testDebounceStopsFlapping() {
        var engine = ContextEngineState(debounce: 2, manualHold: 1800)
        XCTAssertNil(engine.propose("Code", at: start))
        XCTAssertTrue(engine.isPending)
        XCTAssertNil(engine.propose("Music", at: start.addingTimeInterval(1)), "candidate changed: restart the wait")
        XCTAssertNil(engine.propose("Music", at: start.addingTimeInterval(2)))
        XCTAssertEqual(engine.propose("Music", at: start.addingTimeInterval(3.1)), "Music")
        XCTAssertNil(engine.propose("Music", at: start.addingTimeInterval(10)), "already active")
    }

    func testNoMatchFallsBackToTheBaseProfile() {
        var engine = ContextEngineState(debounce: 0, manualHold: 1800)
        XCTAssertEqual(engine.propose("Code", at: start), "Code")
        XCTAssertEqual(engine.propose(nil, at: start.addingTimeInterval(1)), ContextEngineState.baseProfile)
    }
}

final class ProfileTests: XCTestCase {
    func testBuiltInsHaveUniqueNames() {
        let names = Profile.builtIns.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains(ContextEngineState.baseProfile))
    }

    func testCodeIsOnlyTheAgents() throws {
        let code = try XCTUnwrap(Profile.builtIns.first { $0.name == "Code" })
        XCTAssertEqual(code.home.slots, [.init(id: "agents", size: .wide)])
        let stats = try XCTUnwrap(Profile.builtIns.first { $0.name == "Stats" })
        XCTAssertEqual(stats.home.slots.map(\.id), ["systemStats", "timer", "dayProgress"])
    }

    func testUpgradeReplacesAnUntouchedCodeAndAddsStatsOnce() throws {
        let oldCode = Profile(
            name: "Code",
            home: HomeLayout(slots: [
                .init(id: "agents", size: .medium), .init(id: "systemStats", size: .medium),
                .init(id: "timer", size: .small),
            ]), defaultPage: "home", surface: "tinted")
        let everyday = Profile(name: "Everyday", home: HomeLayout(slots: []), defaultPage: "home", surface: "black")
        let upgraded = Profile.upgrade([everyday, oldCode], from: 1)
        XCTAssertEqual(upgraded.map(\.name), ["Everyday", "Code", "Stats"])
        XCTAssertEqual(upgraded[1].home.slots, [.init(id: "agents", size: .wide)])
        let fromTwo = Profile.upgrade(
            [
                Profile(
                    name: "Code", home: HomeLayout(slots: [.init(id: "agents", size: .large)]), defaultPage: "home",
                    surface: "tinted")
            ], from: 2)
        XCTAssertEqual(fromTwo.first?.home.slots, [.init(id: "agents", size: .wide)])
        XCTAssertEqual(fromTwo.count, 1, "Stats was offered at version 2 already")
        XCTAssertEqual(
            Profile.upgrade(
                [
                    Profile(
                        name: "Code", home: HomeLayout(slots: [.init(id: "agents", size: .large)]),
                        defaultPage: "home", surface: "tinted")
                ], from: 3
            ).first?.home.slots, [.init(id: "agents", size: .wide)])
        XCTAssertEqual(Profile.upgrade(upgraded, from: 1).count, 3, "Stats isn't added twice")
        XCTAssertEqual(Profile.upgrade([everyday], from: Profile.builtInsVersion), [everyday], "already current")
    }

    func testResizeCyclesThroughAllowedSizes() {
        XCTAssertEqual(WidgetSize.large.next(in: WidgetSize.standard), .small)
        XCTAssertEqual(WidgetSize.large.next(in: WidgetSize.allCases), .wide)
        XCTAssertEqual(WidgetSize.wide.next(in: WidgetSize.allCases), .small)
        XCTAssertEqual(WidgetSize.wide.next(in: WidgetSize.standard), .small, "a size it can't take resets")
    }

    func testHomeOnScreenFollowsAnUntouchedProfile() {
        let old = HomeLayout(slots: [.init(id: "agents", size: .large)])
        let new = HomeLayout(slots: [.init(id: "agents", size: .wide)])
        let before = [Profile(name: "Code", home: old, defaultPage: "home", surface: "tinted")]
        let after = [Profile(name: "Code", home: new, defaultPage: "home", surface: "tinted")]
        XCTAssertEqual(Profile.upgradedHome(old, profile: "Code", before: before, after: after), new)
        let edited = HomeLayout(slots: [.init(id: "agents", size: .medium)])
        XCTAssertEqual(Profile.upgradedHome(edited, profile: "Code", before: before, after: after), edited)
        XCTAssertEqual(Profile.upgradedHome(old, profile: "Work", before: before, after: after), old)
    }

    func testUpgradeKeepsAnEditedCode() {
        let edited = Profile(
            name: "Code", home: HomeLayout(slots: [.init(id: "notes", size: .small)]), defaultPage: "home",
            surface: "glass")
        XCTAssertEqual(Profile.upgrade([edited], from: 1).first, edited)
    }

    func testCodableRoundTrip() throws {
        let home = HomeLayout(slots: [.init(id: "agents", size: .medium), .init(id: "calendar", size: .small)])
        let profile = Profile(name: "Code", home: home, defaultPage: "widgets", surface: "glass")
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }

    func testHotkeyIndex() {
        XCTAssertEqual(Profile.index(forDigit: 1, count: 3), 0)
        XCTAssertEqual(Profile.index(forDigit: 3, count: 3), 2)
        XCTAssertNil(Profile.index(forDigit: 4, count: 3))
        XCTAssertNil(Profile.index(forDigit: 0, count: 3))
    }

    func testDigitKeyCodes() {
        XCTAssertEqual(KeyCodes.digit(forKeyCode: 18), 1)
        XCTAssertEqual(KeyCodes.digit(forKeyCode: 23), 5)
        XCTAssertEqual(KeyCodes.digit(forKeyCode: 25), 9)
        XCTAssertNil(KeyCodes.digit(forKeyCode: 29), "0 is not a profile")
        XCTAssertNil(KeyCodes.digit(forKeyCode: 9))
    }

    func testRenamingKeepsUniqueNames() {
        XCTAssertEqual(Profile.uniqueName("Work", existing: ["Work", "Work 2"]), "Work 3")
        XCTAssertEqual(Profile.uniqueName("Gaming", existing: ["Work"]), "Gaming")
        XCTAssertEqual(Profile.uniqueName("  ", existing: []), "Profile")
    }
}

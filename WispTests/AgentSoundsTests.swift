import XCTest

@testable import WispCore

final class AgentSoundsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Settings

    func testDefaultsKeepTodaysRequestChimeAndLeaveTheRestQuiet() {
        let sounds = AgentSounds()
        XCTAssertEqual(sounds[.needsApproval], AgentSoundSetting(on: true, sound: .system("Tink")))
        XCTAssertEqual(sounds[.question], AgentSoundSetting(on: true, sound: .system("Tink")))
        XCTAssertTrue(sounds[.spendCap].on)
        for event in [AgentSoundEvent.finished, .failed, .contextWarning, .contextCritical] {
            XCTAssertFalse(sounds[event].on, "\(event)")
        }
        XCTAssertEqual(sounds.volume, 1)
        XCTAssertTrue(sounds.muteDuringCallsOrFocus)
    }

    func testEveryEventHasATitle() {
        XCTAssertEqual(Set(AgentSoundEvent.allCases.map(\.title)).count, AgentSoundEvent.allCases.count)
        XCTAssertEqual(AgentSoundEvent.needsApproval.title, "Needs approval")
    }

    func testRoundTripsAndFillsInMissingEvents() throws {
        var sounds = AgentSounds()
        sounds[.finished] = AgentSoundSetting(on: true, sound: .file("/Users/me/done.aiff"))
        sounds.volume = 0.4
        let data = try JSONEncoder().encode(sounds)
        XCTAssertEqual(try JSONDecoder().decode(AgentSounds.self, from: data), sounds)

        let partial = Data(#"{"events":{"failed":{"on":true,"sound":{"system":{"_0":"Basso"}}}},"volume":0.5}"#.utf8)
        let decoded = try JSONDecoder().decode(AgentSounds.self, from: partial)
        XCTAssertEqual(decoded[.failed], AgentSoundSetting(on: true, sound: .system("Basso")))
        XCTAssertEqual(decoded[.needsApproval], AgentSounds()[.needsApproval])
        XCTAssertEqual(decoded.volume, 0.5)
        XCTAssertTrue(decoded.muteDuringCallsOrFocus)
    }

    func testVolumeIsClamped() {
        var sounds = AgentSounds()
        sounds.volume = 3
        XCTAssertEqual(sounds.volume, 1)
        sounds.volume = -1
        XCTAssertEqual(sounds.volume, 0)
    }

    // MARK: Migration

    func testOldPermissionSoundOffSilencesRequests() {
        let sounds = AgentSounds.migrated(approvalSound: false, pack: .off, custom: [:])
        XCTAssertFalse(sounds[.needsApproval].on)
        XCTAssertFalse(sounds[.question].on)
        XCTAssertFalse(sounds[.finished].on)
    }

    func testNeverSetKeepsTheDefaults() {
        XCTAssertEqual(AgentSounds.migrated(approvalSound: nil, pack: .off, custom: [:]), AgentSounds())
    }

    func testASoundPackCarriesOver() {
        let sounds = AgentSounds.migrated(approvalSound: true, pack: .classic, custom: [:])
        XCTAssertEqual(sounds[.needsApproval].sound, .system("Hero"))
        XCTAssertEqual(sounds[.question].sound, .system("Hero"))
        XCTAssertEqual(sounds[.finished], AgentSoundSetting(on: true, sound: .system("Glass")))
    }

    func testCustomPackFilesCarryOver() {
        let custom = ["alert": "/s/alert.aiff", "done": "/s/done.aiff"]
        let sounds = AgentSounds.migrated(approvalSound: true, pack: .custom, custom: custom)
        XCTAssertEqual(sounds[.needsApproval].sound, .file("/s/alert.aiff"))
        XCTAssertEqual(sounds[.finished], AgentSoundSetting(on: true, sound: .file("/s/done.aiff")))
    }

    // MARK: Rule

    func testPlaysTheChosenSoundWhenOn() {
        var rule = SoundRule()
        XCTAssertEqual(
            rule.sound(for: .needsApproval, session: "s", settings: AgentSounds(), muted: false, now: now),
            .system("Tink"))
        XCTAssertNil(rule.sound(for: .finished, session: "s", settings: AgentSounds(), muted: false, now: now))
    }

    func testABurstChimesOncePerEventAndSession() {
        var rule = SoundRule()
        let settings = AgentSounds()
        XCTAssertNotNil(rule.sound(for: .needsApproval, session: "s", settings: settings, muted: false, now: now))
        XCTAssertNil(
            rule.sound(
                for: .needsApproval, session: "s", settings: settings, muted: false, now: now.addingTimeInterval(2.9)))
        // Another session or another event isn't part of the burst.
        XCTAssertNotNil(
            rule.sound(
                for: .needsApproval, session: "t", settings: settings, muted: false, now: now.addingTimeInterval(1)))
        XCTAssertNotNil(
            rule.sound(for: .question, session: "s", settings: settings, muted: false, now: now.addingTimeInterval(1)))
        XCTAssertNotNil(
            rule.sound(
                for: .needsApproval, session: "s", settings: settings, muted: false, now: now.addingTimeInterval(3.1)))
    }

    func testMutedDuringCallsOrFocusWhenThatIsOn() {
        var rule = SoundRule()
        var settings = AgentSounds()
        XCTAssertNil(rule.sound(for: .needsApproval, session: "s", settings: settings, muted: true, now: now))
        settings.muteDuringCallsOrFocus = false
        XCTAssertNotNil(rule.sound(for: .needsApproval, session: "s", settings: settings, muted: true, now: now))
    }

    func testAMutedSoundDoesNotStartABurst() {
        var rule = SoundRule()
        let settings = AgentSounds()
        _ = rule.sound(for: .needsApproval, session: "s", settings: settings, muted: true, now: now)
        XCTAssertNotNil(
            rule.sound(
                for: .needsApproval, session: "s", settings: settings, muted: false, now: now.addingTimeInterval(1)))
    }
}

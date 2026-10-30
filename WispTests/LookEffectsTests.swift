import XCTest

@testable import WispCore

final class LookEffectsTests: XCTestCase {
    // MARK: Sounds

    func testSoundPacks() {
        XCTAssertNil(SoundPack.sound(for: .open, pack: .off, custom: [:]))
        XCTAssertEqual(SoundPack.sound(for: .open, pack: .soft, custom: [:]), .system("Tink"))
        XCTAssertEqual(SoundPack.sound(for: .alert, pack: .classic, custom: [:]), .system("Hero"))
        XCTAssertEqual(SoundPack.sound(for: .done, pack: .custom, custom: ["done": "/a.aiff"]), .file("/a.aiff"))
        XCTAssertNil(SoundPack.sound(for: .open, pack: .custom, custom: ["open": ""]))
        for event in SoundEvent.allCases {
            XCTAssertNotNil(SoundPack.sound(for: event, pack: .soft, custom: [:]))
            XCTAssertNotNil(SoundPack.sound(for: event, pack: .classic, custom: [:]))
        }
    }

    // MARK: Time of day

    func testTimeOfDayOffKeepsTheAccent() {
        let base = ThemeCatalog.violet
        XCTAssertEqual(TimeOfDayTint.tint(base, minuteOfDay: 19 * 60, mode: .off, isDark: true), base)
    }

    func testSunsetWarmsAndNightCools() {
        let base = ThemeCatalog.violet
        let noon = TimeOfDayTint.tint(base, minuteOfDay: 12 * 60, mode: .sunset, isDark: true)
        let sunset = TimeOfDayTint.tint(base, minuteOfDay: 19 * 60, mode: .sunset, isDark: true)
        let night = TimeOfDayTint.tint(base, minuteOfDay: 2 * 60, mode: .sunset, isDark: true)
        XCTAssertEqual(noon, base)
        XCTAssertGreaterThan(sunset.red, base.red)
        XCTAssertLessThan(night.red, base.red)
    }

    func testTimeOfDayWeightsAtBoundaries() {
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 17 * 60).warm, 0)
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 19 * 60).warm, 1)
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 21 * 60).warm, 0)
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 23 * 60 + 30).cool, 1)
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 3 * 60).cool, 1)
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 6 * 60).cool, 0)
        XCTAssertEqual(TimeOfDayTint.weights(minuteOfDay: 1440 + 19 * 60).warm, 1)
    }

    func testLightModeLiftsTheAccent() {
        let base = ThemeCatalog.violet
        XCTAssertEqual(TimeOfDayTint.tint(base, minuteOfDay: 0, mode: .lightDark, isDark: true), base)
        XCTAssertGreaterThan(
            TimeOfDayTint.tint(base, minuteOfDay: 0, mode: .lightDark, isDark: false).green, base.green)
    }

    // MARK: Glow pulse

    func testGlowPulseStaysInRange() {
        for step in 0..<400 {
            let time = Double(step) * 0.037
            for mode in [GlowPulse.Mode.breathing, .beat] {
                let level = GlowPulse.level(time: time, mode: mode)
                XCTAssertGreaterThanOrEqual(level, 0)
                XCTAssertLessThanOrEqual(level, 1)
            }
            XCTAssertEqual(GlowPulse.level(time: time, mode: .off), 0)
        }
    }

    func testBreathingAndBeatShape() {
        XCTAssertEqual(GlowPulse.level(time: 0, mode: .breathing), 0, accuracy: 0.001)
        XCTAssertEqual(GlowPulse.level(time: 2, mode: .breathing), 1, accuracy: 0.001)
        XCTAssertEqual(GlowPulse.level(time: 0, mode: .beat), 1, accuracy: 0.001)
        XCTAssertEqual(GlowPulse.level(time: 0.5, mode: .beat), 0.6, accuracy: 0.001)
        XCTAssertLessThan(GlowPulse.level(time: 0.4, mode: .beat), 0.1)
    }

    // MARK: Ears

    private func context(hour: Int, minute: Int, meetingIn: Double? = nil) -> EarContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: hour, minute: minute))
        let date = now ?? Date(timeIntervalSince1970: 0)
        return EarContext(
            now: date, calendar: calendar, batteryLevel: 87, nextMeeting: meetingIn.map { date + $0 * 60 },
            weather: "18°", customText: "  hi 👋 ")
    }

    func testEarText() {
        let ctx = context(hour: 21, minute: 5)
        XCTAssertNil(IdleEars.text(for: .off, context: ctx))
        XCTAssertEqual(IdleEars.text(for: .time, context: ctx), "9:05")
        XCTAssertEqual(IdleEars.text(for: .date, context: ctx), "Fri 30")
        XCTAssertEqual(IdleEars.text(for: .battery, context: ctx), "87%")
        XCTAssertEqual(IdleEars.text(for: .weather, context: ctx), "18°")
        XCTAssertEqual(IdleEars.text(for: .custom, context: ctx), "hi 👋")
        var day = ctx
        day.uses24Hour = true
        XCTAssertEqual(IdleEars.text(for: .time, context: day), "21:05")
        let midnight = context(hour: 0, minute: 0)
        XCTAssertEqual(IdleEars.text(for: .time, context: midnight), "12:00")
    }

    func testMeetingEar() {
        XCTAssertNil(IdleEars.text(for: .meeting, context: context(hour: 9, minute: 0)))
        XCTAssertEqual(IdleEars.text(for: .meeting, context: context(hour: 9, minute: 0, meetingIn: 12)), "in 12m")
        XCTAssertEqual(IdleEars.text(for: .meeting, context: context(hour: 9, minute: 0, meetingIn: 150)), "in 2h")
        XCTAssertEqual(IdleEars.text(for: .meeting, context: context(hour: 9, minute: 0, meetingIn: -3)), "now")
        XCTAssertNil(IdleEars.text(for: .meeting, context: context(hour: 9, minute: 0, meetingIn: -30)))
        XCTAssertNil(IdleEars.text(for: .meeting, context: context(hour: 9, minute: 0, meetingIn: 900)))
    }

    func testEmptyCustomTextHidesTheEar() {
        var ctx = context(hour: 9, minute: 0)
        ctx.customText = "   "
        XCTAssertNil(IdleEars.text(for: .custom, context: ctx))
    }

    // MARK: Celebrations

    func testCelebrationsFollowTheirToggles() {
        var look = Appearance.standard
        XCTAssertFalse(Celebration.shouldFire(.pomodoroDone, look: look))
        look.confettiPomodoro = true
        look.confettiAgent = true
        look.confettiBattery = true
        XCTAssertTrue(Celebration.shouldFire(.pomodoroDone, look: look))
        XCTAssertTrue(Celebration.shouldFire(.batteryFull, look: look))
        XCTAssertFalse(Celebration.shouldFire(.agentDone(duration: 60), look: look))
        XCTAssertTrue(Celebration.shouldFire(.agentDone(duration: 301), look: look))
    }

    // MARK: Pet

    func testPetMood() {
        XCTAssertEqual(PetMood.mood(needsAttention: false, celebrating: false, idleFor: 10), .awake)
        XCTAssertEqual(PetMood.mood(needsAttention: false, celebrating: false, idleFor: 120), .asleep)
        XCTAssertEqual(PetMood.mood(needsAttention: true, celebrating: false, idleFor: 500), .alert)
        XCTAssertEqual(PetMood.mood(needsAttention: true, celebrating: true, idleFor: 0), .happy)
    }
}

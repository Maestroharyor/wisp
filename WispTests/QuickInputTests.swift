import XCTest

@testable import WispCore

/// Fixed calendars and dates: Wednesday 5 November 2025, 14:20 in London (GMT, no DST).
final class QuickInputParserTests: XCTestCase {
    private let london = QuickInputParserTests.calendar("Europe/London", locale: "en_GB")
    private lazy var now = date(2025, 11, 5, 14, 20)

    static func calendar(_ zone: String, locale: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.locale = Locale(identifier: locale)
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in calendar: Calendar? = nil)
        -> Date
    {
        let calendar = calendar ?? london
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    private func parse(_ text: String, now: Date? = nil, calendar: Calendar? = nil) -> QuickIntent? {
        QuickInputParser.parse(text, now: now ?? self.now, calendar: calendar ?? london)
    }

    // MARK: Timers

    func testDurations() {
        XCTAssertEqual(parse("25 min"), .timer(.minutes(25)))
        XCTAssertEqual(parse("25min"), .timer(.minutes(25)))
        XCTAssertEqual(parse("25 minutes"), .timer(.minutes(25)))
        XCTAssertEqual(parse("1h"), .timer(.minutes(60)))
        XCTAssertEqual(parse("an hour"), .timer(.minutes(60)))
        XCTAssertEqual(parse("1h30"), .timer(.minutes(90)))
        XCTAssertEqual(parse("1 hour and 30 minutes"), .timer(.minutes(90)))
        XCTAssertEqual(parse("half an hour"), .timer(.minutes(30)))
        XCTAssertEqual(parse("Set a timer for 10 minutes."), .timer(.minutes(10)))
        XCTAssertEqual(parse("start a 5 min timer"), .timer(.minutes(5)))
    }

    func testBareNumberNeedsTheWordTimer() {
        XCTAssertEqual(parse("timer 10"), .timer(.minutes(10)))
        XCTAssertNil(parse("10"))
    }

    func testTimerLimits() {
        XCTAssertNil(parse("4 hours"))
        XCTAssertNil(parse("0 min"))
        XCTAssertNil(parse("90 seconds"))
        XCTAssertEqual(parse("120 seconds"), .timer(.minutes(2)))
    }

    func testPomodoro() {
        XCTAssertEqual(parse("pomodoro"), .timer(.pomodoro))
        XCTAssertEqual(parse("Start a pomodoro"), .timer(.pomodoro))
        XCTAssertEqual(parse("focus"), .timer(.pomodoro))
    }

    // MARK: Reminders

    func testRemindMeAtAnHour() {
        // "at 5" at 14:20 means 17:00 today.
        XCTAssertEqual(parse("remind me to call Sam at 5"), .reminder(title: "Call Sam", due: date(2025, 11, 5, 17, 0)))
    }

    func testRemindMeWithTheTimeFirst() {
        XCTAssertEqual(
            parse("Remind me at 4pm to send the invoice"),
            .reminder(title: "Send the invoice", due: date(2025, 11, 5, 16, 0)))
    }

    func testTimeOnItsOwnIsAReminder() {
        XCTAssertEqual(parse("at 4pm"), .reminder(title: "Reminder", due: date(2025, 11, 5, 16, 0)))
        XCTAssertEqual(
            parse("water the plants at 6pm"), .reminder(title: "Water the plants", due: date(2025, 11, 5, 18, 0)))
    }

    func testPassedTimeMovesToTomorrow() {
        XCTAssertEqual(parse("at 9am"), .reminder(title: "Reminder", due: date(2025, 11, 6, 9, 0)))
        XCTAssertEqual(parse("at 13:30"), .reminder(title: "Reminder", due: date(2025, 11, 6, 13, 30)))
        // Both 2:00 and 14:00 have passed: tomorrow afternoon.
        XCTAssertEqual(parse("at 2"), .reminder(title: "Reminder", due: date(2025, 11, 6, 14, 0)))
    }

    func testRelativeTime() {
        XCTAssertEqual(
            parse("remind me to stretch in 20 minutes"),
            .reminder(title: "Stretch", due: now.addingTimeInterval(20 * 60)))
        XCTAssertEqual(
            parse("in 2 hours check the oven"), .reminder(title: "Check the oven", due: now.addingTimeInterval(7200)))
    }

    func testDaysAndWeekdays() {
        XCTAssertEqual(
            parse("remind me to pay rent tomorrow"), .reminder(title: "Pay rent", due: date(2025, 11, 6, 9, 0)))
        XCTAssertEqual(
            parse("remind me to pay rent on Friday at 5"), .reminder(title: "Pay rent", due: date(2025, 11, 7, 17, 0)))
        XCTAssertEqual(parse("remind me to bin day monday"), .reminder(title: "Bin day", due: date(2025, 11, 10, 9, 0)))
        // Today is Wednesday: plain "wednesday" is today, "next wednesday" a week on.
        XCTAssertEqual(
            parse("remind me wednesday 6pm to ring"), .reminder(title: "Ring", due: date(2025, 11, 5, 18, 0)))
        XCTAssertEqual(
            parse("remind me next wed 6pm to ring"), .reminder(title: "Ring", due: date(2025, 11, 12, 18, 0)))
        XCTAssertEqual(
            parse("remind me tonight to lock up"), .reminder(title: "Lock up", due: date(2025, 11, 5, 20, 0)))
        XCTAssertEqual(parse("tonight at 9 film"), .reminder(title: "Film", due: date(2025, 11, 5, 21, 0)))
        XCTAssertEqual(
            parse("remind me tomorrow morning to stretch"), .reminder(title: "Stretch", due: date(2025, 11, 6, 9, 0)))
    }

    func testAmbiguousHourOnAnotherDay() {
        XCTAssertEqual(parse("remind me tomorrow at 5 to go"), .reminder(title: "Go", due: date(2025, 11, 6, 17, 0)))
        XCTAssertEqual(parse("remind me tomorrow at 8 to go"), .reminder(title: "Go", due: date(2025, 11, 6, 8, 0)))
        XCTAssertEqual(parse("remind me tomorrow at noon to go"), .reminder(title: "Go", due: date(2025, 11, 6, 12, 0)))
    }

    func testReminderWithoutATime() {
        XCTAssertEqual(parse("remind me to buy milk"), .reminder(title: "Buy milk", due: nil))
        XCTAssertNil(parse("remind me"))
    }

    func testKeepsTheUsersCase() {
        XCTAssertEqual(
            parse("remind me to email iOS team at 5pm"),
            .reminder(title: "Email iOS team", due: date(2025, 11, 5, 17, 0)))
    }

    func testForStaysInAReminderTitle() {
        XCTAssertEqual(
            parse("remind me to run for 30 min at 6pm"),
            .reminder(title: "Run for 30 min", due: date(2025, 11, 5, 18, 0)))
    }

    // MARK: Events

    func testEvents() {
        XCTAssertEqual(
            parse("tomorrow 9am meeting"), .event(title: "Meeting", start: date(2025, 11, 6, 9, 0), minutes: 60))
        XCTAssertEqual(
            parse("Lunch with Ana on Friday at 1 for 90 min"),
            .event(title: "Lunch with Ana", start: date(2025, 11, 7, 13, 0), minutes: 90))
        XCTAssertEqual(
            parse("standup at 9:30 tomorrow for 15 minutes"),
            .event(title: "Standup", start: date(2025, 11, 6, 9, 30), minutes: 15))
    }

    func testEventNeedsATime() {
        XCTAssertNil(parse("meeting tomorrow"))
    }

    // MARK: Not handled

    func testEverythingElseGoesToTheModel() {
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("buy 2 apples"))
        XCTAssertNil(parse("what's the weather"))
        XCTAssertNil(parse("meet at the office"))
    }

    // MARK: Time zones

    func testDatesAreInTheGivenTimeZone() {
        let tokyo = Self.calendar("Asia/Tokyo", locale: "ja_JP")
        // 14:20 London is 23:20 in Tokyo, so "at 9am" there is 09:00 Tokyo the next morning.
        let due = date(2025, 11, 6, 9, 0, in: tokyo)
        XCTAssertEqual(parse("at 9am", calendar: tokyo), .reminder(title: "Reminder", due: due))
    }

    func testDaylightSavingDay() {
        // Clocks go forward in New York on 9 March 2025; tomorrow at 9 is still 09:00 local.
        let newYork = Self.calendar("America/New_York", locale: "en_US")
        let saturday = date(2025, 3, 8, 12, 0, in: newYork)
        XCTAssertEqual(
            parse("remind me tomorrow at 9am to call", now: saturday, calendar: newYork),
            .reminder(title: "Call", due: date(2025, 3, 9, 9, 0, in: newYork)))
    }

    // MARK: Model answers

    private func model(_ json: String) -> QuickIntent? {
        QuickInputParser.intent(fromModel: json, now: now, calendar: london)
    }

    func testModelTimer() {
        XCTAssertEqual(model(#"{"kind":"timer","minutes":45}"#), .timer(.minutes(45)))
        XCTAssertEqual(model(#"{"kind":"timer","minutes":"15"}"#), .timer(.minutes(15)))
        XCTAssertEqual(model(#"{"kind":"timer","title":"Pomodoro"}"#), .timer(.pomodoro))
        XCTAssertNil(model(#"{"kind":"timer","minutes":600}"#))
        XCTAssertNil(model(#"{"kind":"timer"}"#))
    }

    func testModelReminder() {
        XCTAssertEqual(
            model(#"{"kind":"reminder","title":"Call the bank","date":"2025-11-06T10:00:00+00:00"}"#),
            .reminder(title: "Call the bank", due: date(2025, 11, 6, 10, 0)))
        XCTAssertEqual(
            model(#"{"kind":"reminder","title":"Call the bank"}"#), .reminder(title: "Call the bank", due: nil))
        XCTAssertNil(model(#"{"kind":"reminder","title":"  "}"#))
    }

    func testModelDateWithoutOffsetIsLocal() {
        let tokyo = Self.calendar("Asia/Tokyo", locale: "ja_JP")
        XCTAssertEqual(
            QuickInputParser.intent(
                fromModel: #"{"kind":"reminder","title":"Tea","date":"2025-11-06T09:00:00"}"#, now: now, calendar: tokyo
            ),
            .reminder(title: "Tea", due: date(2025, 11, 6, 9, 0, in: tokyo)))
    }

    func testModelEvent() {
        XCTAssertEqual(
            model(#"{"kind":"event","title":"Dentist","date":"2025-11-07T15:30:00Z","minutes":30}"#),
            .event(title: "Dentist", start: date(2025, 11, 7, 15, 30), minutes: 30))
        XCTAssertEqual(
            model(#"{"kind":"event","title":"Dentist","date":"2025-11-07T15:30:00Z"}"#),
            .event(title: "Dentist", start: date(2025, 11, 7, 15, 30), minutes: 60))
        XCTAssertNil(model(#"{"kind":"event","title":"Dentist"}"#))
    }

    func testModelNonsense() {
        XCTAssertNil(model("I can't help with that"))
        XCTAssertNil(model(#"{"kind":"email","title":"x"}"#))
        XCTAssertNil(model(#"["timer"]"#))
    }

    func testModelTitleIsTrimmedAndCapped() {
        let long = String(repeating: "a", count: 300)
        guard case .reminder(let title, _) = model(#"{"kind":"reminder","title":"  \#(long)  "}"#) else {
            return XCTFail("expected a reminder")
        }
        XCTAssertEqual(title.count, QuickInputParser.maxTitleLength)
    }

    func testModelDatesOverAYearAheadAreRefused() {
        XCTAssertNil(model(#"{"kind":"reminder","title":"Tea","date":"2027-01-01T09:00:00Z"}"#))
    }

    func testPastModelDatesReachTheCheck() {
        // Read as given, so the card can say the time has passed rather than show the hint.
        let earlier = model(#"{"kind":"event","title":"Tea","date":"2025-11-05T10:00:00Z"}"#)
        XCTAssertEqual(earlier, .event(title: "Tea", start: date(2025, 11, 5, 10, 0), minutes: 60))
        XCTAssertEqual(earlier.flatMap { QuickIntentCheck.problem($0, now: now) }, QuickIntentCheck.passed)
        let lastMinute = model(#"{"kind":"reminder","title":"Tea","date":"2025-11-05T14:19:30Z"}"#)
        XCTAssertEqual(lastMinute.flatMap { QuickIntentCheck.problem($0, now: now) }, QuickIntentCheck.passed)
    }

    func testTheSameMinuteIsNotPast() {
        // Models round to the minute: 14:20 typed at 14:20:40 is fine.
        let later = now.addingTimeInterval(40)
        XCTAssertNil(QuickIntentCheck.problem(.reminder(title: "x", due: now), now: later))
        XCTAssertEqual(
            QuickIntentCheck.problem(.reminder(title: "x", due: now.addingTimeInterval(-1)), now: later),
            QuickIntentCheck.passed)
    }

    func testModelEventLengthOutsideADayIsRejected() {
        XCTAssertNil(model(#"{"kind":"event","title":"Tea","date":"2025-11-06T10:00:00Z","minutes":0}"#))
        XCTAssertNil(model(#"{"kind":"event","title":"Tea","date":"2025-11-06T10:00:00Z","minutes":1441}"#))
        XCTAssertEqual(
            model(#"{"kind":"event","title":"Tea","date":"2025-11-06T10:00:00Z","minutes":1440}"#),
            .event(title: "Tea", start: date(2025, 11, 6, 10, 0), minutes: 1440))
    }

    // MARK: Past times

    func testTodayAtAPassedTimeIsCaughtByTheCheck() {
        let intent = parse("today at 9am")
        XCTAssertEqual(intent, .reminder(title: "Reminder", due: date(2025, 11, 5, 9, 0)))
        XCTAssertEqual(intent.flatMap { QuickIntentCheck.problem($0, now: now) }, QuickIntentCheck.passed)
    }

    func testSameWeekdayWithAPassedTimeIsNextWeek() {
        XCTAssertEqual(
            parse("remind me wednesday 9am to call"), .reminder(title: "Call", due: date(2025, 11, 12, 9, 0)))
        // No time: the morning default has passed too.
        XCTAssertEqual(
            parse("remind me on wednesday to call"), .reminder(title: "Call", due: date(2025, 11, 12, 9, 0)))
    }

    func testADayPartThatIsOverReadsAsPassed() {
        XCTAssertNil(parse("remind me this morning to call"))
        XCTAssertEqual(QuickInputParser.read("remind me this morning to call", now: now, calendar: london), .passed)
        XCTAssertEqual(QuickInputParser.read("what's the weather", now: now, calendar: london), .unknown)
        XCTAssertEqual(QuickInputParser.read("25 min", now: now, calendar: london), .intent(.timer(.minutes(25))))
    }

    func testEarlyHoursAtNightAreTheNextDay() {
        XCTAssertEqual(
            parse("remind me tonight at 1 to sleep"), .reminder(title: "Sleep", due: date(2025, 11, 6, 1, 0)))
        XCTAssertEqual(
            parse("remind me this evening at 2 to sleep"), .reminder(title: "Sleep", due: date(2025, 11, 6, 2, 0)))
        XCTAssertEqual(
            parse("remind me tonight at 1am to sleep"), .reminder(title: "Sleep", due: date(2025, 11, 6, 1, 0)))
        XCTAssertEqual(parse("remind me tonight at 9 to read"), .reminder(title: "Read", due: date(2025, 11, 5, 21, 0)))
    }

    func testTwelveAmIsTheEndOfTheDayNamed() {
        XCTAssertEqual(parse("remind me tomorrow at 12am to go"), .reminder(title: "Go", due: date(2025, 11, 7, 0, 0)))
    }

    private func read(_ text: String) -> QuickRead {
        QuickInputParser.read(text, now: now, calendar: london)
    }

    func testRemindMeWithUnreadTimingIsUnsure() {
        XCTAssertEqual(
            read("remind me to call mom in 2 days"), .unsure(.reminder(title: "Call mom in 2 days", due: nil)))
        XCTAssertEqual(read("remind me to x next week"), .unsure(.reminder(title: "X next week", due: nil)))
        XCTAssertEqual(read("remind me at 9.30pm to x"), .unsure(.reminder(title: "9.30pm to x", due: nil)))
        XCTAssertEqual(read("remind me to call in a week"), .unsure(.reminder(title: "Call in a week", due: nil)))
        XCTAssertEqual(
            read("remind me to pay rent on the 3rd"), .unsure(.reminder(title: "Pay rent on the 3rd", due: nil)))
        XCTAssertNil(parse("remind me to call mom in 2 days"))
    }

    func testEverydayUndatedRemindersAreRead() {
        let phrases = [
            "call mom at work": "Call mom at work", "look in the fridge": "Look in the fridge",
            "check in on Sam": "Check in on Sam", "drop by the shop": "Drop by the shop",
            "buy the next book": "Buy the next book", "read chapter 3": "Read chapter 3", "pay 2 bills": "Pay 2 bills",
        ]
        for (phrase, title) in phrases {
            XCTAssertEqual(read("remind me to \(phrase)"), .intent(.reminder(title: title, due: nil)), phrase)
        }
    }

    func testEventLongerThanADayIsNotRead() {
        XCTAssertNil(parse("meeting tomorrow at 3 for 25 hours"))
        XCTAssertEqual(read("meeting tomorrow at 3 for 0 min"), .unknown)
    }

    func testMorningAtTwelveAmIsTheStartOfTheDay() {
        XCTAssertEqual(
            parse("remind me tomorrow morning at 12am to go"), .reminder(title: "Go", due: date(2025, 11, 6, 0, 0)))
    }

    func testADayPartUnderWayGivesTheNextHour() {
        let late = date(2025, 11, 5, 21, 30)
        XCTAssertEqual(
            parse("remind me tonight to lock up", now: late),
            .reminder(title: "Lock up", due: date(2025, 11, 5, 22, 0)))
    }

    func testTwelveAtNightIsMidnight() {
        XCTAssertEqual(
            parse("remind me tonight at 12 to sleep"), .reminder(title: "Sleep", due: date(2025, 11, 6, 0, 0)))
        XCTAssertEqual(
            parse("remind me this evening at 12 to sleep"), .reminder(title: "Sleep", due: date(2025, 11, 6, 0, 0)))
        XCTAssertEqual(
            parse("remind me this afternoon at 12 to eat"), .reminder(title: "Eat", due: date(2025, 11, 6, 12, 0)))
    }

    func testMidnightIsTheEndOfTheDayNamed() {
        XCTAssertEqual(
            parse("remind me tomorrow at midnight to go"), .reminder(title: "Go", due: date(2025, 11, 7, 0, 0)))
        XCTAssertEqual(parse("remind me at midnight to go"), .reminder(title: "Go", due: date(2025, 11, 6, 0, 0)))
    }

    func testTheCheck() {
        XCTAssertNil(QuickIntentCheck.problem(.timer(.minutes(5)), now: now))
        XCTAssertNil(QuickIntentCheck.problem(.reminder(title: "x", due: nil), now: now))
        XCTAssertNil(QuickIntentCheck.problem(.reminder(title: "x", due: now.addingTimeInterval(60)), now: now))
        XCTAssertEqual(
            QuickIntentCheck.problem(.event(title: "x", start: now.addingTimeInterval(-60), minutes: 30), now: now),
            QuickIntentCheck.passed)
    }

    // MARK: Wording

    func testRemindMeAlwaysMakesAReminder() {
        XCTAssertEqual(
            parse("remind me about the meeting at 3"),
            .reminder(title: "The meeting", due: date(2025, 11, 5, 15, 0)))
    }

    func testShortDayNamesNeedOnNextOrATime() {
        XCTAssertEqual(parse("sat with bob at 3"), .reminder(title: "Sat with bob", due: date(2025, 11, 5, 15, 0)))
        XCTAssertEqual(
            parse("put it in the sun at 4pm"), .reminder(title: "Put it in the sun", due: date(2025, 11, 5, 16, 0)))
        XCTAssertEqual(parse("remind me sat 10am to shop"), .reminder(title: "Shop", due: date(2025, 11, 8, 10, 0)))
        XCTAssertEqual(parse("remind me on sat to shop"), .reminder(title: "Shop", due: date(2025, 11, 8, 9, 0)))
    }

    /// "next Friday" is the coming Friday; only on that weekday itself does "next" mean a week on.
    func testNextWeekdayIsTheComingOne() {
        XCTAssertEqual(parse("remind me next friday to pay"), .reminder(title: "Pay", due: date(2025, 11, 7, 9, 0)))
    }
}

final class QuickIntentTextTests: XCTestCase {
    private let london = QuickInputParserTests.calendar("Europe/London", locale: "en_GB")

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        london.date(from: DateComponents(year: 2025, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private var now: Date { date(5, 14, 20) }

    func testHeadlines() {
        XCTAssertEqual(QuickIntentText.headline(.timer(.minutes(25))), "25 min timer")
        XCTAssertEqual(QuickIntentText.headline(.timer(.minutes(90))), "1 h 30 min timer")
        XCTAssertEqual(QuickIntentText.headline(.timer(.minutes(60))), "1 h timer")
        XCTAssertEqual(QuickIntentText.headline(.timer(.pomodoro)), "Pomodoro")
        XCTAssertEqual(QuickIntentText.headline(.reminder(title: "Call Sam", due: nil)), "Call Sam")
    }

    func testDetails() {
        XCTAssertEqual(
            QuickIntentText.detail(.reminder(title: "x", due: date(5, 17, 0)), now: now, calendar: london),
            "Reminder, today at 17:00")
        XCTAssertEqual(
            QuickIntentText.detail(.reminder(title: "x", due: date(6, 9, 0)), now: now, calendar: london),
            "Reminder, tomorrow at 09:00")
        XCTAssertEqual(
            QuickIntentText.detail(.reminder(title: "x", due: date(7, 9, 0)), now: now, calendar: london),
            "Reminder, Friday at 09:00")
        XCTAssertEqual(QuickIntentText.detail(.reminder(title: "x", due: nil), now: now, calendar: london), "Reminder")
        XCTAssertEqual(
            QuickIntentText.detail(.event(title: "x", start: date(6, 9, 0), minutes: 30), now: now, calendar: london),
            "Event, tomorrow at 09:00 for 30 min")
        XCTAssertEqual(
            QuickIntentText.detail(.timer(.minutes(5)), now: now, calendar: london), "Starts when you confirm")
    }

    func testFarDatesShowTheDate() {
        let detail = QuickIntentText.detail(.reminder(title: "x", due: date(20, 9, 0)), now: now, calendar: london)
        XCTAssertTrue(detail.contains("20"), detail)
        XCTAssertTrue(detail.contains("Nov"), detail)
    }

    func testTwelveHourLocale() {
        var us = london
        us.locale = Locale(identifier: "en_US")
        let detail = QuickIntentText.detail(.reminder(title: "x", due: date(5, 17, 0)), now: now, calendar: us)
        XCTAssertTrue(detail.hasPrefix("Reminder, today at 5:00"), detail)
        XCTAssertTrue(detail.hasSuffix("PM"), detail)
    }

    func testActions() {
        XCTAssertEqual(QuickIntentText.action(.timer(.minutes(5))), "Start")
        XCTAssertEqual(QuickIntentText.action(.reminder(title: "x", due: nil)), "Add")
        XCTAssertEqual(QuickIntentText.action(.event(title: "x", start: .now, minutes: 5)), "Add")
    }
}

final class QuickInputFlowTests: XCTestCase {
    private let undated = QuickIntent.reminder(title: "Call mom in 2 days", due: nil)
    private let timer = QuickIntent.timer(.minutes(5))

    func testAReadRequestIsProposed() {
        XCTAssertEqual(QuickInputFlow.step(for: .intent(timer), aiReady: true), .propose(timer))
        XCTAssertEqual(QuickInputFlow.step(for: .passed, aiReady: true), .passed)
    }

    func testWithoutAIAnUnsureReminderIsProposedUndated() {
        XCTAssertEqual(QuickInputFlow.step(for: .unsure(undated), aiReady: false), .propose(undated))
        XCTAssertEqual(QuickInputFlow.step(for: .unknown, aiReady: false), .hint)
    }

    func testWithAIUnsureAndUnknownGoToTheModel() {
        XCTAssertEqual(QuickInputFlow.step(for: .unsure(undated), aiReady: true), .askModel(fallback: undated))
        XCTAssertEqual(QuickInputFlow.step(for: .unknown, aiReady: true), .askModel(fallback: nil))
    }

    func testAfterTheModelItsReadingThenTheFallback() {
        XCTAssertEqual(QuickInputFlow.step(afterModel: timer, fallback: undated), .propose(timer))
        XCTAssertEqual(QuickInputFlow.step(afterModel: nil, fallback: undated), .propose(undated))
        XCTAssertEqual(QuickInputFlow.step(afterModel: nil, fallback: nil), .hint)
    }
}

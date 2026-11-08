import Foundation

/// The timer a quick request starts.
public enum QuickTimer: Equatable, Sendable {
    case minutes(Int)
    /// A Pomodoro focus session, at the length set in the widget.
    case pomodoro
}

/// What a quick request ("25 min", "remind me to call Sam at 5", "tomorrow 9am meeting") asks
/// Wisp to make. Nothing is made until the user confirms it.
public enum QuickIntent: Equatable, Sendable {
    case timer(QuickTimer)
    /// A Reminders item, with a due date and alert when the request named a time.
    case reminder(title: String, due: Date?)
    case event(title: String, start: Date, minutes: Int)
}

/// Reads the common English forms of a quick request without a model. Dates come out in
/// `calendar`'s time zone; anything it can't read returns nil and goes to the AI task.
public enum QuickInputParser {
    public static let timerMinutes = 1...180
    public static let eventMinutes = 60
    public static let maxEventMinutes = 24 * 60
    public static let maxTitleLength = 200
    /// When a day is named without a time ("tomorrow"), the reminder is for the morning.
    static let morningHour = 9

    public static func parse(_ text: String, now: Date, calendar: Calendar) -> QuickIntent? {
        if case .intent(let intent) = read(text, now: now, calendar: calendar) { return intent }
        return nil
    }

    /// What `parse` read, and when it found nothing, whether that's because the time named is
    /// over ("this morning" in the afternoon), which the model can't fix either.
    public static func read(_ text: String, now: Date, calendar: Calendar) -> QuickRead {
        let words = Word.split(text)
        guard !words.isEmpty, text.count <= 300 else { return .unknown }
        if let timer = timer(words.map(\.key)) { return .intent(.timer(timer)) }
        return scheduled(words, now: now, calendar: calendar)
    }

    // MARK: Timers

    private static let timerFillers: Set<String> = ["set", "start", "begin", "for", "please", "new"]
    private static let timerWords: Set<String> = ["timer", "countdown"]

    static func timer(_ keys: [String]) -> QuickTimer? {
        var named = false
        var rest: [String] = []
        for (index, key) in keys.enumerated() {
            if timerWords.contains(key) {
                named = true
                continue
            }
            if timerFillers.contains(key) { continue }
            // "start a 5 min timer" and "set a timer", but "an hour" is a duration.
            if key == "a" || key == "an" {
                let previous = index > 0 ? keys[index - 1] : ""
                let next = index + 1 < keys.count ? keys[index + 1] : ""
                if (["start", "set", "begin"].contains(previous) && unit(next) == nil) || timerWords.contains(next) {
                    continue
                }
            }
            rest.append(key)
        }
        if [["pomodoro"], ["focus"], ["pomodoro", "session"], ["focus", "session"]].contains(rest) {
            return .pomodoro
        }
        guard let seconds = seconds(rest, allowBare: named), seconds.truncatingRemainder(dividingBy: 60) == 0
        else { return nil }
        let minutes = Int(seconds / 60)
        return timerMinutes.contains(minutes) ? .minutes(minutes) : nil
    }

    private static func unit(_ word: String) -> Character? {
        switch word {
        case "s", "sec", "secs", "second", "seconds": "s"
        case "m", "min", "mins", "minute", "minutes": "m"
        case "h", "hr", "hrs", "hour", "hours": "h"
        default: nil
        }
    }

    /// The length of a whole run of words ("1 hour and 30 minutes", "25min", "1h30"), or nil
    /// when any word isn't part of it. A plain number counts as minutes only when `allowBare`.
    static func seconds(_ keys: [String], allowBare: Bool) -> TimeInterval? {
        guard !keys.isEmpty else { return nil }
        if keys == ["half", "an", "hour"] || keys == ["half", "hour"] { return 1800 }
        var keys = keys
        var extra: TimeInterval = 0
        // "an hour and a half", "2 hours and a half".
        for tail in [["and", "a", "half"], ["and", "half"]]
        where keys.count > tail.count && keys.suffix(tail.count) == tail[...] {
            let hours = keys[keys.count - tail.count - 1]
            guard unit(hours) == "h" || compactToken(hours)?.last == "h" else { return nil }
            keys.removeLast(tail.count)
            extra = 1800
            break
        }
        let words = keys.filter { $0 != "and" }
        var compact = ""
        for (index, key) in words.enumerated() {
            if key == "a" || key == "an" {
                // Only "a" before a unit is one of it; "take a walk" has no number in it.
                guard index + 1 < words.count, unit(words[index + 1]) != nil else { return nil }
                compact += "1"
            } else if let letter = unit(key) {
                compact.append(letter)
            } else if let token = compactToken(key) {
                compact += token
            } else {
                return nil
            }
        }
        // "1h30" means 1 h 30 min.
        if let last = compact.last, last.isNumber, compact.contains("h"), !compact.contains("m") { compact += "m" }
        let hasUnit = compact.contains { !$0.isNumber }
        guard hasUnit || allowBare else { return nil }
        if let seconds = DurationText.seconds(from: compact) { return seconds + extra }
        // "0 min" is a length too, so callers can refuse it rather than leave it in a title.
        let zero = hasUnit && compact.contains("0") && compact.allSatisfy { $0 == "0" || !$0.isNumber }
        return zero ? extra : nil
    }

    /// "25min" as "25m"; nil for anything that isn't digits and units.
    private static func compactToken(_ key: String) -> String? {
        var result = ""
        var letters = ""
        for character in key {
            if character.isASCII, character.isNumber {
                if !letters.isEmpty {
                    guard let letter = unit(letters) else { return nil }
                    result.append(letter)
                    letters = ""
                }
                result.append(character)
            } else if character.isLetter {
                guard !result.isEmpty else { return nil }
                letters.append(character)
            } else {
                return nil
            }
        }
        if !letters.isEmpty {
            guard let letter = unit(letters) else { return nil }
            result.append(letter)
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Reminders and events

    private static let reminderPrefixes: [[String]] = [
        ["remind", "me", "to"], ["remind", "me", "about"], ["remind", "me"], ["reminder", "to"], ["reminder"],
        ["remember", "to"],
    ]
    private static let eventWords: Set<String> = [
        "meeting", "standup", "stand-up", "sync", "lunch", "dinner", "breakfast", "brunch", "coffee", "appointment",
        "interview", "party", "class", "lecture", "demo", "event", "catch-up", "catchup", "1:1", "dentist", "doctor",
        "flight", "workshop", "webinar",
    ]
    /// Joining words left at either end of a title once the time is taken out.
    private static let edgeWords: Set<String> = ["to", "at", "on", "by", "about", "that", "for"]

    private static func scheduled(_ all: [Word], now: Date, calendar: Calendar) -> QuickRead {
        var words = all
        let keys = words.map(\.key)
        let prefix = reminderPrefixes.first { keys.starts(with: $0) }
        if let prefix { words.removeFirst(prefix.count) }

        var when = When()
        var timeSpans = Set<Int>()
        var lengthSpan = Set<Int>()
        var index = 0
        while index < words.count {
            if let match = TimeMatcher.match(words.map(\.key), at: index) {
                let span = Set(index..<index + match.count)
                if case .length(let seconds) = match.part {
                    when.length = seconds
                    lengthSpan = span
                } else {
                    when.apply(match.part)
                    timeSpans.formUnion(span)
                }
                index += match.count
            } else {
                index += 1
            }
        }

        // "Remind me ..." is always a reminder, even about a meeting.
        let isEvent =
            prefix == nil && !timeSpans.isEmpty && words.contains { eventWords.contains($0.key) } && when.hasTime
        let skipped = isEvent ? timeSpans.union(lengthSpan) : timeSpans
        let left = words.enumerated().filter { !skipped.contains($0.offset) }.map(\.element)
        let title = Self.title(left)

        // "In 0 minutes" is no time at all.
        if when.relative == 0 { return .unknown }
        let due: Date?
        switch when.resolve(now: now, calendar: calendar) {
        case .passed: return .passed
        case .none: due = nil
        case .date(let date): due = date
        }
        if isEvent {
            let minutes = when.length.map { Int($0 / 60) } ?? eventMinutes
            guard let start = due, let title, (1...maxEventMinutes).contains(minutes) else { return .unknown }
            return .intent(.event(title: title, start: start, minutes: minutes))
        }
        if prefix != nil {
            if title == nil, due == nil { return .unknown }
            let reminder = QuickIntent.reminder(title: title ?? "Reminder", due: due)
            // Timing this reader couldn't follow ("in 2 days", "next week", "9.30pm") is left in the
            // title of an undated reminder: the model may read it, and without one it's still offered.
            if due == nil, hasUnreadTiming(left.map(\.key)) { return .unsure(reminder) }
            return .intent(reminder)
        }
        guard let due, !words.contains(where: { eventWords.contains($0.key) }) else { return .unknown }
        return .intent(.reminder(title: title ?? "Reminder", due: due))
    }

    private static let timeUnits: Set<String> = [
        "second", "seconds", "sec", "secs", "minute", "minutes", "min", "mins", "hour", "hours", "hr", "hrs", "day",
        "days", "week", "weeks", "weekend", "fortnight", "month", "months", "year", "years",
    ]

    private static let months: Set<String> = [
        "january", "february", "march", "april", "june", "july", "august", "september", "october", "november",
        "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]
    private static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "couple",
        "few",
    ]
    private static let clockLeads: Set<String> = ["at", "around", "before", "until", "by", "after"]

    /// Timing the reader doesn't follow: "in 2 days", "in two days", "in a week", "next month",
    /// "on november 12", "this weekend", "2 weeks from now", "around 6", "at 930", "half past
    /// five", or a word like "9.30pm", "3rd" or "5/11". A plain number ("chapter 3", "pay 2
    /// bills") or "at work" isn't timing.
    private static func hasUnreadTiming(_ keys: [String]) -> Bool {
        func digits(_ key: String) -> Bool { !key.isEmpty && key.allSatisfy(\.isNumber) }
        for (index, key) in keys.enumerated() {
            let previous = index > 0 ? keys[index - 1] : ""
            let next = index + 1 < keys.count ? keys[index + 1] : ""
            let after = index + 2 < keys.count ? keys[index + 2] : ""
            if let first = key.first, first.isNumber, key.contains(where: { !$0.isNumber }) { return true }
            if months.contains(key) || key == "weekend" || key == "tonight" { return true }
            // "May" is also a name and a verb, so only beside a number.
            if key == "may", digits(previous) || digits(next) { return true }
            if key == "from", next == "now" { return true }
            if key == "half" || key == "quarter", next == "past" || next == "to" { return true }
            if clockLeads.contains(key), digits(next) { return true }
            if key == "in", numberWords.contains(next) { return true }
            guard key == "in" || key == "next" else { continue }
            if digits(next) || timeUnits.contains(next) { return true }
            if next == "a" || next == "an", timeUnits.contains(after) || numberWords.contains(after) { return true }
        }
        return false
    }

    /// The words left, joined, with joining words trimmed from the ends and a capital first letter.
    private static func title(_ words: [Word]) -> String? {
        var words = words
        while let first = words.first, edgeWords.contains(first.key) { words.removeFirst() }
        while let last = words.last, edgeWords.contains(last.key) { words.removeLast() }
        let text = words.map(\.text).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        return capped(text)
    }

    static func capped(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String((first.uppercased() + trimmed.dropFirst()).prefix(maxTitleLength))
    }

    // MARK: Model answers

    /// How far ahead a model's date may be.
    static let modelDateAhead: TimeInterval = 366 * 24 * 3600

    /// The AI quick-input task's JSON object as an intent, or nil when it doesn't make sense.
    /// Dates without an offset are read in `calendar`'s time zone. A date over a year ahead or an
    /// event longer than a day is refused rather than fixed up; a past date is kept, so
    /// `QuickIntentCheck` can say the time has passed.
    public static func intent(fromModel json: String, now: Date, calendar: Calendar) -> QuickIntent? {
        guard let data = json.data(using: .utf8), let object = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object = object, let kind = object["kind"]?.stringValue?.lowercased()
        else { return nil }
        let title = object["title"]?.stringValue.flatMap(capped)
        let minutes = number(object["minutes"])
        let date = object["date"]?.stringValue.flatMap { self.date($0, timeZone: calendar.timeZone) }
        if let date {
            let offset = date.timeIntervalSince(now)
            guard offset <= modelDateAhead else { return nil }
        }
        switch kind {
        case "timer":
            if let minutes {
                return timerMinutes.contains(minutes) ? .timer(.minutes(minutes)) : nil
            }
            return title?.lowercased().contains("pomodoro") == true ? .timer(.pomodoro) : nil
        case "reminder":
            guard let title else { return nil }
            return .reminder(title: title, due: date)
        case "event":
            let length = minutes ?? eventMinutes
            guard let title, let date, (1...maxEventMinutes).contains(length) else { return nil }
            return .event(title: title, start: date, minutes: length)
        default:
            return nil
        }
    }

    /// Small models sometimes quote numbers.
    private static func number(_ value: JSONValue?) -> Int? {
        if let double = value?.doubleValue { return Int(double.rounded()) }
        return value?.stringValue.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.map {
            Int($0.rounded())
        }
    }

    private static func date(_ text: String, timeZone: TimeZone) -> Date? {
        let text = text.trimmingCharacters(in: .whitespaces)
        let withOffset = ISO8601DateFormatter()
        withOffset.formatOptions = [.withInternetDateTime]
        if let date = withOffset.date(from: text) { return date }
        withOffset.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withOffset.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }
}

/// What the reader made of a request.
public enum QuickRead: Equatable, Sendable {
    case intent(QuickIntent)
    /// It names a time that's over, with no sensible next one.
    case passed
    /// An undated reminder with timing words the reader couldn't follow: the model should try,
    /// and without one this is what's offered.
    case unsure(QuickIntent)
    /// Not a form the reader knows; the AI task may.
    case unknown
}

/// What Quick add does next with a request.
public enum QuickInputStep: Equatable, Sendable {
    case propose(QuickIntent)
    case passed
    /// Ask the AI; `fallback` is offered if it can't read the request either.
    case askModel(fallback: QuickIntent?)
    /// Nothing understood: show examples.
    case hint
}

public enum QuickInputFlow {
    public static func step(for read: QuickRead, aiReady: Bool) -> QuickInputStep {
        switch read {
        case .intent(let intent): .propose(intent)
        case .passed: .passed
        case .unsure(let intent): aiReady ? .askModel(fallback: intent) : .propose(intent)
        case .unknown: aiReady ? .askModel(fallback: nil) : .hint
        }
    }

    /// After the AI (or its failure, `intent` nil): its reading, else the fallback, else the hint.
    public static func step(afterModel intent: QuickIntent?, fallback: QuickIntent?) -> QuickInputStep {
        guard let chosen = intent ?? fallback else { return .hint }
        return .propose(chosen)
    }
}

/// A word of the request: as typed, and lowercased without surrounding punctuation.
struct Word: Equatable {
    let text: String
    let key: String

    static func split(_ text: String) -> [Word] {
        text.split(whereSeparator: \.isWhitespace).compactMap { part in
            let text = String(part)
            let key = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;\"'()"))
            return key.isEmpty ? nil : Word(text: text, key: key)
        }
    }
}

/// A clock time as typed: "5", "5pm", "17:30", "noon".
struct ClockTime: Equatable {
    enum Meridiem { case am, pm }

    let hour: Int
    let minute: Int
    let meridiem: Meridiem?
    /// Written as a 24-hour time ("17:30", "09:00", "0:15"), so it isn't moved to the afternoon.
    let isTwentyFourHour: Bool
}

enum DayPart: Equatable {
    case morning, afternoon, evening, night

    var defaultHour: Int {
        switch self {
        case .morning: 9
        case .afternoon: 15
        case .evening: 18
        case .night: 20
        }
    }

    /// The hour it's over; once past it, "this morning" no longer means anything today.
    var endHour: Int {
        switch self {
        case .morning: 12
        case .afternoon: 17
        case .evening: 22
        case .night: 24
        }
    }

    var isAfterNoon: Bool { self != .morning }
}

/// One piece of a request's timing.
enum TimePart: Equatable {
    case dayOffset(Int)
    case weekday(Int, next: Bool)
    case clock(ClockTime)
    case part(DayPart)
    case relative(TimeInterval)
    case length(TimeInterval)
}

/// Finds timing phrases in a run of lowercased words.
enum TimeMatcher {
    struct Match: Equatable {
        let part: TimePart
        let count: Int
    }

    private static let weekdayNames: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]
    /// Short names are also words ("sat", "sun", "wed"), so on their own they count as a day only
    /// right before a time ("sat 10am").
    private static let weekdayShortNames: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7,
    ]

    private static func weekday(_ key: String) -> Int? { weekdayNames[key] ?? weekdayShortNames[key] }

    static func match(_ keys: [String], at index: Int) -> Match? {
        let key = keys[index]
        let next = index + 1 < keys.count ? keys[index + 1] : nil
        switch key {
        case "today": return Match(part: .dayOffset(0), count: 1)
        case "tonight": return Match(part: .part(.night), count: 1)
        case "tomorrow", "tmrw", "tmr": return Match(part: .dayOffset(1), count: 1)
        case "morning", "afternoon", "evening":
            if let part = dayPart(key) { return Match(part: .part(part), count: 1) }
        case "this":
            if let next, let part = dayPart(next) { return Match(part: .part(part), count: 2) }
        case "on":
            if let next, let day = weekday(next) { return Match(part: .weekday(day, next: false), count: 2) }
        case "next":
            if let next, let day = weekday(next) { return Match(part: .weekday(day, next: true), count: 2) }
        case "at", "by", "@":
            if let clock = clock(keys, at: index + 1, bare: true) {
                return Match(part: .clock(clock.time), count: 1 + clock.count)
            }
        case "in":
            if let seconds = longestDuration(keys, from: index + 1) {
                return Match(part: .relative(seconds.value), count: 1 + seconds.count)
            }
        case "for":
            if let seconds = longestDuration(keys, from: index + 1) {
                return Match(part: .length(seconds.value), count: 1 + seconds.count)
            }
        default:
            if let day = weekdayNames[key] { return Match(part: .weekday(day, next: false), count: 1) }
            if let day = weekdayShortNames[key], clock(keys, at: index + 1, bare: false) != nil {
                return Match(part: .weekday(day, next: false), count: 1)
            }
            if let clock = clock(keys, at: index, bare: false) {
                return Match(part: .clock(clock.time), count: clock.count)
            }
        }
        return nil
    }

    private static func dayPart(_ key: String) -> DayPart? {
        switch key {
        case "morning": .morning
        case "afternoon": .afternoon
        case "evening": .evening
        default: nil
        }
    }

    /// The longest run of up to five words after `start` that reads as a length.
    private static func longestDuration(_ keys: [String], from start: Int) -> (value: TimeInterval, count: Int)? {
        guard start < keys.count else { return nil }
        for end in stride(from: min(start + 5, keys.count), to: start, by: -1) {
            if let seconds = QuickInputParser.seconds(Array(keys[start..<end]), allowBare: false) {
                return (seconds, end - start)
            }
        }
        return nil
    }

    /// A clock time at `index`, with a following "am"/"pm" word. A plain number counts only
    /// after "at" (`bare`), so "buy 2 apples" has no time in it.
    static func clock(_ keys: [String], at index: Int, bare: Bool) -> (time: ClockTime, count: Int)? {
        guard index < keys.count else { return nil }
        let key = keys[index]
        if key == "noon" || key == "midday" {
            return (ClockTime(hour: 12, minute: 0, meridiem: nil, isTwentyFourHour: true), 1)
        }
        // The end of the day named: "tomorrow at midnight" is 00:00 the day after tomorrow.
        if key == "midnight" { return (ClockTime(hour: 24, minute: 0, meridiem: nil, isTwentyFourHour: true), 1) }
        var body = key
        var meridiem: ClockTime.Meridiem?
        for (suffix, value) in [("a.m", ClockTime.Meridiem.am), ("p.m", .pm), ("am", .am), ("pm", .pm)]
        where body.hasSuffix(suffix) {
            meridiem = value
            body = String(body.dropLast(suffix.count))
            break
        }
        var count = 1
        if meridiem == nil, index + 1 < keys.count {
            switch keys[index + 1] {
            case "am", "a.m": meridiem = .am
            case "pm", "p.m": meridiem = .pm
            default: break
            }
            if meridiem != nil { count = 2 }
        }
        let pieces = body.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(pieces.count), pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) }),
            let hour = Int(pieces[0]), pieces[0].count <= 2
        else { return nil }
        let minute = pieces.count == 2 ? Int(pieces[1]) : 0
        guard let minute, pieces.count == 1 || pieces[1].count == 2, (0...59).contains(minute) else { return nil }
        let hasColon = pieces.count == 2
        guard meridiem != nil || hasColon || bare else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            return (ClockTime(hour: hour, minute: minute, meridiem: meridiem, isTwentyFourHour: false), count)
        }
        guard (0...23).contains(hour) else { return nil }
        let twentyFour = hour == 0 || hour >= 13 || pieces[0].hasPrefix("0")
        return (ClockTime(hour: hour, minute: minute, meridiem: nil, isTwentyFourHour: twentyFour), count)
    }
}

/// The timing pieces found in a request, put together into one date.
struct When {
    var dayOffset: Int?
    var weekday: (day: Int, next: Bool)?
    var clock: ClockTime?
    var part: DayPart?
    var relative: TimeInterval?
    var length: TimeInterval?

    var hasTime: Bool { clock != nil || part != nil || relative != nil }

    mutating func apply(_ piece: TimePart) {
        switch piece {
        case .dayOffset(let offset): dayOffset = offset
        case .weekday(let day, let next): weekday = (day, next)
        case .clock(let time): clock = time
        case .part(let value):
            part = value
            if value == .night, dayOffset == nil { dayOffset = 0 }
        case .relative(let seconds): relative = seconds
        case .length(let seconds): length = seconds
        }
    }

    enum Resolution: Equatable {
        /// No date was said, or only "today".
        case none
        case date(Date)
        /// The words name a time that's over and has no sensible next one ("this morning" at 14:20).
        case passed
    }

    /// The date meant, in `calendar`'s time zone. A plain weekday is the coming one (today
    /// counts); "next <weekday>" is the same, except that on that weekday it means a week on.
    func resolve(now: Date, calendar: Calendar) -> Resolution {
        if let relative { return .date(now.addingTimeInterval(relative)) }
        let today = calendar.startOfDay(for: now)
        var offset = dayOffset
        var sameWeekday = false
        if offset == nil, let weekday {
            let current = calendar.component(.weekday, from: now)
            let ahead = (weekday.day - current + 7) % 7
            offset = ahead == 0 && weekday.next ? 7 : ahead
            sameWeekday = ahead == 0 && !weekday.next
        }
        let date: Date?
        if let clock {
            date = clockDate(clock, offset: offset, now: now, today: today, calendar: calendar)
            if part != nil, offset == nil, let date, date <= now { return .passed }
        } else if let part {
            if (offset ?? 0) == 0, !sameWeekday {
                return partToday(part, now: now, today: today, calendar: calendar)
            }
            date = at(part.defaultHour, 0, dayOffset: offset ?? 0, from: today, calendar: calendar)
        } else if (offset ?? 0) > 0 || sameWeekday {
            date = at(QuickInputParser.morningHour, 0, dayOffset: offset ?? 0, from: today, calendar: calendar)
        } else {
            return .none
        }
        guard let date else { return .none }
        // Today's weekday at a time that's gone: the same day next week.
        if sameWeekday, date <= now, let nextWeek = calendar.date(byAdding: .day, value: 7, to: date) {
            return .date(nextWeek)
        }
        return .date(date)
    }

    private func clockDate(_ clock: ClockTime, offset: Int?, now: Date, today: Date, calendar: Calendar) -> Date? {
        // A day part names today ("this afternoon at 12"), so a passed time isn't moved to tomorrow.
        let namedDay = offset != nil || part != nil
        if let hour = fixedHour(clock, laterDay: (offset ?? 0) > 0) {
            let date = at(hour, clock.minute, dayOffset: offset ?? 0, from: today, calendar: calendar)
            guard !namedDay, let date, date <= now else { return date }
            return at(hour, clock.minute, dayOffset: 1, from: today, calendar: calendar)
        }
        // An hour like "5" today: the next of 5:00 and 17:00 still to come.
        for hour in [clock.hour % 12, clock.hour % 12 + 12] {
            if let date = at(hour, clock.minute, dayOffset: 0, from: today, calendar: calendar), date > now {
                return date
            }
        }
        let hour = Self.guessedHour(clock.hour)
        return at(hour, clock.minute, dayOffset: namedDay ? 0 : 1, from: today, calendar: calendar)
    }

    /// "This evening" or "tonight" with no time: its usual hour, or the next whole hour while it's
    /// still under way, or nothing once it's over.
    private func partToday(_ part: DayPart, now: Date, today: Date, calendar: Calendar) -> Resolution {
        if let usual = at(part.defaultHour, 0, dayOffset: 0, from: today, calendar: calendar), usual > now {
            return .date(usual)
        }
        let nextHour = calendar.component(.hour, from: now) + 1
        guard nextHour <= part.endHour, let date = at(nextHour, 0, dayOffset: 0, from: today, calendar: calendar)
        else { return .passed }
        return .date(date)
    }

    /// The hour when the words settle it; nil for a bare "5" today, which depends on the time now.
    private func fixedHour(_ clock: ClockTime, laterDay: Bool) -> Int? {
        if let part, part == .evening || part == .night { return nightHour(clock) }
        // "Tomorrow morning at midnight" is the start of that day, as with "12am" below.
        if part == .morning, clock.hour == 24 { return 0 }
        // "12am" is the end of the day named, like "midnight", except in "tomorrow morning at 12am".
        if clock.meridiem == .am, clock.hour == 12 { return part == .morning ? 0 : 24 }
        if let meridiem = clock.meridiem { return clock.hour % 12 + (meridiem == .pm ? 12 : 0) }
        if clock.isTwentyFourHour { return clock.hour }
        if let part { return part.isAfterNoon ? clock.hour % 12 + 12 : clock.hour % 12 }
        return laterDay ? Self.guessedHour(clock.hour) : nil
    }

    /// Tonight or this evening: "9" is 21:00, while "12" and "1" to "4" (or "1am") are the small
    /// hours after midnight, so they fall on the next day.
    private func nightHour(_ clock: ClockTime) -> Int {
        let hour: Int
        if let meridiem = clock.meridiem {
            hour = clock.hour % 12 + (meridiem == .pm ? 12 : 0)
        } else if clock.isTwentyFourHour {
            hour = clock.hour
        } else {
            hour = clock.hour == 12 || (1...4).contains(clock.hour) ? clock.hour % 12 : clock.hour % 12 + 12
        }
        return hour < 5 ? hour + 24 : hour
    }

    /// A bare hour on another day: 1 to 6 is the afternoon, 7 to 12 the morning (12 is noon).
    private static func guessedHour(_ hour: Int) -> Int {
        (1...6).contains(hour) ? hour + 12 : hour
    }

    /// `hour` 24 is midnight at the end of that day.
    private func at(_ hour: Int, _ minute: Int, dayOffset: Int, from today: Date, calendar: Calendar) -> Date? {
        let days = dayOffset + hour / 24
        guard let day = calendar.date(byAdding: .day, value: days, to: today) else { return nil }
        return calendar.date(bySettingHour: hour % 24, minute: minute, second: 0, of: day)
    }
}

/// The last check before a card shows and again when it's confirmed: nothing is made for a
/// time that has already gone.
public enum QuickIntentCheck {
    public static let passed = "That time has passed"

    /// Why `intent` can't be made now, or nil when it can. Anything in the current minute counts
    /// as now, since models (and people) round to the minute.
    public static func problem(_ intent: QuickIntent, now: Date) -> String? {
        let minute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        switch intent {
        case .timer, .reminder(_, nil): return nil
        case .reminder(_, let due?): return due < minute ? passed : nil
        case .event(_, let start, _): return start < minute ? passed : nil
        }
    }
}

/// The words on the confirm card.
public enum QuickIntentText {
    public static func headline(_ intent: QuickIntent) -> String {
        switch intent {
        case .timer(.minutes(let minutes)): "\(length(minutes)) timer"
        case .timer(.pomodoro): "Pomodoro"
        case .reminder(let title, _): title
        case .event(let title, _, _): title
        }
    }

    public static func detail(_ intent: QuickIntent, now: Date, calendar: Calendar) -> String {
        switch intent {
        case .timer: return "Starts when you confirm"
        case .reminder(_, let due):
            guard let due else { return "Reminder" }
            return "Reminder, \(when(due, now: now, calendar: calendar))"
        case .event(_, let start, let minutes):
            return "Event, \(when(start, now: now, calendar: calendar)) for \(length(minutes))"
        }
    }

    public static func action(_ intent: QuickIntent) -> String {
        if case .timer = intent { return "Start" }
        return "Add"
    }

    public static func symbol(_ intent: QuickIntent) -> String {
        switch intent {
        case .timer(.minutes): "timer"
        case .timer(.pomodoro): "brain.head.profile"
        case .reminder: "checklist"
        case .event: "calendar.badge.plus"
        }
    }

    /// "25 min", "1 h", "1 h 30 min".
    public static func length(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// "today at 17:00", "Friday at 09:00", or the date when it's more than a week away.
    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date))
            .day ?? 0
        let day: String
        switch days {
        case 0: day = "today"
        case 1: day = "tomorrow"
        case 2...6: day = formatted(date, template: "EEEE", calendar: calendar)
        default: day = formatted(date, template: "EEEdMMM", calendar: calendar)
        }
        return "\(day) at \(formatted(date, template: "jmm", calendar: calendar))"
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

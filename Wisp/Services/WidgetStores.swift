import CoreLocation
import Darwin
import EventKit
import Foundation
import OSLog
import Observation
import SwiftUI
import WispCore

/// CPU and memory, sampled only while a widget is on screen.
@MainActor
@Observable
final class SystemStatsStore {
    private(set) var cpu: Double = 0
    private(set) var memory = MemoryUsage(usedBytes: 0, totalBytes: ProcessInfo.processInfo.physicalMemory)
    /// Recent samples for the small charts.
    private(set) var cpuHistory = SampleHistory(capacity: 40)
    private(set) var memoryHistory = SampleHistory(capacity: 40)
    /// CPU use needs two samples a second apart; until then the gauges show placeholders.
    private(set) var sampled = false

    @ObservationIgnored private var previous: CPUTicks?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var viewers = 0

    func attach() {
        viewers += 1
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func detach() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        task?.cancel()
        task = nil
        previous = nil
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let previous {
                cpu = CPUTicks.usage(from: previous, to: ticks)
                cpuHistory.append(cpu)
                sampled = true
            }
            previous = ticks
        }
        if let used = Self.usedMemory() {
            memory = MemoryUsage(usedBytes: used, totalBytes: ProcessInfo.processInfo.physicalMemory)
            memoryHistory.append(memory.fraction)
        }
    }

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return CPUTicks(
            user: UInt64(ticks.0), system: UInt64(ticks.1), idle: UInt64(ticks.2), nice: UInt64(ticks.3))
    }

    /// Active + wired + compressed pages, which is close to Activity Monitor's "Memory Used".
    private static func usedMemory() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * UInt64(getpagesize())
    }
}

/// The coming week's calendar events, read through EventKit after the user allows it.
@MainActor
@Observable
final class CalendarStore {
    struct Event: Identifiable, Equatable, Sendable {
        /// One occurrence: recurring events repeat `eventID` with a different start.
        let id: String
        /// The calendar's id for the event, used to open it in Calendar.
        let eventID: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        /// The event's calendar colour.
        let color: Color
        /// A video-call link from the event's URL, location or notes.
        let link: URL?
    }

    /// Events from now through the next six days, soonest first (at most 30). Filtered
    /// when read, since the cached query can be minutes old and must not list a meeting
    /// that has just ended.
    var events: [Event] { upcoming.filter { $0.end > .now } }
    private var upcoming: [Event] = []
    /// The same week with no cap, for the window's Calendar page, where a busy week must not
    /// leave its last days looking empty. Filtered when read, like `events`.
    var weekEvents: [Event] { week.filter { $0.end > .now } }
    private var week: [Event] = []
    /// The seven days from the start of today, finished events included, for the window's
    /// Day and Week grids.
    private(set) var wholeWeek: [Event] = []
    /// Every timed event today, including finished ones, for the Day Progress widget.
    private(set) var dayEvents: [ClosedRange<Date>] = []
    /// Every event today with its title, finished and all-day ones included, for the window's
    /// Day Progress page.
    private(set) var todayEvents: [Event] = []
    /// Another week the window's Calendar is showing, finished events included. Kept apart
    /// from the arrays above, which the notch, Home and meeting detection read.
    private(set) var browsed: [Event] = []
    /// The first day of the week in `browsed`, set once its events have landed.
    private(set) var browsedStart: Date?
    private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// The first read since access has landed, so an empty week isn't claimed before it has.
    private(set) var loaded = false
    #if DEBUG
        /// Showing made-up events (`debugFillSample`), which a refresh mustn't replace.
        @ObservationIgnored var usesSample = false
    #endif

    /// Asks for access. Queries go through `reader`, whose own store runs them off the main actor.
    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let reader = CalendarReader()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var lastRefresh: Date?
    /// Set by EKEventStoreChanged, so the next check reads again whatever the cache's age.
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var fetching = false
    /// A refresh asked for while a query was running; it runs once that one lands.
    @ObservationIgnored private var refetch = false
    @ObservationIgnored private var hadAccess = false
    /// Times access went away, so the reader makes a fresh store after a new grant.
    @ObservationIgnored private var revocations = 0
    /// The week the page asked for, read again when the calendars change.
    @ObservationIgnored private var browsing: Date?
    /// Called on the main actor each time a fresh week lands.
    @ObservationIgnored var onWeekLoaded: () -> Void = {}

    /// Asks the first time; once answered, macOS won't ask again, so System Settings opens.
    func requestAccess() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else {
            Permission.calendars.openSettings()
            return
        }
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = EKEventStore.authorizationStatus(for: .event)
            refresh()
        }
    }

    /// Pages rebuild on every switch, so they ask this rather than querying each time. A new
    /// day, a change in access or an EKEventStoreChanged notice reads again straight away.
    func refreshIfStale() {
        let now = Date.now
        let changed =
            dirty || EKEventStore.authorizationStatus(for: .event) != access
            || lastRefresh.map { !Calendar.current.isDate($0, inSameDayAs: now) } ?? true
        guard RefreshRule.calendar.isDue(lastRefresh: lastRefresh, now: now, dirty: changed) else { return }
        refresh()
    }

    /// Reads the seven days from `start` into `browsed`, for a week other than this one.
    func browse(weekStarting start: Date) {
        browsing = start
        guard access == .fullAccess else { return }
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let revocations = revocations
        Task {
            let events = await reader.events(from: start, to: end, revocations: revocations)
            // A later browse or a revoke while this ran wins.
            guard access == .fullAccess, browsing == start else { return }
            browsed = events
            browsedStart = start
        }
    }

    /// Back on this week: stop reading another one on every change.
    func stopBrowsing() {
        browsing = nil
    }

    func refresh() {
        #if DEBUG
            if usesSample { return }
        #endif
        access = EKEventStore.authorizationStatus(for: .event)
        dirty = false
        guard access == .fullAccess else {
            // Access was revoked: stop showing (and offering Join cards for) the cached week.
            upcoming = []
            week = []
            dayEvents = []
            todayEvents = []
            wholeWeek = []
            browsed = []
            browsedStart = nil
            loaded = false
            lastRefresh = nil
            if hadAccess { revocations += 1 }
            hadAccess = false
            return
        }
        lastRefresh = .now
        hadAccess = true
        if observer == nil {
            // The reader queries its own store, so this listens to every store's changes.
            observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dirty = true
                    self?.refreshIfStale()
                }
            }
        }
        guard !fetching else {
            refetch = true
            return
        }
        fetching = true
        let revocations = revocations
        Task {
            let week = await reader.week(from: .now, calendar: .current, revocations: revocations)
            fetching = false
            // Access can go while the query runs, and the revoked branch has already cleared the week.
            if access == .fullAccess {
                upcoming = week.upcoming
                self.week = week.all
                dayEvents = week.day
                todayEvents = week.today
                wholeWeek = week.whole
                loaded = true
                onWeekLoaded()
                if let browsing { browse(weekStarting: browsing) }
            }
            if refetch {
                refetch = false
                refresh()
            }
        }
    }

    /// Opens the event in Calendar.
    func open(_ event: Event) {
        let id = event.eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.eventID
        if let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"), NSWorkspace.shared.open(url) {
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// The Reminders widget: open reminders, overdue first. Ticking one off saves it straight
/// away and keeps it on screen, struck through with Undo, for a few seconds. Titles and due
/// dates are read into memory only.
@MainActor
@Observable
final class RemindersStore {
    private(set) var items: [ReminderItem] = []
    /// Reminders just ticked off, still shown so they can be put back.
    private(set) var justDone: Set<String> = []
    /// Whether a read has finished, so "All done" never shows before the list is known.
    private(set) var loaded = false
    /// The last read failed; the list shown is the one from before.
    private(set) var failed = false
    /// Reminders put back with Undo, by when their save finished (nil while saving). They keep
    /// their row until a read that started after the save has them, so they don't blink out.
    @ObservationIgnored private var undoing: [String: Date?] = [:]
    private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    #if DEBUG
        /// Showing made-up reminders (`debugFillSample`), which a refresh mustn't replace.
        @ObservationIgnored var usesSample = false
    #endif

    @ObservationIgnored private let reader = RemindersReader()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var fetching = false
    @ObservationIgnored private var refetch = false
    @ObservationIgnored private var clearTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastSave: Task<Void, Never>?
    @ObservationIgnored private var hadAccess = false
    /// Times access went away, so the reader makes a fresh store after a new grant.
    @ObservationIgnored private var revocations = 0

    private static let undoFor = Duration.seconds(4)

    /// Asks the first time; once answered, macOS won't ask again, so System Settings opens.
    func requestAccess() {
        guard EKEventStore.authorizationStatus(for: .reminder) == .notDetermined else {
            Permission.reminders.openSettings()
            return
        }
        Task {
            _ = try? await EKEventStore().requestFullAccessToReminders()
            access = EKEventStore.authorizationStatus(for: .reminder)
            refresh()
        }
    }

    func refreshIfStale() {
        let changed = dirty || EKEventStore.authorizationStatus(for: .reminder) != access
        guard RefreshRule.calendar.isDue(lastRefresh: lastRefresh, now: .now, dirty: changed) else { return }
        refresh()
    }

    func refresh() {
        #if DEBUG
            if usesSample { return }
        #endif
        access = EKEventStore.authorizationStatus(for: .reminder)
        dirty = false
        guard access == .fullAccess else {
            items = []
            justDone = []
            undoing = [:]
            loaded = false
            failed = false
            lastRefresh = nil
            if hadAccess { revocations += 1 }
            hadAccess = false
            return
        }
        lastRefresh = .now
        hadAccess = true
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dirty = true
                    self?.refreshIfStale()
                }
            }
        }
        guard !fetching else {
            refetch = true
            return
        }
        fetching = true
        let revocations = revocations
        Task {
            let started = Date.now
            let fetched = await reader.open(revocations: revocations)
            fetching = false
            if access == .fullAccess {
                failed = fetched == nil
                if let fetched {
                    loaded = true
                    items = Self.merge(
                        ReminderList.ordered(fetched, now: .now), keeping: justDone, holding: Set(undoing.keys),
                        from: items)
                    // Saved before this read began: the read has them as they are now.
                    undoing = undoing.filter { _, saved in saved.map { $0 > started } ?? true }
                }
            }
            if refetch {
                refetch = false
                refresh()
            }
        }
    }

    /// Ones just ticked off stay where they were until their Undo runs out, rather than jumping
    /// to the end of the list. Ones being put back stay too, until a read has them again.
    private static func merge(
        _ fresh: [ReminderItem], keeping done: Set<String>, holding undoing: Set<String>, from old: [ReminderItem]
    ) -> [ReminderItem] {
        var merged = fresh.filter { !done.contains($0.id) }
        let present = Set(merged.map(\.id))
        for (index, item) in old.enumerated()
        where done.contains(item.id) || (undoing.contains(item.id) && !present.contains(item.id)) {
            merged.insert(item, at: min(index, merged.count))
        }
        return merged
    }

    /// Saves to Reminders one after another, so an Undo clicked straight after a tick is
    /// always saved after it.
    private func save(_ id: String, done: Bool) async -> Bool {
        let previous = lastSave
        let save = Task { [reader] in
            await previous?.value
            return await reader.setCompleted(id, done)
        }
        lastSave = Task { _ = await save.value }
        return await save.value
    }

    func complete(_ item: ReminderItem) {
        justDone.insert(item.id)
        Task {
            // Not saved (the reminder went meanwhile): it comes back as it is in Reminders.
            if await !save(item.id, done: true) { tickFailed(item) }
        }
        clearTasks[item.id]?.cancel()
        clearTasks[item.id] = Task { [weak self] in
            try? await Task.sleep(for: Self.undoFor)
            guard !Task.isCancelled, let self else { return }
            self.justDone.remove(item.id)
            self.items.removeAll { $0.id == item.id }
            self.clearTasks[item.id] = nil
            // A repeating reminder's next one has the same id and was held back while this
            // one could be undone; reading again brings it in.
            self.refresh()
        }
    }

    func undo(_ item: ReminderItem) {
        clearTasks[item.id]?.cancel()
        clearTasks[item.id] = nil
        justDone.remove(item.id)
        undoing[item.id] = .some(nil)
        Task {
            _ = await save(item.id, done: false)
            undoing[item.id] = .some(.now)
            refresh()
        }
    }

    private func tickFailed(_ item: ReminderItem) {
        clearTasks[item.id]?.cancel()
        clearTasks[item.id] = nil
        justDone.remove(item.id)
        refresh()
    }

    /// Opens Reminders.
    func openApp() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// EventKit hands fetched reminders to a callback on its own queue. `@unchecked Sendable` is
/// safe here: the array is built by EventKit, passed over once, and only touched inside
/// `RemindersReader` afterwards, never by the callback again.
private final class FetchedReminders: @unchecked Sendable {
    let reminders: [EKReminder]

    init(_ reminders: [EKReminder]) {
        self.reminders = reminders
    }
}

/// Reads and ticks off reminders off the main actor. It keeps the reminders it last read, so
/// ticking one off changes that very reminder, and the ones it ticked off, since a later read
/// (of open reminders only) no longer has them for Undo. Its store is made again after access
/// went, as `CalendarReader`'s is.
private actor RemindersReader {
    private var store: EKEventStore?
    private var storeRevocations = 0
    private var reminders: [String: EKReminder] = [:]
    private var ticked: [String: EKReminder] = [:]
    /// Counts reads: one that started before a later one finishes is dropped, so an older
    /// copy of a reminder never replaces a newer one.
    private var reads = 0

    /// The open reminders, or nil when Reminders couldn't be read.
    func open(revocations: Int) async -> [ReminderItem]? {
        if storeRevocations != revocations {
            store = nil
            reminders = [:]
            ticked = [:]
            storeRevocations = revocations
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        reads += 1
        let read = reads
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        let batch: FetchedReminders? = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0.map(FetchedReminders.init)) }
        }
        guard let fetched = batch?.reminders else { return nil }
        if read == reads {
            reminders = Dictionary(
                fetched.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return fetched.map(Self.item)
    }

    /// False when the reminder isn't known or couldn't be saved.
    func setCompleted(_ id: String, _ done: Bool) -> Bool {
        guard let store, let reminder = done ? reminders[id] : ticked[id] ?? reminders[id] else { return false }
        reminder.isCompleted = done
        do {
            try store.save(reminder, commit: true)
        } catch {
            reminder.isCompleted = !done
            return false
        }
        if done { ticked[id] = reminder } else { ticked[id] = nil }
        return true
    }

    private static func item(_ reminder: EKReminder) -> ReminderItem {
        ReminderItem(
            id: reminder.calendarItemIdentifier, title: reminder.title ?? "Reminder", due: due(of: reminder),
            isCompleted: reminder.isCompleted, list: reminder.calendar?.title ?? "",
            listColor: reminder.calendar?.color.flatMap(Self.rgb))
    }

    private static func rgb(_ color: NSColor) -> RGB? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return RGB(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }

    /// A reminder due on a day with no time is due by the end of that day, so it isn't
    /// overdue all morning.
    private static func due(of reminder: EKReminder) -> Date? {
        guard let components = reminder.dueDateComponents, let date = Calendar.current.date(from: components) else {
            return nil
        }
        guard components.hour == nil else { return date }
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

/// Runs the synchronous week query off the main actor. Its store is made on first use, after
/// access is granted, and made again after access went, so a later grant starts from a fresh one.
private actor CalendarReader {
    struct Week: Sendable {
        let upcoming: [CalendarStore.Event]
        /// Every event still to come this week, uncapped.
        let all: [CalendarStore.Event]
        let day: [ClosedRange<Date>]
        let today: [CalendarStore.Event]
        /// The whole seven days, finished events included, for the window's hour grid.
        let whole: [CalendarStore.Event]
    }

    private var store: EKEventStore?
    private var storeRevocations = 0

    /// `revocations` counts the times access went; it travels with the query itself, so a
    /// revoke can't be ordered after the next grant's query.
    func week(from now: Date, calendar: Calendar, revocations: Int) -> Week {
        let store = currentStore(revocations: revocations)
        let dayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStart) ?? now
        let week = store.events(matching: store.predicateForEvents(withStart: dayStart, end: weekEnd, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        let day = week.filter { !$0.isAllDay && $0.startDate < tomorrow && $0.startDate <= $0.endDate }
            .map { $0.startDate...$0.endDate }
        let all = week.filter { $0.endDate > now }.map(Self.event)
        let upcoming = all.prefix(30)
        let today = week.filter { $0.startDate < tomorrow && $0.startDate <= $0.endDate }.prefix(50).map(Self.event)
        let whole = week.prefix(300).map(Self.event)
        return Week(upcoming: Array(upcoming), all: all, day: day, today: Array(today), whole: whole)
    }

    /// Every event from `start` to `end`, finished ones included, soonest first.
    func events(from start: Date, to end: Date, revocations: Int) -> [CalendarStore.Event] {
        let store = currentStore(revocations: revocations)
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .prefix(300).map(Self.event)
    }

    private func currentStore(revocations: Int) -> EKEventStore {
        let store = storeRevocations == revocations ? self.store ?? EKEventStore() : EKEventStore()
        self.store = store
        storeRevocations = revocations
        return store
    }

    private static func event(_ event: EKEvent) -> CalendarStore.Event {
        let eventID = event.eventIdentifier ?? UUID().uuidString
        return CalendarStore.Event(
            id: Meetings.occurrenceID(eventID: eventID, start: event.startDate), eventID: eventID,
            title: event.title ?? "Event", start: event.startDate,
            end: event.endDate, isAllDay: event.isAllDay,
            color: Color(nsColor: event.calendar.color ?? .systemPurple),
            link: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
    }
}

/// Current weather from Open-Meteo (free, no key) for the Mac's approximate location.
@MainActor
@Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    struct Hour: Equatable, Identifiable {
        let hour: Int
        let temperature: Double
        let code: Int
        /// Each hour's own day or night, so evening hours don't show a sun.
        let isDay: Bool
        var id: Int { hour }
    }

    struct Reading: Equatable {
        let hours: [Hour]
        let temperature: Double
        let high: Double
        let low: Double
        let code: Int
        let isDay: Bool
        let place: String
    }

    private(set) var reading: Reading?
    private(set) var status = "Allow location to show weather"
    /// Fetching for the first time, so the card says so instead of asking for location.
    private(set) var loading = false
    /// The last try failed, so the card offers Try again.
    private(set) var failed = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var lastFetch: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Fetches at most every 30 minutes.
    func refreshIfStale() {
        if let lastFetch, Date.now.timeIntervalSince(lastFetch) < 1800, reading != nil { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: status = "Location access is off"
        default: requestLocation()
        }
    }

    /// Asks again now, after a failure.
    func retry() {
        lastFetch = nil
        refreshIfStale()
    }

    private func requestLocation() {
        loading = true
        failed = false
        status = "Getting weather…"
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Delegate callbacks arrive on the thread that created the manager: main.
        MainActor.assumeIsolated { authorizationChanged() }
    }

    private func authorizationChanged() {
        let status = manager.authorizationStatus
        if status == .authorized || status == .authorizedAlways { requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        MainActor.assumeIsolated {
            startFetch(latitude: coordinate.latitude, longitude: coordinate.longitude, location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { fail("Couldn't find your location") }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]?
        }
        let current: Current
        let daily: Daily
        let hourly: Hourly?
    }

    private func startFetch(latitude: Double, longitude: Double, location: CLLocation) {
        Task { await fetch(latitude: latitude, longitude: longitude, location: location) }
    }

    private func fetch(latitude: Double, longitude: Double, location: CLLocation) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            // About a kilometre, as precise as the location asked for and the forecast needs.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "forecast_hours", value: "5"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else {
            fail("Couldn't get the weather")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            let place = try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
            let isDayNow = response.current.is_day == 1
            let hours: [Hour] =
                response.hourly.map { hourly in
                    let count = min(hourly.time.count, hourly.temperature_2m.count, hourly.weather_code.count)
                    return (0..<count).dropFirst().prefix(4).map { index in
                        Hour(
                            // Times look like "2026-10-29T17:00".
                            hour: Int(hourly.time[index].suffix(5).prefix(2)) ?? 0,
                            temperature: hourly.temperature_2m[index], code: hourly.weather_code[index],
                            isDay: hourly.is_day.flatMap { $0.indices.contains(index) ? $0[index] == 1 : nil }
                                ?? isDayNow)
                    }
                } ?? []
            reading = Reading(
                hours: hours,
                temperature: response.current.temperature_2m,
                high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
                low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m,
                code: response.current.weather_code,
                isDay: isDayNow,
                place: place ?? ""
            )
            lastFetch = .now
            loading = false
            failed = false
        } catch {
            fail("Couldn't get the weather")
        }
    }

    private func fail(_ text: String) {
        loading = false
        failed = true
        status = text
    }
}

/// A single scratch note, saved as you type.
@MainActor
@Observable
final class NotesStore {
    /// Every note. Kept on this Mac, in Application Support, and never logged.
    private(set) var book: NoteBook
    /// The note the widget and the window's editor show.
    var selectedID: UUID?

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let read = Self.read()
        if let read {
            book = read
        } else {
            // First run of the notebook: the old single note becomes the first note.
            book = NoteBook.migrated(fromSingle: UserDefaults.standard.string(forKey: "notesText") ?? "", at: .now)
            saveNow()
            UserDefaults.standard.removeObject(forKey: "notesText")
        }
        selectedID = book.sorted.first?.id
    }

    var selected: Note? { selectedID.flatMap(book.note) }

    /// The selected note's text, for the editors. Typing with no note starts one.
    var text: String {
        get { selected?.body ?? "" }
        set {
            if let id = selectedID, book.note(id) != nil {
                book.update(id, body: newValue, at: .now)
            } else {
                guard !newValue.isEmpty else { return }
                selectedID = book.add(body: newValue, at: .now)
            }
            save()
        }
    }

    @discardableResult
    func newNote() -> UUID {
        // An empty note already waiting is reused rather than piling up blank ones.
        if let blank = book.notes.first(where: \.isEmpty) {
            selectedID = blank.id
            return blank.id
        }
        let id = book.add(at: .now)
        selectedID = id
        save()
        return id
    }

    /// Removes a note and returns it, for Undo.
    @discardableResult
    func remove(_ id: UUID) -> Note? {
        let note = book.note(id)
        book.remove(id)
        if selectedID == id { selectedID = book.sorted.first?.id }
        save()
        return note
    }

    func restore(_ note: Note) {
        book.restore(note)
        selectedID = note.id
        save()
    }

    func togglePin(_ id: UUID) {
        book.togglePin(id)
        save()
    }

    // MARK: Saving

    private static var file: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(AppSupport.folderName(bundleID: Bundle.main.bundleIdentifier))
            .appendingPathComponent("notes.json")
    }

    private static func read() -> NoteBook? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(NoteBook.self, from: data)
    }

    /// Saves half a second after typing stops, so each key press isn't a write.
    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        let url = Self.file
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(book).write(to: url, options: .atomic)
        } catch {
            Logger(subsystem: "com.ayomideodewale.wisp", category: "Notes")
                .error("Couldn't save notes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if DEBUG
    // Made-up events and reminders, so the window's pages can be checked without Calendar or
    // Reminders access. Never in release builds.
    extension CalendarStore {
        func debugFillSample() {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            func at(_ day: Int, _ hour: Double) -> Date {
                today.addingTimeInterval(Double(day) * 86_400 + hour * 3_600)
            }
            let samples: [(String, Int, Double, Double, Color)] = [
                ("Morning focus", 0, 8, 8.5, .green), ("Design review", 0, 9, 10, .purple),
                ("Lunch", 0, 13, 14, .blue), ("Gym", 0, 16, 17, .orange), ("Standup", 1, 9.5, 9.75, .purple),
                ("Pairing", 1, 11, 12.5, .purple), ("Dentist", 2, 15, 16, .orange), ("1:1", 2, 15.5, 16.5, .blue),
                ("Planning", 3, 10, 12, .green), ("Guitar", 4, 18, 19, .blue), ("Review", 5, 14, 15, .red),
            ]
            let events = samples.enumerated().map { index, sample in
                Event(
                    id: "sample-\(index)", eventID: "sample-\(index)", title: sample.0, start: at(sample.1, sample.2),
                    end: at(sample.1, sample.3), isAllDay: false, color: sample.4,
                    link: index == 1 ? URL(string: "https://example.com") : nil)
            }
            let allDay = Event(
                id: "sample-day", eventID: "sample-day", title: "Holiday", start: at(2, 0), end: at(3, 0),
                isAllDay: true, color: .teal, link: nil)
            usesSample = true
            access = .fullAccess
            wholeWeek = events + [allDay]
            week = wholeWeek
            upcoming = wholeWeek.filter { $0.end > .now }
            todayEvents = events.filter { calendar.isDateInToday($0.start) }
            loaded = true
        }
    }

    extension RemindersStore {
        func debugFillSample() {
            let now = Date.now
            usesSample = true
            access = .fullAccess
            loaded = true
            let work = RGB(red: 1, green: 0.55, blue: 0.2)
            let personal = RGB(red: 0.55, green: 0.45, blue: 1)
            items = [
                ReminderItem(
                    id: "r1", title: "Send invoice", due: now.addingTimeInterval(-86_400), isCompleted: false,
                    list: "Work", listColor: work),
                ReminderItem(
                    id: "r2", title: "Call the bank", due: now.addingTimeInterval(3_600), isCompleted: false,
                    list: "Personal", listColor: personal),
                ReminderItem(
                    id: "r3", title: "Book flights", due: now.addingTimeInterval(4 * 86_400), isCompleted: false,
                    list: "Travel", listColor: RGB(red: 0.3, green: 0.6, blue: 1)),
                ReminderItem(
                    id: "r4", title: "Read 20 pages", due: nil, isCompleted: false, list: "Personal",
                    listColor: personal),
            ]
        }
    }
#endif

#if DEBUG
    extension NotesStore {
        /// A few made-up notes in the Dev app's notebook when it has none, for checking pages.
        func debugFillSample() {
            guard book.notes.isEmpty else { return }
            for body in [
                "Trip plan\nTwo weeks, three stops, beaches last.\n- Book flights\n- Reserve the hotel",
                "Product ideas\nA notch timer that knows your meetings.",
                "Reading list\nDeep Work, The Design of Everyday Things",
            ] {
                newNote()
                text = body
            }
        }
    }
#endif

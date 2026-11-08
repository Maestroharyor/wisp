import CoreLocation
import Darwin
import EventKit
import Foundation
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
    /// Every timed event today, including finished ones, for the Day Progress widget.
    private(set) var dayEvents: [ClosedRange<Date>] = []
    /// Every event today with its title, finished and all-day ones included, for the window's
    /// Day Progress page.
    private(set) var todayEvents: [Event] = []
    private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

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
    /// Called on the main actor each time a fresh week lands.
    @ObservationIgnored var onWeekLoaded: () -> Void = {}

    func requestAccess() {
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

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event)
        dirty = false
        guard access == .fullAccess else {
            // Access was revoked: stop showing (and offering Join cards for) the cached week.
            upcoming = []
            dayEvents = []
            todayEvents = []
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
                dayEvents = week.day
                todayEvents = week.today
                onWeekLoaded()
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

/// Runs the synchronous week query off the main actor. Its store is made on first use, after
/// access is granted, and made again after access went, so a later grant starts from a fresh one.
private actor CalendarReader {
    struct Week: Sendable {
        let upcoming: [CalendarStore.Event]
        let day: [ClosedRange<Date>]
        let today: [CalendarStore.Event]
    }

    private var store: EKEventStore?
    private var storeRevocations = 0

    /// `revocations` counts the times access went; it travels with the query itself, so a
    /// revoke can't be ordered after the next grant's query.
    func week(from now: Date, calendar: Calendar, revocations: Int) -> Week {
        let store = storeRevocations == revocations ? self.store ?? EKEventStore() : EKEventStore()
        self.store = store
        storeRevocations = revocations
        let dayStart = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: dayStart) ?? now
        let week = store.events(matching: store.predicateForEvents(withStart: dayStart, end: weekEnd, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        let day = week.filter { !$0.isAllDay && $0.startDate < tomorrow && $0.startDate <= $0.endDate }
            .map { $0.startDate...$0.endDate }
        let upcoming = week.filter { $0.endDate > now }.prefix(30).map(Self.event)
        let today = week.filter { $0.startDate < tomorrow && $0.startDate <= $0.endDate }.prefix(50).map(Self.event)
        return Week(upcoming: Array(upcoming), day: day, today: Array(today))
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
        default: manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Delegate callbacks arrive on the thread that created the manager: main.
        MainActor.assumeIsolated { authorizationChanged() }
    }

    private func authorizationChanged() {
        let status = manager.authorizationStatus
        if status == .authorized || status == .authorizedAlways { manager.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        MainActor.assumeIsolated {
            startFetch(latitude: coordinate.latitude, longitude: coordinate.longitude, location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        MainActor.assumeIsolated { status = "Location unavailable" }
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
            URLQueryItem(name: "latitude", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "forecast_hours", value: "5"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return }
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
        } catch {
            status = "Weather unavailable"
        }
    }
}

/// A single scratch note, saved as you type.
@MainActor
@Observable
final class NotesStore {
    var text: String {
        didSet { UserDefaults.standard.set(text, forKey: "notesText") }
    }

    init() {
        text = UserDefaults.standard.string(forKey: "notesText") ?? ""
    }
}

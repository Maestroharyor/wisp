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

/// Today's next calendar events, read through EventKit after the user allows it.
@MainActor
@Observable
final class CalendarStore {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        /// The event's calendar colour.
        let color: Color
    }

    private(set) var events: [Event] = []
    /// Every timed event today, including finished ones, for the Day Progress widget.
    private(set) var dayEvents: [ClosedRange<Date>] = []
    private(set) var access: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            access = EKEventStore.authorizationStatus(for: .event)
            refresh()
        }
    }

    func refresh() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard access == .fullAccess else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        let now = Date.now
        let dayStart = Calendar.current.startOfDay(for: now)
        let end = dayStart.addingTimeInterval(86400)
        let today = store.events(matching: store.predicateForEvents(withStart: dayStart, end: end, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
        dayEvents = today.filter { !$0.isAllDay && $0.startDate <= $0.endDate }.map { $0.startDate...$0.endDate }
        events =
            today
            .filter { $0.endDate > now }
            .prefix(3)
            .map {
                Event(
                    id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event", start: $0.startDate,
                    end: $0.endDate, isAllDay: $0.isAllDay,
                    color: Color(nsColor: $0.calendar.color ?? .systemPurple))
            }
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
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "forecast_hours", value: "5"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            let place = try? await CLGeocoder().reverseGeocodeLocation(location).first?.locality
            let hourly = response.hourly
            let hours = (hourly.map { zip(zip($0.time, $0.temperature_2m), $0.weather_code) } ?? zip(zip([], []), []))
                .dropFirst()
                .prefix(4)
                .map { pair, code in
                    // Times look like "2026-10-29T17:00".
                    Hour(hour: Int(pair.0.suffix(5).prefix(2)) ?? 0, temperature: pair.1, code: code)
                }
            reading = Reading(
                hours: Array(hours),
                temperature: response.current.temperature_2m,
                high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
                low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m,
                code: response.current.weather_code,
                isDay: response.current.is_day == 1,
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

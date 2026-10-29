import Foundation

/// WMO weather interpretation codes, as returned by Open-Meteo.
public enum WeatherCode {
    public static func describe(_ code: Int, isDay: Bool) -> (title: String, symbol: String) {
        switch code {
        case 0: ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1, 2: ("Partly cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: ("Cloudy", "cloud.fill")
        case 45, 48: ("Fog", "cloud.fog.fill")
        case 51, 53, 55, 56, 57: ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67, 80, 81, 82: ("Rain", "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86: ("Snow", "cloud.snow.fill")
        case 95, 96, 99: ("Thunderstorm", "cloud.bolt.rain.fill")
        default: ("Unknown", "cloud.fill")
        }
    }
}

/// Cumulative CPU ticks across all cores, from host_statistics(HOST_CPU_LOAD_INFO).
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }

    /// Busy fraction between two samples, 0...1.
    public static func usage(from before: CPUTicks, to after: CPUTicks) -> Double {
        guard after.total > before.total, after.busy >= before.busy else { return 0 }
        return Double(after.busy - before.busy) / Double(after.total - before.total)
    }
}

public struct MemoryUsage: Sendable, Equatable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64

    public init(usedBytes: UInt64, totalBytes: UInt64) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

/// Compact ages for clipboard cards: "now", "5m", "2h", "3d".
public enum RelativeAge {
    public static func short(from date: Date, to now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }
}

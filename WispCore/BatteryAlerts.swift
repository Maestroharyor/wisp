import Foundation

public struct BatteryState: Sendable, Equatable {
    public var percent: Int
    public var isPluggedIn: Bool
    public var isCharging: Bool

    public init(percent: Int, isPluggedIn: Bool, isCharging: Bool) {
        self.percent = percent
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
    }
}

public enum BatteryEvent: Sendable, Equatable {
    case pluggedIn
    case unplugged
    case full
    case low(Int)
}

/// Turns consecutive battery readings into the moments worth showing.
public enum BatteryAlerts {
    public static let lowThresholds = [20, 10]

    public static func events(
        from previous: BatteryState?, to current: BatteryState, thresholds: [Int] = lowThresholds
    ) -> [BatteryEvent] {
        guard let previous else { return [] }
        var events: [BatteryEvent] = []
        if !previous.isPluggedIn, current.isPluggedIn { events.append(.pluggedIn) }
        if previous.isPluggedIn, !current.isPluggedIn { events.append(.unplugged) }
        if current.isPluggedIn, previous.percent < 100, current.percent >= 100 { events.append(.full) }
        if !current.isPluggedIn {
            for threshold in thresholds where previous.percent > threshold && current.percent <= threshold {
                events.append(.low(threshold))
            }
        }
        return events
    }
}

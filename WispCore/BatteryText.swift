import Foundation

/// Words for the window's Battery page: the Mac's power state, its time left, and each part of
/// an accessory, part by part (a device can report its own, left, right and case levels).
public enum BatteryText {
    public struct Part: Sendable, Equatable {
        public let label: String
        public let level: Int
        /// At or below the battery warning level, where the accessory alert fires.
        public let isLow: Bool
    }

    public static func status(_ state: BatteryState) -> String {
        state.isCharging ? "Charging" : state.isPluggedIn ? "On power" : "On battery"
    }

    /// "1h 20m to full" on power, "45m left" on battery; nil while the system doesn't know.
    public static func remaining(minutes: Int?, state: BatteryState) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let length = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return "\(length) \(state.isPluggedIn ? "to full" : "left")"
    }

    /// The device's batteries in a fixed order: its own, then left, right and case.
    public static func parts(
        of device: BluetoothDevice, lowLevel: Int = AccessoryBatteryAlerts.defaultLowLevel
    ) -> [Part] {
        let order: [(BatteryPart, String)] = [(.main, "Battery"), (.left, "Left"), (.right, "Right"), (.case, "Case")]
        return order.compactMap { part, label in
            device.battery[part].map { Part(label: label, level: $0, isLow: $0 <= lowLevel) }
        }
    }

    /// The emptiest part, which is the one worth showing first.
    public static func lowestLevel(of device: BluetoothDevice) -> Int? {
        device.battery.values.min()
    }
}

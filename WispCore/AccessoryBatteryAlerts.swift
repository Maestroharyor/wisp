import Foundation

/// Decides when a mouse, keyboard or trackpad gets a low-battery warning: once when it
/// reaches the low level (the Mac's battery warning level in Settings), then not again until
/// it has charged past `rearmLevel`. Readings wobble by a few percent, so re-arming waits for
/// a real charge.
public struct AccessoryBatteryAlerts: Sendable, Equatable {
    public static let defaultLowLevel = 20
    /// Above every warning level Settings offers (at most 30%).
    public static let rearmLevel = 50

    /// Addresses already warned about. A device that disconnects stays here, so turning
    /// it back on at the same low level doesn't warn twice.
    public private(set) var warned: Set<String> = []

    public init() {}

    /// The devices to warn about after this reading.
    public mutating func check(_ devices: [BluetoothDevice], lowLevel: Int = defaultLowLevel) -> [BluetoothDevice] {
        var due: [BluetoothDevice] = []
        for device in devices {
            guard let level = device.battery[.main] else { continue }
            if level > Self.rearmLevel {
                warned.remove(device.address)
            } else if level <= lowLevel, !warned.contains(device.address) {
                warned.insert(device.address)
                due.append(device)
            }
        }
        return due
    }
}

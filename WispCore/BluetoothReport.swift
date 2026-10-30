import Foundation

public enum BatteryPart: String, Sendable, Hashable {
    case left
    case right
    case `case`
    case main
}

/// A connected Bluetooth device as `system_profiler` describes it.
public struct BluetoothDevice: Sendable, Equatable {
    public let name: String
    public let address: String
    public let kind: String
    public let battery: [BatteryPart: Int]

    public init(name: String, address: String, kind: String, battery: [BatteryPart: Int]) {
        self.name = name
        self.address = address
        self.kind = kind
        self.battery = battery
    }

    public var symbol: String {
        let lowered = (kind + " " + name).lowercased()
        if lowered.contains("airpods pro") { return "airpods.pro" }
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("headphone") || lowered.contains("headset") { return "headphones" }
        if lowered.contains("mouse") { return "computermouse.fill" }
        if lowered.contains("keyboard") { return "keyboard.fill" }
        if lowered.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lowered.contains("speaker") { return "hifispeaker.fill" }
        if lowered.contains("gamepad") || lowered.contains("controller") { return "gamecontroller.fill" }
        return "dot.radiowaves.left.and.right"
    }

    public var isHeadphones: Bool {
        ["airpods", "airpodsmax", "headphones", "airpods.pro"].contains(symbol)
    }

    /// The number worth showing first: the weaker bud, else the main battery.
    public var headline: Int? {
        let buds = [battery[.left], battery[.right]].compactMap { $0 }
        if let lowest = buds.min() { return lowest }
        return battery[.main]
    }
}

/// Parses `system_profiler SPBluetoothDataType -json`. Battery keys only appear for
/// devices that report them (AirPods, Beats, Magic accessories, some others).
public enum BluetoothReport {
    public static func connected(from json: Data) -> [BluetoothDevice]? {
        guard let root = try? JSONDecoder().decode([String: [Controller]].self, from: json),
            let controllers = root["SPBluetoothDataType"]
        else { return nil }
        return controllers.flatMap { controller in
            (controller.connected ?? []).flatMap { entry in
                entry.map { name, info in
                    BluetoothDevice(
                        name: name, address: info.address ?? name, kind: info.minorType ?? "",
                        battery: info.battery)
                }
            }
        }
    }

    public static func newlyConnected(_ devices: [BluetoothDevice], previous: Set<String>) -> [BluetoothDevice] {
        devices.filter { !previous.contains($0.address) }
    }

    private struct Controller: Decodable {
        let connected: [[String: Info]]?

        enum CodingKeys: String, CodingKey {
            case connected = "device_connected"
        }
    }

    private struct Info: Decodable {
        let address: String?
        let minorType: String?
        let left: String?
        let right: String?
        let caseLevel: String?
        let main: String?

        enum CodingKeys: String, CodingKey {
            case address = "device_address"
            case minorType = "device_minorType"
            case left = "device_batteryLevelLeft"
            case right = "device_batteryLevelRight"
            case caseLevel = "device_batteryLevelCase"
            case main = "device_batteryLevelMain"
        }

        var battery: [BatteryPart: Int] {
            let parts: [(BatteryPart, String?)] = [(.left, left), (.right, right), (.case, caseLevel), (.main, main)]
            var levels: [BatteryPart: Int] = [:]
            for (part, text) in parts {
                if let value = text.flatMap({ Int($0.filter(\.isNumber)) }) { levels[part] = value }
            }
            return levels
        }
    }
}

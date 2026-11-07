import Foundation
import IOKit
import IOKit.hid

/// Calls back when a matching HID device is connected (and, when asked, disconnected): a
/// keyboard, so the Caps Lock remap can be re-applied, or a Bluetooth accessory, so its
/// battery can be read. Uses IOKit matching notifications, which need no permission (no
/// device is opened).
@MainActor
final class HIDDeviceWatcher {
    private let matches: [[String: Any]]
    private let onConnect: @MainActor () -> Void
    private let onDisconnect: (@MainActor () -> Void)?
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    /// Any keyboard, wired or wireless.
    static let keyboards: [[String: Any]] = [
        [
            kIOProviderClassKey: kIOHIDDeviceKey,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard,
        ]
    ]

    /// Any Bluetooth or Bluetooth LE input device (mice, keyboards, trackpads, controllers).
    static let bluetooth: [[String: Any]] = [
        [
            kIOProviderClassKey: kIOHIDDeviceKey,
            kIOPropertyMatchKey: [kIOHIDTransportKey: kIOHIDTransportBluetoothValue],
        ],
        [
            kIOProviderClassKey: kIOHIDDeviceKey,
            kIOPropertyMatchKey: [kIOHIDTransportKey: kIOHIDTransportBluetoothLowEnergyValue],
        ],
    ]

    init(
        matching matches: [[String: Any]], onConnect: @escaping @MainActor () -> Void,
        onDisconnect: (@MainActor () -> Void)? = nil
    ) {
        self.matches = matches
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var notifications: [(type: String, callback: IOServiceMatchingCallback)] = [
            (kIOFirstMatchNotification, deviceMatched)
        ]
        if onDisconnect != nil { notifications.append((kIOTerminatedNotification, deviceTerminated)) }
        for matching in matches {
            for (type, callback) in notifications {
                var iterator: io_iterator_t = 0
                let status = IOServiceAddMatchingNotification(
                    port, type, matching as CFDictionary, callback, refcon, &iterator)
                guard status == KERN_SUCCESS else { return stop() }
                iterators.append(iterator)
                // Drain what is already there; this also arms the notification.
                drain(iterator)
            }
        }
    }

    func stop() {
        iterators.forEach { IOObjectRelease($0) }
        iterators = []
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }

    fileprivate func deviceConnected() {
        onConnect()
    }

    fileprivate func deviceDisconnected() {
        onDisconnect?()
    }
}

private func drain(_ iterator: io_iterator_t) {
    while case let device = IOIteratorNext(iterator), device != 0 {
        IOObjectRelease(device)
    }
}

private func deviceMatched(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    drain(iterator)
    guard let refcon else { return }
    let watcher = Unmanaged<HIDDeviceWatcher>.fromOpaque(refcon).takeUnretainedValue()
    // The notification port delivers on the main queue (set in start()).
    MainActor.assumeIsolated { watcher.deviceConnected() }
}

private func deviceTerminated(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    drain(iterator)
    guard let refcon else { return }
    let watcher = Unmanaged<HIDDeviceWatcher>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.deviceDisconnected() }
}

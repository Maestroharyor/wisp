import Foundation
import IOKit
import IOKit.hid

/// Calls back when a keyboard is connected, so the Caps Lock remap can be re-applied.
/// Uses an IOKit matching notification, which needs no permission (no device is opened).
@MainActor
final class KeyboardWatcher {
    private let onConnect: @MainActor () -> Void
    private var port: IONotificationPortRef?
    private var iterator: io_iterator_t = 0

    init(onConnect: @escaping @MainActor () -> Void) {
        self.onConnect = onConnect
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)

        let matching: [String: Any] = [
            kIOProviderClassKey: kIOHIDDeviceKey,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard,
        ]
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = IOServiceAddMatchingNotification(
            port, kIOFirstMatchNotification, matching as CFDictionary, keyboardMatched, refcon, &iterator)
        guard status == KERN_SUCCESS else { return stop() }
        // Drain the keyboards that are already attached; this also arms the notification.
        drain(iterator)
    }

    func stop() {
        if iterator != 0 {
            IOObjectRelease(iterator)
            iterator = 0
        }
        if let port {
            IONotificationPortDestroy(port)
            self.port = nil
        }
    }

    fileprivate func keyboardConnected() {
        onConnect()
    }
}

private func drain(_ iterator: io_iterator_t) {
    while case let device = IOIteratorNext(iterator), device != 0 {
        IOObjectRelease(device)
    }
}

private func keyboardMatched(refcon: UnsafeMutableRawPointer?, iterator: io_iterator_t) {
    drain(iterator)
    guard let refcon else { return }
    let watcher = Unmanaged<KeyboardWatcher>.fromOpaque(refcon).takeUnretainedValue()
    // The notification port delivers on the main queue (set in start()).
    MainActor.assumeIsolated { watcher.keyboardConnected() }
}

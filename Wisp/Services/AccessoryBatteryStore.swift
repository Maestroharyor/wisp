import Foundation
import OSLog
import Observation
import WispCore

/// Battery levels of connected Bluetooth mice, keyboards and trackpads, read from
/// `system_profiler` like the headphones' levels. It reads at start and when a Bluetooth
/// input device connects or disconnects, then every 30 minutes only while accessories are
/// listed, so a Mac without any pays nothing after launch. Warns once per device at `lowLevel`.
@MainActor
@Observable
final class AccessoryBatteryStore {
    private(set) var devices: [BluetoothDevice] = []

    @ObservationIgnored var onLow: (BluetoothDevice) -> Void = { _ in }
    /// The warning level, read at each check so a change in Settings applies to the next reading.
    @ObservationIgnored var lowLevel: () -> Int = { AccessoryBatteryAlerts.defaultLowLevel }
    @ObservationIgnored private var alerts = AccessoryBatteryAlerts()
    @ObservationIgnored private var poll: Task<Void, Never>?
    /// A read that is waiting or running.
    @ObservationIgnored private var lookup: Task<Void, Never>?
    /// True while `system_profiler` runs; a refresh asked for then waits for it to finish.
    @ObservationIgnored private var reading = false
    @ObservationIgnored private var readAgain: Duration?
    @ObservationIgnored private var watcher: HIDDeviceWatcher?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "accessories")

    private static let interval: Duration = .seconds(30 * 60)

    func start() {
        guard watcher == nil else { return }
        let watcher = HIDDeviceWatcher(
            matching: HIDDeviceWatcher.bluetooth,
            onConnect: { [weak self] in self?.refresh(after: .seconds(3)) },
            onDisconnect: { [weak self] in self?.refresh(after: .seconds(1)) })
        watcher.start()
        self.watcher = watcher
        // Starting the watcher drains attached devices without a callback, so read once now.
        refresh(after: .zero)
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        poll?.cancel()
        poll = nil
        lookup?.cancel()
        lookup = nil
        reading = false
        readAgain = nil
        devices = []
    }

    /// One device can connect as several HID interfaces, so bursts collapse into one read.
    /// The wait gives a newly connected device time to report its level.
    private func refresh(after delay: Duration) {
        if reading {
            readAgain = min(readAgain ?? delay, delay)
            return
        }
        lookup?.cancel()
        lookup = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.reading = true
            let found = await Self.read()
            // Cancelled means stop() ran and already reset the state.
            guard !Task.isCancelled else { return }
            self.reading = false
            self.lookup = nil
            if let found { self.apply(found) }
            if let again = self.readAgain {
                self.readAgain = nil
                self.refresh(after: again)
            }
        }
    }

    private func apply(_ found: [BluetoothDevice]) {
        devices = found
        alerts.check(found, lowLevel: lowLevel()).forEach { onLow($0) }
        log.debug("read \(found.count, privacy: .public) accessory batteries")
        updatePoll()
    }

    private func updatePoll() {
        guard !devices.isEmpty else {
            poll?.cancel()
            poll = nil
            return
        }
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled, let self else { return }
                // A connect read already on its way covers this one.
                if self.lookup == nil { self.refresh(after: .zero) }
            }
        }
    }

    private nonisolated static func read() async -> [BluetoothDevice]? {
        guard
            let output = try? await ProcessRunner.run(
                "/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: .seconds(10)),
            let devices = BluetoothReport.connected(from: Data(output.utf8))
        else { return nil }
        return BluetoothReport.accessories(devices)
    }
}

import Foundation
import IOKit.ps
import Observation
import WispCore

/// Battery level and power source, from IOKit power-source notifications.
@MainActor
@Observable
final class BatteryMonitor {
    private(set) var state: BatteryState?
    /// Minutes to empty or full, when the system knows.
    private(set) var minutesRemaining: Int?
    private(set) var hasBattery = false

    @ObservationIgnored var onEvent: (BatteryEvent, BatteryState) -> Void = { _, _ in }
    @ObservationIgnored private var source: CFRunLoopSource?

    func start() {
        read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(batteryChanged, context)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    fileprivate func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }

            hasBattery = true
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            let next = BatteryState(
                percent: Int((Double(current) / Double(max) * 100).rounded()),
                isPluggedIn: plugged,
                isCharging: charging
            )
            let key = plugged ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            minutesRemaining = (description[key] as? Int).flatMap { $0 > 0 ? $0 : nil }

            let events = BatteryAlerts.events(from: state, to: next)
            state = next
            events.forEach { onEvent($0, next) }
            return
        }
    }
}

private func batteryChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
    // Delivered on the main run loop, where the source was added.
    MainActor.assumeIsolated { monitor.read() }
}

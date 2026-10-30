import CoreAudio
import Foundation
import OSLog
import WispCore

/// Notices Bluetooth headphones becoming the sound output (AirPods connecting, say) and
/// reads their battery levels from `system_profiler`. Watching the output device needs
/// no Bluetooth permission; the profiler runs once per connection, off the main thread.
@MainActor
final class HeadphoneMonitor {
    var onConnect: (BluetoothDevice) -> Void = { _ in }

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var block: AudioObjectPropertyListenerBlock?
    private var lastOutput: AudioObjectID?
    private var lookup: Task<Void, Never>?
    private let log = Logger(subsystem: "com.maestro.wisp", category: "headphones")

    func start() {
        guard block == nil else { return }
        lastOutput = SystemVolume.defaultOutput
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
        block = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    func stop() {
        lookup?.cancel()
        guard let block else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        self.block = nil
    }

    private func outputChanged() {
        guard let device = SystemVolume.defaultOutput, device != lastOutput else { return }
        lastOutput = device
        guard Self.isBluetooth(device) else { return }
        let name = Self.name(of: device) ?? "Headphones"
        lookup?.cancel()
        lookup = Task { [weak self] in
            // Battery levels show up a moment after the audio route switches.
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            let found = await Self.profiledDevice(named: name)
            guard !Task.isCancelled else { return }
            self?.onConnect(found ?? BluetoothDevice(name: name, address: name, kind: "Headphones", battery: [:]))
        }
    }

    private nonisolated static func profiledDevice(named name: String) async -> BluetoothDevice? {
        guard
            let output = try? await ProcessRunner.run(
                "/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: .seconds(10)),
            let devices = BluetoothReport.connected(from: Data(output.utf8))
        else { return nil }
        // Without a name match, only take a device that is itself headphones, so a
        // keyboard's battery never shows as the headphones'.
        return devices.first { $0.name == name } ?? devices.first { $0.isHeadphones && !$0.battery.isEmpty }
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let transport: UInt32? = SystemVolume.read(device, address)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr,
            let value = name?.takeRetainedValue()
        else { return nil }
        return value as String
    }
}

import CoreAudio
import Foundation
import Observation

/// Whether any app is using the default microphone (a call, a recording) and which apps,
/// checked every two seconds through CoreAudio, plus a mute toggle for it. Wisp never records.
@MainActor
@Observable
final class MicrophoneMonitor {
    private(set) var inUse = false
    private(set) var since: Date?
    private(set) var muted = false
    /// Bundle ids of the apps recording from any input right now (empty when macOS doesn't say).
    private(set) var inputApps: [String] = []

    @ObservationIgnored var onChange: (Bool) -> Void = { _ in }
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Mutes the input where the device supports it; otherwise turns its volume to zero
    /// and back.
    func toggleMute() {
        guard let device = Self.defaultInput else { return }
        let next = !muted
        if SystemVolume.write(device, Self.muteAddress, UInt32(next ? 1 : 0)) {
            muted = next
        } else if SystemVolume.write(device, Self.volumeAddress, Float32(next ? 0 : restoreVolume)) {
            muted = next
        }
    }

    @ObservationIgnored private var restoreVolume: Float32 = 0.75

    private func poll() {
        guard let device = Self.defaultInput else { return }
        let running: UInt32? = SystemVolume.read(device, Self.runningAddress)
        let now = (running ?? 0) != 0
        if let volume: Float32 = SystemVolume.read(device, Self.volumeAddress), volume > 0 { restoreVolume = volume }
        if let mute: UInt32 = SystemVolume.read(device, Self.muteAddress) { muted = mute != 0 }
        // Which apps only matters while the mic is on; the list is read only then.
        let apps = now ? Self.appsUsingInput() : []
        guard now != inUse || apps != inputApps else { return }
        if now != inUse { since = now ? .now : nil }
        inUse = now
        inputApps = apps
        onChange(now)
    }

    /// CoreAudio's per-process view (macOS 14): the processes with an input stream running.
    private static func appsUsingInput() -> [String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return [] }
        return processes.compactMap { process in
            let running: UInt32? = SystemVolume.read(process, runningInputAddress)
            guard running == 1, let id: Unmanaged<CFString> = SystemVolume.read(process, bundleIDAddress) else {
                return nil
            }
            let bundleID = id.takeRetainedValue() as String
            return bundleID.isEmpty ? nil : bundleID
        }
        .sorted()
    }

    private static let runningInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyIsRunningInput,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let bundleIDAddress = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyBundleID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var defaultInput: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static let runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
}

import CoreAudio
import Foundation
import OSLog
import Observation
import WispCore

/// Whether any app is using the default microphone (a call, a recording) and which apps,
/// checked every two seconds through CoreAudio and whenever the default input changes, plus
/// a mute toggle for it. Wisp never records.
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
    @ObservationIgnored private var inputListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var lastDevice: AudioObjectID?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "microphone")

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        // Unplugging a mic changes the default input; checking then clears the pill at once.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        inputListener = listener
        var address = Self.defaultInputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
    }

    func stop() {
        task?.cancel()
        task = nil
        if let inputListener {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, inputListener)
            self.inputListener = nil
        }
        update(inUse: false, apps: [])
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
        let device = Self.defaultInput
        if device != lastDevice {
            lastDevice = device
            log.debug("Default input: \(device.flatMap(Self.uid) ?? "none", privacy: .public)")
        }
        guard let device else {
            update(inUse: false, apps: [])
            return
        }
        let running: UInt32? =
            SystemVolume.read(device, Self.runningAddress) ?? SystemVolume.read(device, Self.runningAnywhereAddress)
        if let volume: Float32 = SystemVolume.read(device, Self.volumeAddress), volume > 0 { restoreVolume = volume }
        if let mute: UInt32 = SystemVolume.read(device, Self.muteAddress) { muted = mute != 0 }
        let input = Self.processesUsingInput()
        let now = MicState.inUse(hasInputDevice: true, deviceRunning: (running ?? 0) != 0, inputProcesses: input)
        update(inUse: now, apps: now ? MicState.apps(input ?? []) : [])
    }

    private func update(inUse now: Bool, apps: [String]) {
        guard now != inUse || apps != inputApps else { return }
        if now != inUse { since = now ? .now : nil }
        inUse = now
        inputApps = apps
        onChange(now)
    }

    /// CoreAudio's per-process view (macOS 14): the bundle ids of the processes with an input
    /// stream running, "" for one without. Nil when the list can't be read.
    private static func processesUsingInput() -> [String]? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return nil }
        return processes.compactMap { process in
            let running: UInt32? = SystemVolume.read(process, runningInputAddress)
            guard running == 1 else { return nil }
            guard let id: Unmanaged<CFString> = SystemVolume.read(process, bundleIDAddress) else { return "" }
            return id.takeRetainedValue() as String
        }
    }

    /// The device's UID, for diagnosing which mic the monitor reads. Names no person.
    private static func uid(_ device: AudioObjectID) -> String? {
        guard let id: Unmanaged<CFString> = SystemVolume.read(device, uidAddress) else { return nil }
        return id.takeRetainedValue() as String
    }

    private static let uidAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceUID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

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

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var defaultInput: AudioObjectID? {
        var address = defaultInputAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// Only consulted when the process list can't be read (see `MicState`). Input scope where
    /// the driver offers it; the device-wide flag also counts playback.
    private static let runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let runningAnywhereAddress = AudioObjectPropertyAddress(
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

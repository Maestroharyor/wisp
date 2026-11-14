import AudioToolbox
import CoreAudio

/// Output volume and mute for the default output device, via CoreAudio.
enum SystemVolume {
    static var volume: Double? {
        guard let device = defaultOutput, let value: Float32 = read(device, volumeAddress) else { return nil }
        return Double(value)
    }

    static var isMuted: Bool {
        guard let device = defaultOutput, let value: UInt32 = read(device, muteAddress) else { return false }
        return value != 0
    }

    /// False for outputs such as HDMI or some USB DACs whose volume the system cannot set.
    static var canSetVolume: Bool {
        guard let device = defaultOutput else { return false }
        var address = volumeAddress
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    @discardableResult
    static func setVolume(_ value: Double) -> Bool {
        guard let device = defaultOutput else { return false }
        if isMuted, value > 0 { setMuted(false) }
        return write(device, volumeAddress, Float32(min(max(value, 0), 1)))
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutput else { return false }
        return write(device, muteAddress, UInt32(muted ? 1 : 0))
    }

    /// Calls `handler` on the main queue whenever the output volume or mute changes,
    /// including from other apps or the system keys. Re-attaches when the default
    /// output device changes. Returns an object that stops listening on `stop()` or when released.
    @MainActor static func observe(_ handler: @escaping @MainActor () -> Void) -> VolumeObserver {
        VolumeObserver(handler: handler)
    }

    static var defaultOutput: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static func read<Value>(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Value? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<Value>.size)
        let pointer = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.pointee
    }

    static func write(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: Float32) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static func write(_ device: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: UInt32) -> Bool {
        var address = address
        var value = value
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

/// Listens to the default output device's volume and mute until stopped or released.
@MainActor
final class VolumeObserver {
    private let handler: @MainActor () -> Void
    private var device: AudioObjectID?
    /// Still registered for default-device changes.
    private var listening = true
    // nonisolated(unsafe): read only by deinit, to remove the listeners. Both are set once in
    // init and never change, and CoreAudio only calls them on the main queue.
    nonisolated(unsafe) private let block: AudioObjectPropertyListenerBlock
    nonisolated(unsafe) private let deviceBlock: AudioObjectPropertyListenerBlock
    private var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        block = { _, _ in MainActor.assumeIsolated { handler() } }
        var attach: (() -> Void)?
        deviceBlock = { _, _ in MainActor.assumeIsolated { attach?() } }
        attach = { [weak self] in self?.attach() }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main, deviceBlock)
        self.attach()
    }

    func stop() {
        detach()
        guard listening else { return }
        listening = false
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main, deviceBlock)
    }

    /// CoreAudio holds the listener blocks, not this object, and the volume block holds the
    /// handler, so without this a released observer would keep calling it.
    deinit {
        if let device {
            for address in [SystemVolume.volumeAddress, SystemVolume.muteAddress] {
                var address = address
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
            }
        }
        if listening {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, .main, deviceBlock)
        }
    }

    private func attach() {
        detach()
        guard let device = SystemVolume.defaultOutput else { return }
        for address in [SystemVolume.volumeAddress, SystemVolume.muteAddress] {
            var address = address
            AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        }
        self.device = device
    }

    private func detach() {
        guard let device else { return }
        for address in [SystemVolume.volumeAddress, SystemVolume.muteAddress] {
            var address = address
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        self.device = nil
    }
}

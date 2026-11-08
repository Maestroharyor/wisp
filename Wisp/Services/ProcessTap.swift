import CoreAudio
import Foundation
import OSLog
import WispCore
import os

/// One app's sound, played back at its own level. A private CoreAudio process tap (macOS
/// 14.2) reads the app's output, and a private aggregate device on the current output plays
/// it scaled. The tap starts unmuted and is switched to "muted when tapped" only after sound
/// has come through this tap (see `TapArming`), so:
/// - without System Audio Recording the app keeps playing at full volume, never silent;
/// - the app is muted only while Wisp is reading the tap. If Wisp quits or crashes, or the
///   IO stops while the app is idle (`TapActivity`), the reading stops and the app plays
///   directly. Both objects are private to Wisp's process, so CoreAudio drops them with it;
///   a public tap would outlive a crash.
@MainActor
final class ProcessTap {
    let app: String
    let processes: Set<UInt32>
    private(set) var arming = TapArming()
    /// Set when the app's sound couldn't be handed over; the tap is down and should be dropped.
    private(set) var failed = false
    private(set) var running = false

    private var activity = TapActivity()
    private var appliedGain: Float
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let description: CATapDescription
    private let render: TapRender
    private let outputUID: String
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "app-volume")

    /// Nil when CoreAudio refuses any step; everything built so far is taken down again.
    /// The IO doesn't run until `update(appPlaying:seconds:)` sees the app play.
    init?(app: String, processes: Set<UInt32>, outputUID: String, gain: Float) {
        self.app = app
        self.processes = processes
        description = CATapDescription(stereoMixdownOfProcesses: processes.sorted())
        description.name = "Wisp app volume"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        render = TapRender(gain: gain)
        appliedGain = gain
        self.outputUID = outputUID
        guard build() else {
            teardown()
            return nil
        }
    }

    private func build() -> Bool {
        guard #available(macOS 14.2, *),
            check(AudioHardwareCreateProcessTap(description, &tapID), "create tap"),
            let tapUID = readTapUID(), Self.isInterleavedFloat(tapID)
        else { return false }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Wisp app volume",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]],
        ]
        guard check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &deviceID), "create device")
        else { return false }
        let render = render
        let block: AudioDeviceIOBlock = { _, input, _, output, _ in render.process(input, output) }
        return check(AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil, block), "create IO")
    }

    /// Takes everything down: stopping the device ends the reading, so the app is heard
    /// directly again even before the tap goes.
    func teardown() {
        if deviceID != kAudioObjectUnknown {
            if let procID {
                if running { AudioDeviceStop(deviceID, procID) }
                AudioDeviceDestroyIOProcID(deviceID, procID)
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        running = false
        procID = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    func setGain(_ gain: Float) {
        guard gain != appliedGain else { return }
        appliedGain = gain
        render.setGain(gain)
    }

    /// Runs the IO only while the app plays (plus a grace), and while it runs feeds the
    /// loudest sample since the last call to `TapArming`: the app's sound is handed over once
    /// this tap has heard it. Returns the arming state; `.lost` means the tap should come down.
    func update(appPlaying: Bool, seconds: Double) -> TapArming.State {
        setRunning(activity.observe(appPlaying: appPlaying, seconds: seconds))
        guard running else { return arming.state }
        let before = arming.state
        let state = arming.observe(peak: render.takePeak(), appPlaying: appPlaying, seconds: seconds)
        if state == .armed, before != .armed, !handOver() {
            failed = true
            teardown()
        }
        return state
    }

    private func setRunning(_ run: Bool) {
        guard run != running, let procID, deviceID != kAudioObjectUnknown else { return }
        if run {
            running = check(AudioDeviceStart(deviceID, procID), "start")
        } else {
            AudioDeviceStop(deviceID, procID)
            running = false
            // Peaks from before the pause say nothing about the next play.
            _ = render.takePeak()
        }
    }

    /// Mutes the app (only while Wisp reads it) and starts playing the scaled copy. If the
    /// live tap can't change, it's rebuilt muted. False when neither works; the caller takes
    /// everything down, since an unmuted app plus the copy would play twice.
    private func handOver() -> Bool {
        description.muteBehavior = .mutedWhenTapped
        if updateDescription() {
            render.arm()
            return true
        }
        let wasRunning = running
        teardown()
        guard build() else {
            Self.log.error("couldn't hand over an app's sound; leaving it untouched")
            return false
        }
        render.arm()
        if wasRunning { setRunning(true) }
        return running || !wasRunning
    }

    private func updateDescription() -> Bool {
        var address = ProcessTapAddress.global(kAudioTapPropertyDescription)
        var value = description
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        return check(status, "mute")
    }

    private func readTapUID() -> String? {
        guard let uid: Unmanaged<CFString> = SystemVolume.read(tapID, ProcessTapAddress.global(kAudioTapPropertyUID))
        else { return nil }
        return uid.takeRetainedValue() as String
    }

    /// The render loop handles interleaved 32-bit float, which is what a stereo mixdown tap gives.
    private static func isInterleavedFloat(_ tap: AudioObjectID) -> Bool {
        guard
            let format: AudioStreamBasicDescription = SystemVolume.read(
                tap, ProcessTapAddress.global(kAudioTapPropertyFormat))
        else { return false }
        let flags = format.mFormatFlags
        let ok =
            format.mFormatID == kAudioFormatLinearPCM && flags & kAudioFormatFlagIsFloat != 0
            && flags & kAudioFormatFlagIsNonInterleaved == 0 && format.mBitsPerChannel == 32
        if !ok { log.error("tap format not supported") }
        return ok
    }

    private func check(_ status: OSStatus, _ step: StaticString) -> Bool {
        guard status != noErr else { return true }
        Self.log.error("app volume \(step, privacy: .public) failed: \(status, privacy: .public)")
        return false
    }
}

enum ProcessTapAddress {
    static func global(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

/// What the audio thread shares with the main thread. The lock is only ever tried on the
/// audio thread, never waited on, so a busy main thread can't make it miss a deadline.
///
/// `@unchecked Sendable` because of `last`: only the audio thread reads or writes it (the
/// IO block runs one buffer at a time on CoreAudio's IO thread), so it never races. It
/// keeps the last gain and armed flag, so a missed try-lock repeats them instead of
/// dropping a buffer to silence.
final class TapRender: @unchecked Sendable {
    private struct Shared {
        var target: Float
        /// Until armed the tap isn't muting the app, so Wisp plays silence alongside it.
        var armed = false
        var peak: Float = 0
    }

    private struct Last {
        /// The gain the last buffer ended on, for a click-free ramp to the target.
        var gain: Float
        var armed = false
    }

    private let shared: OSAllocatedUnfairLock<Shared>
    private let last: UnsafeMutablePointer<Last>

    init(gain: Float) {
        shared = OSAllocatedUnfairLock(initialState: Shared(target: gain))
        last = UnsafeMutablePointer.allocate(capacity: 1)
        last.initialize(to: Last(gain: gain))
    }

    deinit {
        last.deinitialize(count: 1)
        last.deallocate()
    }

    func setGain(_ gain: Float) { shared.withLock { $0.target = gain } }
    func arm() { shared.withLock { $0.armed = true } }
    func takePeak() -> Float {
        shared.withLock {
            let peak = $0.peak
            $0.peak = 0
            return peak
        }
    }

    /// Runs on CoreAudio's real-time thread: no allocation, no waiting.
    func process(_ input: UnsafePointer<AudioBufferList>, _ output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        var source = UnsafeBufferPointer<Float>(start: nil, count: 0)
        var sourceChannels = 0
        // The output device's own inputs (a headset mic) come first; the tap's stream is last.
        if let buffer = inputs.last, let data = buffer.mData {
            sourceChannels = Int(buffer.mNumberChannels)
            source = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
        }
        let peak = AudioGain.peak(source)
        let start = last.pointee.gain
        // On a missed try-lock the last target and armed flag stand for this buffer.
        let fresh = shared.withLockIfAvailable { state -> (target: Float, armed: Bool) in
            state.peak = max(state.peak, peak)
            return (state.target, state.armed)
        }
        if let fresh { last.pointee = Last(gain: fresh.target, armed: fresh.armed) }
        let end = last.pointee.gain
        let armed = last.pointee.armed
        let totalChannels = outputs.reduce(0) { $0 + Int($1.mNumberChannels) }
        var firstChannel = 0
        for buffer in outputs {
            let channels = Int(buffer.mNumberChannels)
            defer { firstChannel += channels }
            guard let data = buffer.mData else { continue }
            let samples = UnsafeMutableBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            let frames = channels > 0 ? samples.count / channels : 0
            // Not armed yet: the app is still heard directly, so Wisp plays silence.
            guard armed, sourceChannels > 0, frames > 0 else {
                for index in samples.indices { samples[index] = 0 }
                continue
            }
            if totalChannels == 1 {
                AudioGain.renderMono(
                    source, channels: sourceChannels, into: samples, frames: frames, from: start, to: end)
            } else {
                AudioGain.render(
                    source, channels: sourceChannels, into: samples, channels: channels, firstChannel: firstChannel,
                    frames: frames, from: start, to: end)
            }
        }
    }
}

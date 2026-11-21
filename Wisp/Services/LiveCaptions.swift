import AVFoundation
import CoreAudio
import Foundation
import OSLog
import Speech
import WispCore

/// Captions for whatever an app is playing, made on this Mac: a read-only tap of the app's
/// sound feeds on-device speech recognition. Nothing is recorded, sent or logged, and the app's
/// sound plays on as before; the tap only listens.
@MainActor
@Observable
final class LiveCaptions {
    /// The last few lines heard, newest last.
    private(set) var lines: [String] = []
    /// Listening to an app now.
    private(set) var listening = false

    @ObservationIgnored private var buffer = LiveCaptionBuffer()
    @ObservationIgnored private var tap: CaptionTap?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var feed: AudioFeed?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var segmentStart = Date.now
    @ObservationIgnored private var lastHeard = Date.now
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var app: String?
    private static let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "LiveCaptions")

    /// What live captions can do now, given the setting and the two permissions.
    static func status(enabled: Bool) -> CaptionSource.Live {
        guard enabled else { return .off }
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        // Unknown until a tap has heard sound; a refusal shows as silence, not an error.
        let audio = SystemAudioPermission.status != false
        return speech && audio ? .ready : .needsPermission
    }

    /// Listens to `bundleID`'s sound. Calling it again for the same app does nothing.
    func start(app bundleID: String) {
        guard bundleID != app || !listening else { return }
        stop()
        guard
            let recognizer = SFSpeechRecognizer(locale: .current)
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
            recognizer.supportsOnDeviceRecognition, recognizer.isAvailable
        else {
            Self.log.notice("on-device recognition isn't available for this language")
            return
        }
        recognizer.queue = .main
        let feed = AudioFeed(Self.makeRequest())
        guard let tap = CaptionTap(app: bundleID, feed: feed) else {
            Self.log.notice("couldn't listen to the playing app")
            return
        }
        self.recognizer = recognizer
        self.feed = feed
        self.tap = tap
        app = bundleID
        listening = true
        buffer.clear()
        lines = []
        startTask()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.tick()
            }
        }
    }

    func stop() {
        clock?.cancel()
        clock = nil
        task?.cancel()
        task = nil
        tap?.teardown()
        tap = nil
        feed = nil
        recognizer = nil
        app = nil
        listening = false
    }

    private static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        // Never Apple's servers: the request fails rather than leave the Mac.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        return request
    }

    /// A new recognition request for the next stretch of sound; the words so far stay.
    private func startTask() {
        guard let recognizer, let feed else { return }
        generation += 1
        let generation = generation
        let request = Self.makeRequest()
        feed.replace(with: request)
        segmentStart = .now
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            MainActor.assumeIsolated {
                self?.received(text: text, isFinal: isFinal, failed: failed, generation: generation)
            }
        }
    }

    private func received(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard generation == self.generation else { return }
        if let text {
            buffer.update(partial: text)
            lines = buffer.lines
        }
        if isFinal || failed {
            buffer.finish()
            lines = buffer.lines
            if listening { startTask() }
        }
    }

    /// Ends a segment after a long run or a pause, so no request runs into the time limit.
    private func tick() {
        guard listening, let tap else { return }
        if tap.takePeak() > 0.01 { lastHeard = .now }
        if tap.failed {
            stop()
            return
        }
        let now = Date.now
        if LiveCaptionBuffer.restarts(
            segmentAge: now.timeIntervalSince(segmentStart), silence: now.timeIntervalSince(lastHeard))
        {
            // A pause: nothing to say until sound comes back, so don't spin requests.
            guard now.timeIntervalSince(segmentStart) > 2 else { return }
            task?.finish()
        }
    }
}

/// A private, read-only CoreAudio tap of one app's sound: an aggregate device whose input is
/// the tap, read on its IO thread and handed to the recogniser as mono buffers.
@MainActor
private final class CaptionTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let reader: TapReader
    private(set) var failed = false

    init?(app bundleID: String, feed: AudioFeed) {
        guard #available(macOS 14.2, *), let outputUID = AppVolumeStore.defaultOutputUID() else { return nil }
        let processes = AppVolumeStore.processObjects().filter { object in
            let pid: pid_t = SystemVolume.read(object, ProcessTapAddress.global(kAudioProcessPropertyPID)) ?? 0
            return AppVolumeStore.resolveApp(object: object, pid: pid) == bundleID
        }
        guard !processes.isEmpty else { return nil }
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Wisp live captions"
        description.isPrivate = true
        // Listen only: the app keeps playing exactly as it was.
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr,
            let uid: Unmanaged<CFString> = SystemVolume.read(tapID, ProcessTapAddress.global(kAudioTapPropertyUID)),
            let format: AudioStreamBasicDescription = SystemVolume.read(
                tapID, ProcessTapAddress.global(kAudioTapPropertyFormat)),
            format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
        else {
            if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
            return nil
        }
        reader = TapReader(feed: feed, sampleRate: format.mSampleRate, channels: Int(format.mChannelsPerFrame))
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Wisp live captions",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: uid.takeRetainedValue() as String, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        let reader = reader
        let block: AudioDeviceIOBlock = { _, input, _, output, _ in reader.read(input, silencing: output) }
        guard AudioHardwareCreateAggregateDevice(composition as CFDictionary, &deviceID) == noErr,
            AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, nil, block) == noErr, let procID,
            AudioDeviceStart(deviceID, procID) == noErr
        else {
            teardown()
            return nil
        }
    }

    func takePeak() -> Float { reader.takePeak() }

    func teardown() {
        if deviceID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(deviceID, procID)
                AudioDeviceDestroyIOProcID(deviceID, procID)
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }
}

/// Runs on CoreAudio's IO thread: mixes the tap's interleaved float frames to mono for the
/// recogniser and keeps the loudest sample since the main actor last asked. The lock guards
/// only the peak, which is why this can be `@unchecked Sendable`.
private final class TapReader: @unchecked Sendable {
    private let feed: AudioFeed
    private let format: AVAudioFormat?
    private let channels: Int
    private let lock = NSLock()
    private var peak: Float = 0

    init(feed: AudioFeed, sampleRate: Double, channels: Int) {
        self.feed = feed
        self.channels = max(channels, 1)
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    func read(_ input: UnsafePointer<AudioBufferList>, silencing output: UnsafeMutablePointer<AudioBufferList>) {
        // The aggregate has an output side; it plays nothing of ours.
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }
        guard let format, let first = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).first,
            let data = first.mData
        else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        let total = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let frames = total / channels
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
            let mono = pcm.floatChannelData?[0]
        else { return }
        var loudest: Float = 0
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += samples[frame * channels + channel] }
            let value = sum / Float(channels)
            mono[frame] = value
            loudest = max(loudest, abs(value))
        }
        pcm.frameLength = AVAudioFrameCount(frames)
        lock.withLock { peak = max(peak, loudest) }
        feed.append(pcm)
    }

    func takePeak() -> Float {
        lock.withLock {
            defer { peak = 0 }
            return peak
        }
    }
}

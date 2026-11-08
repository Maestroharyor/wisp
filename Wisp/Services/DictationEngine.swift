import AVFoundation
import AppKit
import OSLog
import Observation
import Speech
import WispCore

/// Push-to-talk dictation: hold the dictation key with Caps Lock, speak, let go. Speech is
/// transcribed on this Mac only (`requiresOnDeviceRecognition`); when the language can't be
/// recognised on device, dictation says so and never falls back to Apple's servers. Audio
/// lives in memory for the length of the hold and nothing is kept.
@MainActor
@Observable
final class DictationEngine {
    private(set) var phase: PushToTalk.Phase = .idle
    /// Where the current dictation goes, chosen when recording starts.
    private(set) var target: DictationTarget?
    /// Checked ahead of time (launch, Wisp coming forward, settings changes), so a key press
    /// doesn't wait on it.
    private(set) var readiness: DictationReadiness = .needsPermission

    /// Optional clean-up (filler words, punctuation) run on the transcript before it's
    /// delivered. Nil delivers the transcript as heard. The on-device AI engine plugs in here.
    @ObservationIgnored var cleanup: DictationCleanup?
    /// Where dictated text would go right now; set by the app delegate.
    @ObservationIgnored var resolveTarget: @MainActor () -> DictationTarget = { .focusedApp }
    /// Puts text into a draft box or question card. False when it has closed.
    @ObservationIgnored var deliverInWisp: @MainActor (String, DictationTarget) -> Bool = { _, _ in false }
    /// A quick press of a dictation key that also opens the shelf.
    @ObservationIgnored var onTap: @MainActor () -> Void = {}
    /// Dictation started or ended, so the microphone pill can leave Wisp's own input out.
    @ObservationIgnored var onActiveChange: @MainActor (Bool) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let activities: ActivityCenter
    @ObservationIgnored private var talk = PushToTalk(sharedWithShelf: false)
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var holdTimer: Task<Void, Never>?
    @ObservationIgnored private var finishTimer: Task<Void, Never>?
    @ObservationIgnored private var session: RecognitionSession?
    /// The app in front when recording started; text is pasted only into that app.
    @ObservationIgnored private var appAtStart: pid_t?
    /// Why the last recording couldn't start, for the notice.
    @ObservationIgnored private var unavailableMessage = ""
    /// A blocked hold on the shared key opens the shelf quietly; the first one also says why,
    /// once until dictation becomes ready again.
    @ObservationIgnored private var explainedBlockedHold = false
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "dictation")

    /// How long to wait for the final transcript after the key comes up.
    private static let finishTimeout: Duration = .seconds(3)
    /// How long after ⌘V the user's clipboard comes back. Apps read the pasteboard when they
    /// handle ⌘V, usually within a few milliseconds; 800 ms leaves room for a busy app, while
    /// a copy the user makes sooner than that is still safe because the change count moves.
    private static let restoreDelay: Duration = .milliseconds(800)

    init(preferences: Preferences, activities: ActivityCenter) {
        self.preferences = preferences
        self.activities = activities
    }

    func start() {
        if preferences.dictationEnabled { refreshReadiness() }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.preferences.dictationEnabled else { return }
                self.refreshReadiness()
            }
        }
        observePreferences()
    }

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.dictationEnabled
            _ = preferences.hotkey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.preferences.dictationEnabled { self.refreshReadiness() }
                self.observePreferences()
            }
        }
    }

    // MARK: Key

    /// A hold event from the keyboard tap, delivered after the tap callback has returned.
    func handle(_ event: HoldKey.Event) {
        switch event {
        case .down:
            if talk.phase == .idle {
                talk = PushToTalk(
                    sharedWithShelf: preferences.dictationKey.sharesShelfKey(preferences.hotkey.keyCode))
            }
            apply(talk.press(at: .now))
            if case .pressed = talk.phase { scheduleHold(after: talk.holdDelay) }
        case .up:
            holdTimer?.cancel()
            apply(talk.release(at: .now))
        case .cancel:
            holdTimer?.cancel()
            apply(talk.cancel())
        }
    }

    private func scheduleHold(after delay: TimeInterval) {
        holdTimer?.cancel()
        holdTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.apply(self.talk.holdElapsed(at: .now))
        }
    }

    private func apply(_ effect: PushToTalk.Effect) {
        switch effect {
        case .none: break
        case .tap:
            // Only the shelf: a dictation still being transcribed carries on.
            onTap()
        case .tapDiscardingRecording:
            endSession()
            target = nil
            onTap()
        case .startRecording: startRecording()
        case .finishRecording: finishRecording()
        case .discard(let reason): discard(reason)
        case .deliver(let text): deliver(text)
        }
        sync()
    }

    private func sync() {
        let wasActive = phase.isActive
        phase = talk.phase
        if phase.isActive != wasActive { onActiveChange(phase.isActive) }
    }

    // MARK: Recording

    private func startRecording() {
        // The cache can be stale (a permission granted in System Settings while Wisp stayed in
        // the background), so look again before giving up.
        if !readiness.isReady { refreshReadiness() }
        guard readiness.isReady, let recognizer, recognizer.isAvailable else {
            unavailableMessage = readiness.isReady ? DictationReadiness.onDeviceUnavailable.message : readiness.message
            if readiness == .needsPermission { Task { await requestPermissions() } }
            becameUnavailable()
            return
        }
        // Starting the audio engine stays on the main actor: AVAudioEngine and the recognition
        // request aren't Sendable, and moving them to another thread would need unchecked
        // wrappers around both. It runs after the key tap has returned, so it can't stall the tap.
        let session = RecognitionSession(recognizer: recognizer)
        session.onFinal = { [weak self] text in self?.transcribed(text) }
        session.onFailure = { [weak self] in self?.recognitionFailed() }
        do {
            try session.start()
        } catch {
            log.error("could not start the microphone: \(String(describing: error), privacy: .public)")
            unavailableMessage = "Couldn't start the microphone"
            becameUnavailable()
            return
        }
        self.session = session
        let target = resolveTarget()
        self.target = target
        appAtStart = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if target.showsPill {
            activities.post(.dictation(since: .now), slot: .dictation, duration: nil)
        }
    }

    private func becameUnavailable() {
        apply(talk.unavailable())
        guard talk.phase == .blocked, !explainedBlockedHold else { return }
        explainedBlockedHold = true
        notice(unavailableMessage, symbol: "mic.slash.fill")
    }

    private func finishRecording() {
        // The microphone is off now; the pill shouldn't say it's still listening.
        activities.remove(.dictation)
        session?.finish()
        finishTimer?.cancel()
        finishTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.finishTimeout)
            guard !Task.isCancelled, let self else { return }
            // No final result in time: use what was heard so far.
            self.transcribed(self.session?.latest ?? "")
        }
    }

    private func transcribed(_ text: String) {
        apply(talk.transcribed(text))
    }

    private func recognitionFailed() {
        // After the key is up a failure is often just "no speech": keep what was heard, if anything.
        if talk.phase == .finishing {
            transcribed(session?.latest ?? "")
        } else {
            apply(talk.failed())
        }
    }

    private func endSession() {
        finishTimer?.cancel()
        finishTimer = nil
        session?.cancel()
        session = nil
        activities.remove(.dictation)
    }

    private func discard(_ reason: PushToTalk.DiscardReason) {
        endSession()
        target = nil
        switch reason {
        case .cancelled: break
        case .tooShort: notice("Hold the key while you speak", symbol: "mic.fill")
        case .nothingHeard: notice("Didn't catch that", symbol: "mic.fill")
        case .failed: notice("Dictation stopped", symbol: "mic.slash.fill")
        case .unavailable: notice(unavailableMessage, symbol: "mic.slash.fill")
        }
    }

    // MARK: Delivery

    private func deliver(_ heard: String) {
        endSession()
        let target = self.target ?? .focusedApp
        let cleanup = self.cleanup
        Task { [weak self] in
            let text = await DictationText.finish(heard, cleanup: cleanup) ?? heard
            guard let self else { return }
            self.put(text, into: target)
            self.talk.delivered()
            self.target = nil
            self.sync()
        }
    }

    private func put(_ text: String, into target: DictationTarget) {
        switch target {
        case .focusedApp:
            let appNow = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard AccessibilityPermission.isTrusted,
                DictationPaste.action(appAtStart: appAtStart, appNow: appNow) == .paste
            else { return copy(text) }
            PasteShortcut.pasteRestoring(text, after: Self.restoreDelay)
        case .agentDraft, .questionAnswer:
            guard !deliverInWisp(text, target) else { return }
            copy(text)
        }
    }

    private func copy(_ text: String) {
        PasteShortcut.stage(text)
        notice("Dictation copied", symbol: "doc.on.clipboard")
    }

    private func notice(_ text: String, symbol: String) {
        activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: 2)
    }

    // MARK: Permissions

    func refreshReadiness() {
        let speech: DictationPermission =
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        let microphone: DictationPermission =
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .notDetermined: .notAsked
            default: .denied
            }
        // Made again each time, so a change of language in System Settings is picked up.
        let recognizer = SFSpeechRecognizer()
        recognizer?.queue = .main
        self.recognizer = recognizer
        let next = DictationReadiness.check(
            speech: speech, microphone: microphone,
            onDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false,
            hyperKey: preferences.hotkey.usesHyper, hasMicrophone: AVCaptureDevice.default(for: .audio) != nil)
        if next.isReady { explainedBlockedHold = false }
        readiness = next
    }

    /// Asks for Speech Recognition, then the microphone. Called when dictation is turned on.
    func requestPermissions() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await Self.requestSpeechAccess()
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        refreshReadiness()
    }

    /// Nonisolated because macOS calls the handler off the main thread.
    nonisolated static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// The request the microphone tap feeds. The tap appends on an audio thread while the main
/// actor may swap in a fresh request (after an early final result); the lock guards that one
/// reference, which is why this can be `@unchecked Sendable`.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request.append(buffer) }
    }

    func replace(with request: SFSpeechAudioBufferRecognitionRequest) {
        lock.withLock { self.request = request }
    }
}

/// One hold of the key: the microphone feeding on-device recognition requests.
@MainActor
private final class RecognitionSession {
    var onFinal: (String) -> Void = { _ in }
    var onFailure: () -> Void = {}
    /// The best transcript so far.
    var latest: String { transcript.text }

    private let recognizer: SFSpeechRecognizer
    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest
    private let feed: AudioFeed
    private var task: SFSpeechRecognitionTask?
    private var transcript = DictationTranscript()
    /// Bumped for each recognition task, so a replaced task's late results are ignored.
    private var generation = 0
    private var finishing = false
    private var done = false
    private var tapped = false

    enum StartError: Error {
        case noInput
    }

    init(recognizer: SFSpeechRecognizer) {
        self.recognizer = recognizer
        let request = Self.makeRequest()
        self.request = request
        feed = AudioFeed(request)
    }

    private static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        // Never Apple's servers: the request fails rather than leave the Mac.
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        return request
    }

    func start() throws {
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw StartError.noInput }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(feed))
        tapped = true
        audio.prepare()
        do {
            try audio.start()
        } catch {
            stopAudio()
            throw error
        }
        startTask()
    }

    /// Results arrive on the main queue (the recognizer's queue is set to it), which the
    /// handler relies on.
    private func startTask() {
        generation += 1
        let generation = generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            MainActor.assumeIsolated {
                self?.received(text: text, isFinal: isFinal, failed: failed, generation: generation)
            }
        }
    }

    /// The tap runs on an audio thread, so its block must not be main-actor isolated.
    private nonisolated static func tapBlock(_ feed: AudioFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.append(buffer) }
    }

    private func received(text: String?, isFinal: Bool, failed: Bool, generation: Int) {
        guard !done, generation == self.generation else { return }
        if let text { transcript.update(text) }
        if isFinal {
            transcript.commit(text ?? "")
            if finishing {
                done = true
                onFinal(transcript.text)
            } else {
                // The recognizer ended early (a long pause) while the key is still held:
                // keep that part and listen on with a fresh request.
                let next = Self.makeRequest()
                request = next
                feed.replace(with: next)
                startTask()
            }
        } else if failed {
            done = true
            onFailure()
        }
    }

    /// Stops listening and asks for the final transcript.
    func finish() {
        finishing = true
        stopAudio()
        request.endAudio()
    }

    func cancel() {
        done = true
        stopAudio()
        task?.cancel()
        task = nil
    }

    private func stopAudio() {
        if audio.isRunning { audio.stop() }
        guard tapped else { return }
        tapped = false
        audio.inputNode.removeTap(onBus: 0)
    }
}

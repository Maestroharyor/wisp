import AVFoundation
import Observation

/// The front camera for the Mirror widget. Runs only while a mirror view is on screen.
@MainActor
@Observable
final class CameraMirror {
    enum State: Equatable {
        case idle
        case denied
        case unavailable
        case running
    }

    private(set) var state: State = .idle
    @ObservationIgnored private let capture = CaptureQueue()
    var session: AVCaptureSession { capture.session }
    @ObservationIgnored private var viewers = 0
    @ObservationIgnored private var configured = false

    func attach() {
        viewers += 1
        guard viewers == 1 else { return }
        Task { await start() }
    }

    func detach() {
        viewers = max(viewers - 1, 0)
        guard viewers == 0 else { return }
        capture.stop()
        if state == .running { state = .idle }
    }

    private func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }
        guard viewers > 0 else { return }
        if !configured {
            guard let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
            else {
                state = .unavailable
                return
            }
            session.sessionPreset = .medium
            session.addInput(input)
            configured = true
        }
        await capture.start()
        state = viewers > 0 ? .running : .idle
    }
}

/// Starts and stops the session on its own queue, as AVFoundation recommends, so the
/// blocking `startRunning` never stalls the main thread.
/// `@unchecked Sendable`: AVCaptureSession isn't annotated, but start and stop are only
/// called on `queue`, and configuration happens before the first start.
private final class CaptureQueue: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.maestro.wisp.camera")

    func start() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }
}

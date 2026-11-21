import CoreGraphics
import Foundation
import ScreenCaptureKit
import WispCore
import os

enum ScreenSnapshotError: Error {
    case offScreen
    /// ScreenCaptureKit never answered, which it can do while a privacy prompt waits.
    case timedOut
}

/// One frame of part of the screen for Capture text. Unlike the region watch it captures the
/// display, so the selection can span windows. Wisp's own windows are left out. The image is
/// only returned to the caller, never saved.
enum ScreenSnapshot {
    /// `selection` is in the window server's top-left global space, in points.
    static func capture(_ selection: CGRect, timeout: Duration = .seconds(8)) async throws -> CGImage {
        try await firstOf(timeout: timeout) { try await read(selection) }
    }

    private static func read(_ selection: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let index = RegionGeometry.displayIndex(for: selection, in: content.displays.map(\.frame)),
            let source = RegionGeometry.region(selection, in: content.displays[index].frame)
        else { throw ScreenSnapshotError.offScreen }
        let own = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(
            display: content.displays[index],
            excludingApplications: content.applications.filter { $0.processID == own },
            exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        let size = RegionGeometry.textCaptureSize(for: source.size, scale: CGFloat(filter.pointPixelScale))
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? RegionCaptureError.noImage)
                }
            }
        }
    }
}

extension ScreenSnapshot {
    /// The work's result, or `timedOut` once `timeout` passes, whichever comes first. Unlike a
    /// task group it doesn't wait for work that ignores cancellation, so a capture that never
    /// returns can't hold Capture text forever.
    fileprivate static func firstOf<T: Sendable>(
        timeout: Duration, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let once = ResumeOnce<T>()
        return try await withCheckedThrowingContinuation { continuation in
            once.set(continuation)
            let job = Task {
                do { once.resume(.success(try await work())) } catch { once.resume(.failure(error)) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                job.cancel()
                once.resume(.failure(ScreenSnapshotError.timedOut))
            }
        }
    }
}

/// Resumes a continuation once, from whichever side gets there first.
private final class ResumeOnce<T: Sendable>: Sendable {
    private let state = OSAllocatedUnfairLock<CheckedContinuation<T, Error>?>(initialState: nil)

    func set(_ continuation: CheckedContinuation<T, Error>) {
        state.withLock { $0 = continuation }
    }

    func resume(_ result: Result<T, Error>) {
        let continuation = state.withLock { current -> CheckedContinuation<T, Error>? in
            defer { current = nil }
            return current
        }
        continuation?.resume(with: result)
    }
}

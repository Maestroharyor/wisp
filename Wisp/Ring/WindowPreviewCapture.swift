import CoreGraphics
import Foundation
import ScreenCaptureKit
import WispCore

/// Small live pictures of an app's windows for the ring's centre. Only used when Screen
/// Recording is already on; it never asks. The pictures stay in memory while the ring is open
/// and are never saved or logged.
actor WindowPreviewCapture {
    private var listed: [SCWindow]?

    /// A new opening looks the windows up again.
    func reset() {
        listed = nil
    }

    /// `window` as Accessibility reported it, drawn to fit a `side`-point square; nil when it
    /// isn't on screen (minimised, another Space) or can't be told apart from the others.
    func image(pid: pid_t, window: WindowSummary, side: CGFloat) async throws -> CGImage? {
        let windows = try await windows().filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
        let candidates = windows.map { CapturableWindow(id: $0.windowID, title: $0.title, frame: $0.frame) }
        guard let id = WindowMatch.best(for: window, in: candidates),
            let found = windows.first(where: { $0.windowID == id })
        else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: found)
        let size = WindowPreview.size(for: found.frame.size, fitting: side)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(size.width * scale), 1)
        configuration.height = max(Int(size.height * scale), 1)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
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

    private func windows() async throws -> [SCWindow] {
        if let listed { return listed }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        listed = content.windows
        return content.windows
    }
}

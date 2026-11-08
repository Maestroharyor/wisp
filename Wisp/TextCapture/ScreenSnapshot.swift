import CoreGraphics
import Foundation
import ScreenCaptureKit
import WispCore

enum ScreenSnapshotError: Error {
    case offScreen
}

/// One frame of part of the screen for Capture text. Unlike the region watch it captures the
/// display, so the selection can span windows. Wisp's own windows are left out. The image is
/// only returned to the caller, never saved.
enum ScreenSnapshot {
    /// `selection` is in the window server's top-left global space, in points.
    static func capture(_ selection: CGRect) async throws -> CGImage {
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

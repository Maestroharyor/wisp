import CoreGraphics
import Foundation
import ScreenCaptureKit
import WispCore

/// The window and the part of it being watched.
struct RegionTarget: Sendable, Equatable {
    let windowID: CGWindowID
    let appName: String
    /// Offset and size in points from the window's top-left corner.
    let region: CGRect
}

enum RegionCaptureError: Error {
    /// The window closed or its app quit.
    case windowGone
    /// The window shrank until the region fell outside it.
    case regionGone
    case noImage
}

/// Takes one frame of just the region with ScreenCaptureKit and reduces it to what the rule
/// needs. Nothing is kept: the image is dropped as soon as a sample returns.
///
/// An actor, so capturing, drawing and OCR run on the shared concurrency pool rather than
/// the main actor, where text recognition would stall the notch for a moment.
actor RegionCaptureSession {
    /// The shareable-content lookup lists every window, so it's redone only this often or
    /// after a failed capture, not on every check.
    private static let refreshEvery = 20

    private let target: RegionTarget
    private let readsText: Bool
    private var window: SCWindow?
    private var checksSinceRefresh = 0

    init(target: RegionTarget, readsText: Bool) {
        self.target = target
        self.readsText = readsText
    }

    func sample() async throws -> RegionWatchSample {
        let window = try await currentWindow()
        // The cached frame can be up to 20 checks old. A resize in between is tolerated: the
        // region is anchored to the top-left corner, so it only clips a little late, and a failed
        // capture refreshes it at once.
        guard let source = RegionGeometry.sourceRect(target.region, windowSize: window.frame.size) else {
            throw RegionCaptureError.regionGone
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        let grid = LuminanceFrame.gridSize(for: source.size)
        // Text needs full resolution; a pixel comparison only needs the small grid.
        let size =
            readsText ? RegionGeometry.textCaptureSize(for: source.size, scale: CGFloat(filter.pointPixelScale)) : grid
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let image: CGImage
        do {
            image = try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                    if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: error ?? RegionCaptureError.noImage)
                    }
                }
            }
        } catch {
            // The window may have moved to another display or changed; look it up again next time.
            self.window = nil
            throw error
        }
        guard let frame = Self.luminance(of: image, size: grid) else { throw RegionCaptureError.noImage }
        return RegionWatchSample(
            frame: frame, text: readsText ? Self.recognizedText(in: image) : nil, time: .now,
            pointsPerPixel: source.width / grid.width)
    }

    private func currentWindow() async throws -> SCWindow {
        checksSinceRefresh += 1
        if let window, checksSinceRefresh < Self.refreshEvery { return window }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let found = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw RegionCaptureError.windowGone
        }
        window = found
        checksSinceRefresh = 0
        return found
    }

    /// The region drawn into a grayscale bitmap of the grid size; Core Graphics averages.
    private static func luminance(of image: CGImage, size: CGSize) -> LuminanceFrame? {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? LuminanceFrame(width: width, height: height, pixels: pixels) : nil
    }

    /// On-device Vision OCR, top candidate per line, without autocorrect. A failed read gives
    /// "", which a text rule treats as the region not showing its text yet.
    private static func recognizedText(in image: CGImage) -> String {
        ImageReader.literalLines(in: image).map(\.text).joined(separator: "\n")
    }
}

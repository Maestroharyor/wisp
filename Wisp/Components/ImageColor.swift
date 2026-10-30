import AppKit
import CoreImage
import SwiftUI
import WispCore

/// The average colour of a picture (album art, the desktop picture).
enum ImageColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func average(of image: NSImage) -> RGB? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard
            let filter = CIFilter(
                name: "CIAreaAverage",
                parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
            let output = filter.outputImage
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return RGB(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension RGB {
    /// From a colour picker's choice, in sRGB.
    init?(color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }
}

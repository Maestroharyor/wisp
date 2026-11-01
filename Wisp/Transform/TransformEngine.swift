import AVFoundation
import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision
import WispCore

enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png
    case heic
    case tiff

    var id: Self { self }
    var title: String { rawValue.uppercased() }
    var ext: String { self == .jpeg ? "jpg" : rawValue }

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        }
    }
}

enum TransformOperation: String, CaseIterable, Identifiable, Sendable {
    case convert
    case compress
    case resize
    case rotate
    case removeBackground
    case removeMetadata
    case combinePDF
    case zip

    var id: Self { self }

    var title: String {
        switch self {
        case .convert: "Convert"
        case .compress: "Compress"
        case .resize: "Resize"
        case .rotate: "Rotate"
        case .removeBackground: "Remove BG"
        case .removeMetadata: "Strip Info"
        case .combinePDF: "Make PDF"
        case .zip: "Zip"
        }
    }

    var symbol: String {
        switch self {
        case .convert: "arrow.triangle.2.circlepath"
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .resize: "arrow.up.left.and.down.right.magnifyingglass"
        case .rotate: "rotate.right"
        case .removeBackground: "person.crop.rectangle.badge.plus"
        case .removeMetadata: "eye.slash"
        case .combinePDF: "doc.richtext"
        case .zip: "doc.zipper"
        }
    }
}

struct TransformOptions: Sendable, Equatable {
    var format: ImageFormat = .jpeg
    var quality: Double = 0.8
    var longestSide: Double = 2048
    /// Compress also shrinks to this longest side when set (the web ready preset).
    var compressLongestSide: Double?
    /// Degrees clockwise: 90, 180 or 270.
    var rotation: Int = 90
}

enum TransformError: LocalizedError {
    case unreadable(String)
    case writeFailed(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Couldn't read \(name)"
        case .writeFailed(let name): "Couldn't write \(name)"
        case .unsupported(let name): "\(name) isn't an image"
        }
    }
}

/// File transforms. Everything here is pure file-in, file-out and runs off the main
/// thread; outputs land next to the originals and never overwrite them.
enum TransformEngine {
    /// The files written, and the first problem if some files failed. Files already written
    /// are kept and reported even when a later one fails.
    struct Outcome: Sendable {
        var outputs: [URL]
        var problem: String?
    }

    static func run(_ operation: TransformOperation, urls: [URL], options: TransformOptions) async throws -> Outcome {
        try await Task.detached(priority: .userInitiated) {
            switch operation {
            case .combinePDF:
                return Outcome(outputs: [try combinePDF(urls)])
            case .zip:
                return Outcome(outputs: [])  // Handled by TrayStore.zip, which already runs ditto.
            default:
                var result = Outcome(outputs: [])
                for url in urls {
                    do {
                        result.outputs.append(try transformFile(url, operation: operation, options: options))
                    } catch {
                        result.problem = result.problem ?? error.localizedDescription
                    }
                }
                return result
            }
        }.value
    }

    private static func transformFile(_ url: URL, operation: TransformOperation, options: TransformOptions) throws
        -> URL
    {
        if operation == .compress, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
            throw TransformError.unsupported(url.lastPathComponent)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let sourceType = CGImageSourceGetType(source).flatMap({ UTType($0 as String) })
        else { throw TransformError.unsupported(url.lastPathComponent) }

        switch operation {
        case .convert:
            let image = try decode(source, url: url, maxPixel: nil)
            return try write(image, like: url, format: options.format, quality: options.quality, suffix: nil)
        case .compress:
            let image = try decode(source, url: url, maxPixel: options.compressLongestSide)
            let format: ImageFormat = sourceType.conforms(to: .png) ? .png : .jpeg
            return try write(image, like: url, format: format, quality: options.quality, suffix: "compressed")
        case .resize:
            let image = try decode(source, url: url, maxPixel: options.longestSide)
            return try write(image, like: url, format: format(of: sourceType), quality: 0.9, suffix: "resized")
        case .rotate:
            let image = try rotate(try decode(source, url: url, maxPixel: nil), degrees: options.rotation)
            return try write(image, like: url, format: format(of: sourceType), quality: 0.92, suffix: "rotated")
        case .removeMetadata:
            // Re-encoding pixels without properties drops EXIF, GPS and other metadata.
            let image = try decode(source, url: url, maxPixel: nil)
            return try write(image, like: url, format: format(of: sourceType), quality: 0.95, suffix: "clean")
        case .removeBackground:
            let image = try removeBackground(try decode(source, url: url, maxPixel: nil), name: url.lastPathComponent)
            return try write(image, like: url, format: .png, quality: 1, suffix: "cutout")
        case .combinePDF, .zip:
            return url
        }
    }

    private static func format(of type: UTType) -> ImageFormat {
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .heic) { return .heic }
        if type.conforms(to: .tiff) { return .tiff }
        return .jpeg
    }

    /// Decodes with the EXIF orientation applied, optionally downscaled.
    private static func decode(_ source: CGImageSource, url: URL, maxPixel: Double?) throws -> CGImage {
        let size = imageSize(source)
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let fitted = maxPixel.map { TransformMath.fit(size, longestSide: $0) } ?? size
        options[kCGImageSourceThumbnailMaxPixelSize] = max(fitted.width, fitted.height)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TransformError.unreadable(url.lastPathComponent)
        }
        return image
    }

    private static func imageSize(_ source: CGImageSource) -> CGSize {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Double,
            let height = properties[kCGImagePropertyPixelHeight] as? Double
        else { return CGSize(width: 4096, height: 4096) }
        return CGSize(width: width, height: height)
    }

    private static func write(_ image: CGImage, like source: URL, format: ImageFormat, quality: Double, suffix: String?)
        throws -> URL
    {
        let folder = source.deletingLastPathComponent()
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let output = TransformNaming.output(for: source, suffix: suffix, ext: format.ext, existing: existing)
        guard
            let destination = CGImageDestinationCreateWithURL(
                output as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw TransformError.writeFailed(output.lastPathComponent) }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TransformError.writeFailed(output.lastPathComponent)
        }
        return output
    }

    private static func rotate(_ image: CGImage, degrees: Int) throws -> CGImage {
        let quarterTurns = ((degrees / 90) % 4 + 4) % 4
        let swap = quarterTurns % 2 == 1
        let width = swap ? image.height : image.width
        let height = swap ? image.width : image.height
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw TransformError.writeFailed("rotation") }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width),
                height: CGFloat(image.height)))
        guard let rotated = context.makeImage() else { throw TransformError.writeFailed("rotation") }
        return rotated
    }

    /// Lifts the foreground subject with Vision and keeps transparency.
    private static func removeBackground(_ image: CGImage, name: String) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first else { throw TransformError.unreadable(name) }
        let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            throw TransformError.writeFailed(name)
        }
        return output
    }

    /// One PDF from images and PDFs, in the given order, next to the first file.
    private static func combinePDF(_ urls: [URL]) throws -> URL {
        let document = PDFDocument()
        for url in urls {
            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                for index in 0..<pdf.pageCount {
                    if let page = pdf.page(at: index) { document.insert(page, at: document.pageCount) }
                }
            } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = try? decode(source, url: url, maxPixel: nil),
                let page = PDFPage(image: NSImage(cgImage: image, size: .zero))
            {
                document.insert(page, at: document.pageCount)
            }
        }
        guard document.pageCount > 0, let first = urls.first else { throw TransformError.writeFailed("PDF") }
        let folder = first.deletingLastPathComponent()
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Combined"
        let output = TransformNaming.output(
            for: folder.appendingPathComponent("\(name).src"), suffix: nil, ext: "pdf", existing: existing)
        guard document.write(to: output) else { throw TransformError.writeFailed(output.lastPathComponent) }
        return output
    }
}

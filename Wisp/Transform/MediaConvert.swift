import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WispCore

/// Converts files dropped on a format around the ring's Transform segment: images through the
/// Transform engine, video and audio with AVFoundation, all on this Mac. Outputs land next to
/// the originals and never overwrite them.
enum MediaConvert {
    enum Failure: LocalizedError {
        case unsupported(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name): "\(name) can't be converted to that"
            case .failed(let name): "Couldn't convert \(name)"
            }
        }
    }

    /// Whether every video has a sound track; nil when that isn't known within `limit`.
    static func haveSound(_ videos: [URL], within limit: Duration) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                for video in videos {
                    let tracks = (try? await AVURLAsset(url: video).loadTracks(withMediaType: .audio)) ?? []
                    if tracks.isEmpty { return false }
                }
                return true
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func run(_ format: ConvertFormat, urls: [URL]) async -> TransformEngine.Outcome {
        var result = TransformEngine.Outcome(outputs: [])
        for url in urls {
            do {
                result.outputs.append(try await convert(url, to: format))
            } catch {
                result.problem = result.problem ?? error.localizedDescription
            }
        }
        return result
    }

    private static func convert(_ url: URL, to format: ConvertFormat) async throws -> URL {
        let name = url.lastPathComponent
        switch (ConvertTargets.kind(ofExtension: url.pathExtension), format) {
        case (.image, _):
            guard let image = imageFormat(for: format) else { throw Failure.unsupported(name) }
            var options = TransformOptions()
            options.format = image
            options.quality = 0.9
            let outcome = try await TransformEngine.run(.convert, urls: [url], options: options)
            guard let output = outcome.outputs.first else { throw Failure.failed(name) }
            return output
        case (.video, .gif):
            return try await Task.detached(priority: .userInitiated) { try await gif(from: url) }.value
        case (.video, .mp4), (.video, .mov), (.video, .m4a), (.audio, .m4a):
            return try await Task.detached(priority: .userInitiated) { try await export(url, to: format) }.value
        case (.audio, .wav), (.audio, .aiff):
            return try await Task.detached(priority: .userInitiated) { try pcm(url, to: format) }.value
        default:
            throw Failure.unsupported(name)
        }
    }

    private static func imageFormat(for format: ConvertFormat) -> ImageFormat? {
        switch format {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        default: nil
        }
    }

    private static func output(for url: URL, ext: String) -> URL {
        let folder = url.deletingLastPathComponent()
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        return TransformNaming.output(for: url, suffix: nil, ext: ext, existing: existing)
    }

    /// Re-encoded with the system's export presets: the best quality for video, AAC for audio.
    private static func export(_ url: URL, to format: ConvertFormat) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let preset = format == .m4a ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        let type: AVFileType =
            switch format {
            case .mp4: .mp4
            case .m4a: .m4a
            default: .mov
            }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw Failure.unsupported(url.lastPathComponent)
        }
        let target = output(for: url, ext: format.ext)
        session.outputURL = target
        session.outputFileType = type
        await session.export()
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: target)
            throw Failure.failed(url.lastPathComponent)
        }
        return target
    }

    /// Uncompressed 16-bit audio, written a block at a time so a long file isn't held in memory.
    private static func pcm(_ url: URL, to format: ConvertFormat) throws -> URL {
        let input = try AVAudioFile(forReading: url)
        let source = input.processingFormat
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: source.sampleRate,
            AVNumberOfChannelsKey: source.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: format == .aiff,
        ]
        let target = output(for: url, ext: format.ext)
        do {
            let writer = try AVAudioFile(
                forWriting: target, settings: settings, commonFormat: source.commonFormat,
                interleaved: source.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 32_768) else {
                throw Failure.failed(url.lastPathComponent)
            }
            while input.framePosition < input.length {
                try input.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                try writer.write(from: buffer)
            }
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return target
    }

    /// A looping GIF of the clip's start (see `GIFPlan`), frames taken upright and scaled down.
    private static func gif(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let times = GIFPlan.frames(duration: duration)
        guard !times.isEmpty else { throw Failure.unsupported(url.lastPathComponent) }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: GIFPlan.longestSide, height: GIFPlan.longestSide)
        let tolerance = CMTime(seconds: GIFPlan.delay() / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let target = output(for: url, ext: ConvertFormat.gif.ext)
        guard
            let destination = CGImageDestinationCreateWithURL(
                target as CFURL, UTType.gif.identifier as CFString, times.count, nil)
        else { throw Failure.failed(url.lastPathComponent) }
        let loop = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, loop as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: GIFPlan.delay()]]
        for time in times {
            let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
            CGImageDestinationAddImage(destination, image, frame as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: target)
            throw Failure.failed(url.lastPathComponent)
        }
        return target
    }
}

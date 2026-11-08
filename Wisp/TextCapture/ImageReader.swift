import CoreGraphics
import Vision
import WispCore

/// On-device Vision reading of one image: text lines, and QR codes or barcodes. Synchronous and
/// slow on large images, so callers run it off the main actor. Nothing is kept or logged.
enum ImageReader {
    /// Text lines read literally, for the region watch: build output and status words read
    /// better without language correction, and its rules expect the language settings it
    /// always had. Empty when Vision fails.
    static func literalLines(in image: CGImage) -> [RecognizedLine] {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: image).perform([text])
        } catch {
            return []
        }
        return lines(from: text)
    }

    /// Text and codes in one pass, for Capture text and clipboard images. Prose reads better
    /// with language correction, and the text may be in any language.
    static func read(_ image: CGImage) -> CaptureResult {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.automaticallyDetectsLanguage = true
        let codes = VNDetectBarcodesRequest()
        do {
            try VNImageRequestHandler(cgImage: image).perform([text, codes])
        } catch {
            return .nothing
        }
        return CaptureResult(lines: lines(from: text), codes: (codes.results ?? []).compactMap(\.payloadStringValue))
    }

    /// The top candidate for each line, with its box.
    private static func lines(from request: VNRecognizeTextRequest) -> [RecognizedLine] {
        (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { RecognizedLine(text: $0.string, box: observation.boundingBox) }
        }
    }
}

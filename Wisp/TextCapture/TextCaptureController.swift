import AppKit
import ImageIO
import PDFKit
import WispCore

/// Copies text out of things that only show it: a part of the screen (the Capture text ring
/// action), an image in the clipboard history, and a PDF in the tray as an AI summary.
/// Reading happens on this Mac. Frames and images are dropped once read, and the text is never
/// logged; it only goes to the clipboard. A PDF's text goes to the AI engine chosen in
/// Settings › AI for its summary.
@MainActor
final class TextCaptureController {
    private let services: AppServices
    private let picker = RegionPicker()
    /// One Vision read at a time (Capture text or Copy text).
    private var reading = false
    /// One summary at a time; the model is slower than Vision, so it doesn't block reading.
    private var summarising = false

    /// Pages read from a PDF. The model takes a few pages' worth, so more would only be cut.
    private static let pdfPageLimit = 30
    private static let pdfSymbol = "doc.text.magnifyingglass"

    /// Marker from nspasteboard.org that asks clipboard managers, Wisp's history included, to
    /// skip an item.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private enum PDFRead: Sendable {
        case text(String)
        case locked
        case unreadable
    }

    init(services: AppServices) {
        self.services = services
    }

    /// The ring action: drag over text or a QR code and its contents land on the clipboard.
    /// Screen Recording is asked for on first use.
    func begin() {
        guard !picker.isPicking else { return }
        guard !reading else { return notice("Still reading the last one") }
        guard CGPreflightScreenCaptureAccess() else {
            notice(Permission.askForScreenRecording())
            return
        }
        services.closeShelves()
        picker.pick(hint: "Drag over text or a QR code to copy it. Esc cancels.") { [weak self] rect in
            guard let self, let rect else { return }
            self.capture(rect)
        }
    }

    private func capture(_ selection: CGRect) {
        guard !reading else { return notice("Still reading the last one") }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = RegionGeometry.flipped(selection, primaryHeight: primaryHeight)
        reading = true
        Task {
            defer { reading = false }
            do {
                let result = try await Task.detached {
                    ImageReader.read(try await ScreenSnapshot.capture(flipped))
                }.value
                deliver(result)
            } catch ScreenSnapshotError.offScreen {
                notice("Drag over part of a screen")
            } catch {
                notice("Couldn't capture the screen")
            }
        }
    }

    /// The clipboard menu's Copy text on an image.
    func copyText(from item: ClipItem) {
        guard item.kind == .image, let url = services.clipboard.imageURL(for: item) else { return }
        guard !reading else { return notice("Still reading the last one") }
        reading = true
        Task {
            defer { reading = false }
            let result = await Task.detached { () -> CaptureResult? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { return nil }
                return ImageReader.read(image)
            }.value
            if let result { deliver(result) } else { notice("Couldn't open the image") }
        }
    }

    /// Whether the tray offers Summarise on PDFs: only while AI is turned on.
    var canSummarise: Bool { services.preferences.aiEnabled }

    /// Summarises a PDF's text with the AI and copies the summary; a notice confirms it, since
    /// a notice holds one line. Once the AI result card exists it can show the summary there.
    func summarise(_ url: URL) {
        guard canSummarise else { return }
        guard !summarising else { return notice("Still summarising the last one", symbol: Self.pdfSymbol) }
        summarising = true
        let name = url.lastPathComponent
        // Stays up until the run ends; every outcome below replaces it in the same slot.
        services.activities.post(
            .notice(symbol: Self.pdfSymbol, text: PDFText.progress(fileName: name)), slot: .notice, duration: nil)
        Task {
            defer { summarising = false }
            let pages = Self.pdfPageLimit
            let read = await Task.detached { Self.pdfText(url, pageLimit: pages) }.value
            switch read {
            case .unreadable:
                notice("Couldn't open the PDF", symbol: Self.pdfSymbol)
            case .locked:
                notice("This PDF is locked", symbol: Self.pdfSymbol)
            case .text(let text) where text.isEmpty:
                notice("This PDF has no text to read", symbol: Self.pdfSymbol)
            case .text(let text):
                do throws(AIError) {
                    let answer = try await services.ai.run(.summarise, on: text)
                    copy(answer.text)
                    let text = answer.truncated ? PDFText.partialNotice(fileName: name) : PDFText.notice(fileName: name)
                    notice(text, symbol: Self.pdfSymbol, duration: 4)
                } catch {
                    notice(error.message, symbol: Self.pdfSymbol)
                }
            }
        }
    }

    /// The text of the pages worth reading, tidied; empty for a scan with no text layer.
    private nonisolated static func pdfText(_ url: URL, pageLimit: Int) -> PDFRead {
        guard let document = PDFDocument(url: url) else { return .unreadable }
        guard !document.isLocked else { return .locked }
        let pages = PDFText.pageIndices(count: document.pageCount, limit: pageLimit).compactMap {
            document.page(at: $0)?.string
        }
        return .text(PDFText.clean(pages: pages))
    }

    private func deliver(_ result: CaptureResult) {
        if let text = result.copyText {
            if result.isSecret { copySecret(text) } else { copy(text) }
        }
        notice(result.notice)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// A Wi-Fi password: kept off other Macs through Universal Clipboard and marked concealed,
    /// so clipboard history never stores it on disk.
    private func copySecret(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: Self.concealedType)
        pasteboard.writeObjects([item])
    }

    private func notice(_ text: String, symbol: String = "text.viewfinder", duration: TimeInterval = 3) {
        services.activities.post(.notice(symbol: symbol, text: text), slot: .notice, duration: duration)
    }
}

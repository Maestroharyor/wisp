import AppKit
import Observation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers
import WispCore

/// State for the Transform window.
@MainActor
@Observable
final class TransformModel {
    var files: [URL] = []
    var operation: TransformOperation = .convert
    var options = TransformOptions()
    var running = false
    var message: String?
    var outputs: [URL] = []
    /// The format videos and audio convert to; images use `options.format`.
    var mediaFormat: ConvertFormat = .mp4

    /// What Convert can do with the files: image formats, the video and audio formats every file
    /// can take, or nothing (text, mixed kinds that share no format).
    var conversion: Conversion {
        guard !files.isEmpty else { return .nothing }
        let exts = files.map(\.pathExtension)
        if exts.allSatisfy({ ConvertTargets.kind(ofExtension: $0) == .image }) { return .images }
        let formats = ConvertTargets.formats(forExtensions: exts)
        return formats.isEmpty ? .nothing : .media(formats)
    }

    enum Conversion: Equatable {
        case images
        case media([ConvertFormat])
        case nothing
    }

    var totalBytes: Int64 { files.reduce(0) { $0 + Self.size(of: $1) } }

    static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

/// Floating window for converting, compressing, resizing and otherwise reshaping
/// files (design §9). Results land next to the originals and in the tray.
@MainActor
final class TransformPanelController {
    private let services: AppServices
    private let model = TransformModel()
    private var window: NSPanel?

    init(services: AppServices) {
        self.services = services
    }

    func open(_ urls: [URL]) {
        if !urls.isEmpty {
            model.files = urls
            model.outputs = []
            model.message = nil
        }
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                window.setFrameTopLeftPoint(CGPoint(x: visible.maxX - TransformView.width - 40, y: visible.maxY - 40))
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: TransformView.width, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(
            rootView: TransformView(model: model, run: { [weak self] in self?.run() }))
        return panel
    }

    private func run() {
        let files = model.files
        guard !files.isEmpty, !model.running else { return }
        if model.operation == .zip {
            services.tray.zip(files)
            model.message = "Zipping… the archive appears in the tray."
            return
        }
        model.running = true
        model.message = nil
        let operation = model.operation
        let options = model.options
        if operation == .convert, case .media(let formats) = model.conversion {
            let format = formats.contains(model.mediaFormat) ? model.mediaFormat : formats[0]
            Task {
                let result = await MediaConvert.run(format, urls: files)
                finish(result, files: files, operation: operation)
            }
            return
        }
        Task {
            do {
                let result = try await TransformEngine.run(operation, urls: files, options: options)
                finish(result, files: files, operation: operation)
            } catch {
                model.message = error.localizedDescription
                model.running = false
            }
        }
    }

    private func finish(_ result: TransformEngine.Outcome, files: [URL], operation: TransformOperation) {
        let outputs = result.outputs
        model.outputs = outputs
        services.tray.add(outputs)
        let before = files.reduce(0) { $0 + TransformModel.size(of: $1) }
        let after = outputs.reduce(0) { $0 + TransformModel.size(of: $1) }
        model.message =
            [.compress, .resize].contains(operation)
            ? TransformMath.savingsText(before: before, after: after)
            : "Done: \(outputs.count) file\(outputs.count == 1 ? "" : "s") added to the tray"
        if let problem = result.problem {
            model.message = outputs.isEmpty ? problem : "\(problem). \(outputs.count) done, added to the tray."
        }
        model.running = false
    }
}

/// The Transform window: the files, what to do with them, its options, and one button that says
/// what it will do.
private struct TransformView: View {
    @Bindable var model: TransformModel
    let run: () -> Void

    static let width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if model.files.isEmpty {
                emptyDrop
            } else {
                section("Files") { filesRow }
                section("Action") { operations }
                section("Options") { optionsArea }
            }
            Spacer(minLength: 0)
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.outputs.isEmpty {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
                    .controlSize(.small)
            }
            Button(action: run) {
                Text(buttonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canRun)
        }
        .padding(20)
        .padding(.top, 14)
        .frame(width: Self.width, height: 560)
        .tint(.wispViolet)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: FileDrop.handler { model.files += $0 })
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous).fill(Color.wispViolet))
            VStack(alignment: .leading, spacing: 1) {
                Text("Transform").font(.title3.weight(.bold))
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }

    private var summary: String {
        guard let first = model.files.first else { return "Convert, compress, resize and more" }
        let size = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        return model.files.count == 1
            ? "\(first.lastPathComponent) · \(size)" : "\(model.files.count) files · \(size)"
    }

    private var emptyDrop: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc").font(.system(size: 30, weight: .regular)).foregroundStyle(.secondary)
            Text("Drop files here").font(.headline)
            Button("Choose files…", action: addFiles)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(
            RoundedRectangle(cornerRadius: SurfaceRadius.card, style: .continuous).strokeBorder(
                Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    private var filesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(model.files, id: \.self) { url in
                    VStack(spacing: 4) {
                        FileIcon(path: url.path)
                            .frame(width: 48, height: 48)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    model.files.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.callout)
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, Color.secondary)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 6, y: -6)
                                .accessibilityLabel("Remove \(url.lastPathComponent)")
                            }
                        Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                            .frame(width: 64)
                    }
                    .help(url.lastPathComponent)
                }
                Button(action: addFiles) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous).strokeBorder(
                                Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add files")
            }
            .padding(.top, 6)
        }
    }

    private var operations: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(TransformOperation.allCases) { operation in
                Button {
                    model.operation = operation
                } label: {
                    let chosen = model.operation == operation
                    VStack(spacing: 6) {
                        Image(systemName: operation.symbol).font(.title3)
                        Text(operation.title).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(chosen ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous)
                            .fill(chosen ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.quaternary))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: SurfaceRadius.row, style: .continuous))
                    .wispHover(cornerRadius: SurfaceRadius.row)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.operation == operation ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var optionsArea: some View {
        switch model.operation {
        case .convert:
            switch model.conversion {
            case .images:
                formatChips(ImageFormat.allCases.map { ($0.title, $0 == model.options.format) }) { index in
                    model.options.format = ImageFormat.allCases[index]
                }
                qualitySlider
            case .media(let formats):
                formatChips(formats.map { ($0.title, $0 == chosenMedia(formats)) }) { index in
                    model.mediaFormat = formats[index]
                }
            case .nothing:
                note("These files can't be converted. Convert takes images, video and audio; try Zip instead.")
            }
        case .compress:
            qualitySlider
            Toggle("Shrink to 2048 px on the longest side", isOn: shrinksForWeb)
            Button("Web ready preset") {
                model.options.quality = 0.75
                model.options.compressLongestSide = 2048
            }
            .controlSize(.small)
        case .resize:
            LabeledContent("Longest side") {
                Picker("", selection: $model.options.longestSide) {
                    ForEach([800.0, 1280, 2048, 3000, 4096], id: \.self) { Text("\(Int($0)) px").tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
            }
        case .rotate:
            Picker("Rotation", selection: $model.options.rotation) {
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .removeBackground:
            note("Lifts the main subject and saves a PNG with a transparent background.")
        case .removeMetadata:
            note("Saves a copy without location, camera and other hidden info.")
        case .combinePDF:
            note("Combines images and PDFs, in this order, into one PDF.")
        case .zip:
            note("Packs the files into one zip archive next to them.")
        }
    }

    /// The format to convert video and audio to: the one picked, if these files can take it.
    private func chosenMedia(_ formats: [ConvertFormat]) -> ConvertFormat {
        formats.contains(model.mediaFormat) ? model.mediaFormat : formats[0]
    }

    /// Formats as a row of chips that wraps, instead of a segmented control that squeezes.
    private func formatChips(_ chips: [(title: String, chosen: Bool)], pick: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                Button {
                    pick(index)
                } label: {
                    Text(chip.title).font(.callout.weight(.semibold))
                        .foregroundStyle(chip.chosen ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(
                            Capsule().fill(chip.chosen ? AnyShapeStyle(Color.wispViolet) : AnyShapeStyle(.quaternary))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Convert to \(chip.title)")
                .accessibilityAddTraits(chip.chosen ? .isSelected : [])
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var canRun: Bool {
        guard !model.files.isEmpty, !model.running else { return false }
        return model.operation != .convert || model.conversion != .nothing
    }

    private var buttonTitle: String {
        if model.running { return "Working…" }
        guard model.operation == .convert else { return model.operation.title }
        switch model.conversion {
        case .images: return "Convert to \(model.options.format.title)"
        case .media(let formats): return "Convert to \(chosenMedia(formats).title)"
        case .nothing: return "Convert"
        }
    }

    private var shrinksForWeb: Binding<Bool> {
        Binding(
            get: { model.options.compressLongestSide != nil },
            set: { model.options.compressLongestSide = $0 ? 2048 : nil })
    }

    private var qualitySlider: some View {
        LabeledContent("Quality") {
            HStack {
                Slider(value: $model.options.quality, in: 0.3...1)
                Text("\(Int(model.options.quality * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { model.files += panel.urls }
    }
}

/// A file's Finder icon, looked up off the main thread and cached (`RingIconCache`).
private struct FileIcon: View {
    let path: String

    var body: some View {
        if let image = RingIconCache.shared.image(for: .file(path: path)) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "doc").font(.system(size: 26)).foregroundStyle(.secondary)
        }
    }
}

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
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                window.setFrameTopLeftPoint(CGPoint(x: visible.maxX - 360, y: visible.maxY - 40))
            }
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.appearance = NSAppearance(named: .darkAqua)
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
        Task {
            do {
                let outputs = try await TransformEngine.run(operation, urls: files, options: options)
                model.outputs = outputs
                services.tray.add(outputs)
                let before = files.reduce(0) { $0 + TransformModel.size(of: $1) }
                let after = outputs.reduce(0) { $0 + TransformModel.size(of: $1) }
                model.message =
                    [.compress, .resize, .convert].contains(operation)
                    ? TransformMath.savingsText(before: before, after: after)
                    : "Done: \(outputs.count) file\(outputs.count == 1 ? "" : "s") added to the tray"
            } catch {
                model.message = error.localizedDescription
            }
            model.running = false
        }
    }
}

private struct TransformView: View {
    @Bindable var model: TransformModel
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            filesRow
            operations
            optionsArea
            Spacer(minLength: 0)
            if let message = model.message {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !model.outputs.isEmpty {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.outputs) }
                    .controlSize(.small)
            }
            Button(action: run) {
                Text(model.running ? "Working…" : model.operation.title)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.indigo))
            }
            .buttonStyle(.plain)
            .disabled(model.files.isEmpty || model.running)
            .opacity(model.files.isEmpty ? 0.5 : 1)
        }
        .padding(18)
        .padding(.top, 14)
        .frame(width: 320, height: 600)
        .background(.black.opacity(0.92))
        .foregroundStyle(.white)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: FileDrop.handler { model.files += $0 })
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars").font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text("Transform").font(.system(size: 15, weight: .bold))
                Text(summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var summary: String {
        guard let first = model.files.first else { return "Drop files here" }
        let size = ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        return model.files.count == 1
            ? "\(first.lastPathComponent) · \(size)" : "\(model.files.count) files · \(size)"
    }

    private var filesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.files, id: \.self) { url in
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable().frame(width: 44, height: 44)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                model.files.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .help(url.lastPathComponent)
                }
                Button(action: addFiles) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10).strokeBorder(
                                .white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var operations: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(TransformOperation.allCases) { operation in
                Button {
                    model.operation = operation
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: operation.symbol).font(.system(size: 15))
                        Text(operation.title).font(.system(size: 9, weight: .medium)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(model.operation == operation ? Color.indigo : .white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var optionsArea: some View {
        switch model.operation {
        case .convert:
            Picker("Format", selection: $model.options.format) {
                ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            qualitySlider
        case .compress:
            qualitySlider
            Button("Web ready preset") {
                model.options.quality = 0.75
                model.options.longestSide = 2048
            }
            .controlSize(.small)
        case .resize:
            LabeledContent("Longest side") {
                Picker("", selection: $model.options.longestSide) {
                    ForEach([800.0, 1280, 2048, 3000, 4096], id: \.self) { Text("\(Int($0)) px").tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
            }
        case .rotate:
            Picker("Rotation", selection: $model.options.rotation) {
                Text("90°").tag(90)
                Text("180°").tag(180)
                Text("270°").tag(270)
            }
            .pickerStyle(.segmented)
        case .removeBackground:
            Text("Lifts the main subject and saves a PNG with a transparent background.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        case .removeMetadata:
            Text("Saves a copy without location, camera and other hidden info.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        case .combinePDF:
            Text("Combines images and PDFs, in this order, into one PDF.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        case .zip:
            Text("Packs the files into one zip archive next to them.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var qualitySlider: some View {
        LabeledContent("Quality") {
            HStack {
                Slider(value: $model.options.quality, in: 0.3...1)
                Text("\(Int(model.options.quality * 100))%").monospacedDigit().frame(width: 38)
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

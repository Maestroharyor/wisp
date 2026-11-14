import AppKit
import OSLog
import Observation
import WispCore

/// Watches the general pasteboard and keeps a history. Skips content that password
/// managers mark as concealed or transient. Images are stored as PNG files next to
/// the history file in Application Support.
@MainActor
@Observable
final class ClipboardStore {
    private(set) var history: ClipboardHistory

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let pasteboard = NSPasteboard.general
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// The last copy still being stored (an image encodes off the main thread); later copies
    /// wait for it so history keeps the order things were copied in.
    @ObservationIgnored private var storing: Task<Void, Never>?
    /// Counts stores, so only the latest one clears `storing` when it finishes.
    @ObservationIgnored private var storeCount = 0
    /// History saves run one at a time off the main thread; changes made meanwhile share the next.
    @ObservationIgnored private var saves = SaveCoalescer()
    /// Saves run here in order, so an older snapshot never lands after a newer one.
    @ObservationIgnored private let saveQueue = DispatchQueue(label: "com.ayomideodewale.wisp.clipboard", qos: .utility)
    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "clipboard")

    init(preferences: Preferences) {
        self.preferences = preferences
        lastChangeCount = NSPasteboard.general.changeCount
        history = ClipboardHistory(limit: preferences.clipboardLimit)
        load()
    }

    nonisolated static var folder: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(AppSupport.folderName(bundleID: Bundle.main.bundleIdentifier))
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        saveNow()
    }

    func imageURL(for item: ClipItem) -> URL? {
        item.imageFile.map { Self.folder.appendingPathComponent($0) }
    }

    /// Puts an item back on the pasteboard without recording it again.
    func copy(_ item: ClipItem) {
        pasteboard.clearContents()
        if item.kind == .image, let url = imageURL(for: item), let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
        } else if let text = item.text {
            pasteboard.setString(text, forType: .string)
        }
        lastChangeCount = pasteboard.changeCount
        var refreshed = item
        refreshed.date = .now
        history.add(refreshed)
        save()
    }

    func remove(_ item: ClipItem) {
        if let removed = history.remove(id: item.id) { deleteFiles(of: [removed]) }
        save()
    }

    func togglePin(_ item: ClipItem) {
        history.togglePin(id: item.id)
        save()
    }

    func clear() {
        deleteFiles(of: history.clearUnpinned())
        save()
    }

    private func check() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Tracked even while off, so turning history on never records what was copied before.
        guard preferences.clipboardEnabled else { return }

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: ClipClassifier.privateTypes) else { return }
        let app = NSWorkspace.shared.frontmostApplication

        let source = (name: app?.localizedName, bundleID: app?.bundleIdentifier)
        let copied = Date.now
        let previous = storing
        if let text = pasteboard.string(forType: .string) {
            guard ClipClassifier.keeps(text: text) else { return }
            let item = ClipItem(kind: ClipClassifier.kind(for: text), text: text, date: copied)
            guard let previous else { return record(item, source: source) }
            let number = nextStore()
            storing = Task { [weak self] in
                await previous.value
                self?.record(item, source: source)
                self?.finishStore(number)
            }
        } else if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            // A screenshot on a big display is tens of megabytes; encoding it on the main
            // thread would stall the key taps that run there.
            let number = nextStore()
            storing = Task { [weak self] in
                let stored = await Task.detached { Result { try Self.storeImage(data) } }.value
                await previous?.value
                guard let self else { return }
                defer { self.finishStore(number) }
                switch stored {
                case .success(var item):
                    item.date = copied
                    self.record(item, source: source)
                case .failure(let error):
                    self.log.error("could not store clipboard image: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func nextStore() -> Int {
        storeCount += 1
        return storeCount
    }

    /// Once the latest store is done, text copies go straight in again.
    private func finishStore(_ number: Int) {
        if number == storeCount { storing = nil }
    }

    private func record(_ item: ClipItem, source: (name: String?, bundleID: String?)) {
        // History may have been switched off while an image was being stored.
        guard preferences.clipboardEnabled else { return deleteFiles(of: [item]) }
        var item = item
        item.sourceApp = source.name
        item.sourceBundleID = source.bundleID
        history.limit = preferences.clipboardLimit
        deleteFiles(of: history.add(item))
        save()
    }

    private struct UnreadableImage: Error {}

    /// Writes the image as a PNG file, reusing the pasteboard's PNG bytes when it has them.
    private nonisolated static func storeImage(_ data: Data) throws -> ClipItem {
        guard let bitmap = NSBitmapImageRep(data: data) else { throw UnreadableImage() }
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
        guard let png = isPNG ? data : bitmap.representation(using: .png, properties: [:]) else {
            throw UnreadableImage()
        }
        let name = "\(UUID().uuidString).png"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent(name))
        return ClipItem(
            kind: .image, imageFile: name,
            imagePixelSize: CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh), date: .now)
    }

    private func deleteFiles(of items: [ClipItem]) {
        for item in items {
            if let url = imageURL(for: item) { try? FileManager.default.removeItem(at: url) }
        }
    }

    private var historyURL: URL { Self.folder.appendingPathComponent("history.json") }

    private func load() {
        guard let data = try? Data(contentsOf: historyURL) else { return }
        guard let saved = try? JSONDecoder().decode(ClipboardHistory.self, from: data) else {
            // The next copy would save over it, pinned items and all. Keep it aside instead, so
            // a downgrade or a damaged file doesn't lose the history for good.
            let aside = Self.folder.appendingPathComponent("history.unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: historyURL, to: aside)
            log.error("clipboard history could not be read; set it aside")
            return
        }
        history = saved
        history.limit = preferences.clipboardLimit
    }

    private func save() {
        guard saves.changed() else { return }
        startSave()
    }

    /// Encodes and writes a snapshot of the history on the save queue, then starts one more
    /// save if the history changed while it ran.
    private func startSave() {
        guard saves.begin() else { return }
        let snapshot = history
        let url = historyURL
        let queue = saveQueue
        let log = log
        Task { [weak self] in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.async {
                    Self.write(snapshot, to: url, log: log)
                    continuation.resume()
                }
            }
            guard let self, self.saves.finish() else { return }
            self.startSave()
        }
    }

    /// On quit: waits for a save that's running and writes what came after it, so the last
    /// change isn't lost with the process.
    private func saveNow() {
        let pending = saves.dirty ? history : nil
        saves = SaveCoalescer()
        let url = historyURL
        saveQueue.sync {
            if let pending { Self.write(pending, to: url, log: log) }
        }
    }

    private nonisolated static func write(_ history: ClipboardHistory, to url: URL, log: Logger) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: url, options: .atomic)
        } catch {
            log.error("could not save clipboard history: \(error.localizedDescription, privacy: .public)")
        }
    }
}

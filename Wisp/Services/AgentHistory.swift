import Foundation
import OSLog
import Observation
import WispCore

/// Finished agent sessions, kept in Application Support so the history survives relaunches, and
/// their on-device summaries. Records hold figures, tool counts, masked commands and file names,
/// never prompts, messages, file contents or command output (see `SessionRecord`). The file is
/// read and written off the main actor; writes are gathered for a second.
@MainActor
@Observable
final class AgentHistoryStore {
    private(set) var history = SessionHistory()

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let ai: AIService
    @ObservationIgnored private let file: AgentHistoryFile
    /// Records removed from the history while their run may still be live, so a later turn of the
    /// same run doesn't bring them back.
    @ObservationIgnored private var removed: Set<String> = []
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var clearedBeforeLoad = false
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    private static let writeDelay: Duration = .seconds(1)

    init(preferences: Preferences, ai: AIService, folder: URL = AgentHistoryStore.folder) {
        self.preferences = preferences
        self.ai = ai
        file = AgentHistoryFile(folder: folder)
        Task { [weak self, file] in
            let saved = await file.load(now: .now)
            self?.finishLoading(saved)
        }
    }

    nonisolated static var folder: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(AppSupport.folderName(bundleID: Bundle.main.bundleIdentifier))
            .appendingPathComponent("Agents", isDirectory: true)
    }

    /// Whether finished sessions get an AI summary: the setting is on and the engine is ready.
    var summariesAvailable: Bool { preferences.agentSummaries && ai.isReady }

    /// Saves a record when history is on and something happened in it.
    func save(_ record: SessionRecord) {
        guard preferences.agentHistory, !record.isEmpty, !removed.contains(record.id) else { return }
        history.save(record, now: .now)
        scheduleWrite()
    }

    /// Summarises `record` on this Mac and stores the summary with it. Nil when summaries are
    /// off or the engine isn't ready. `hidden` leaves files and commands out of what the model
    /// sees, so the summary can't name them.
    func summarise(_ record: SessionRecord, hidden: Bool) async -> String? {
        guard summariesAvailable, !record.isEmpty else { return nil }
        guard let answer = try? await ai.run(.sessionSummary, on: record.summaryInput(hidden: hidden)).text,
            !answer.isEmpty
        else { return nil }
        if preferences.agentHistory, history.records.contains(where: { $0.id == record.id }) {
            history.setSummary(answer, for: record.id)
            scheduleWrite()
        }
        return answer
    }

    func remove(_ id: String) {
        removed.insert(id)
        history.remove(id)
        scheduleWrite()
    }

    func clear() {
        if !loaded { clearedBeforeLoad = true }
        history.clear()
        scheduleWrite()
    }

    /// Writes a change still waiting for its delay, so quitting doesn't lose the last turn.
    func flush() {
        guard loaded, let task = writeTask else { return }
        task.cancel()
        writeTask = nil
        file.writeNow(history.records.isEmpty ? nil : try? JSONEncoder().encode(history))
    }

    /// Records saved before the file was read are kept on top of it.
    private func finishLoading(_ saved: SessionHistory) {
        var merged = clearedBeforeLoad ? SessionHistory() : saved
        for record in history.records where !removed.contains(record.id) { merged.save(record, now: .now) }
        for id in removed { merged.remove(id) }
        history = merged
        loaded = true
        if writeTask != nil {
            writeTask?.cancel()
            writeTask = nil
            scheduleWrite()
        }
    }

    private func scheduleWrite() {
        guard writeTask == nil else { return }
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard let self, !Task.isCancelled, self.loaded else { return }
            self.writeTask = nil
            // Encoded here, so the snapshot is the history as it is now; written off the main actor.
            let data = self.history.records.isEmpty ? nil : try? JSONEncoder().encode(self.history)
            await self.file.write(data)
        }
    }
}

/// The history file, read and written in order away from the main actor.
actor AgentHistoryFile {
    nonisolated let folder: URL
    nonisolated let url: URL
    nonisolated let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "agent-history")

    /// Writes a pending change straight away, on the caller's thread; for quitting.
    nonisolated func writeNow(_ data: Data?) {
        Self.store(data, folder: folder, url: url, log: log)
    }

    init(folder: URL) {
        self.folder = folder
        url = folder.appendingPathComponent("history.json")
    }

    /// The saved history, or an empty one. A file that can't be read at all is moved to
    /// `history.json.bak`, so the next write doesn't replace it.
    func load(now: Date) -> SessionHistory {
        guard let data = try? Data(contentsOf: url) else { return SessionHistory() }
        do {
            return try SessionHistory.decode(data, now: now)
        } catch {
            log.error(
                "agent history unreadable, kept as history.json.bak: \(error.localizedDescription, privacy: .public)")
            let backup = folder.appendingPathComponent("history.json.bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return SessionHistory()
        }
    }

    func write(_ data: Data?) {
        Self.store(data, folder: folder, url: url, log: log)
    }

    /// Writes `data`, readable by this user only, or removes the file when there's nothing to keep.
    nonisolated static func store(_ data: Data?, folder: URL, url: URL, log: Logger) {
        let manager = FileManager.default
        do {
            guard let data else {
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
                return
            }
            try manager.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            log.error("could not save agent history: \(error.localizedDescription, privacy: .public)")
        }
    }
}

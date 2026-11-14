import Foundation
import OSLog
import Observation
import WispCore
import os

/// Finished agent sessions, kept in Application Support so the history survives relaunches, and
/// their on-device summaries. Records hold figures, tool counts, masked commands and file names,
/// never prompts, messages, file contents or command output (see `SessionRecord`). The file is
/// read and written off the main actor; writes are gathered for a second. Approvals and how they
/// ended are kept beside it, in their own file (see `ApprovalRecord`).
@MainActor
@Observable
final class AgentHistoryStore {
    private(set) var history = SessionHistory()
    /// The last week of permission requests and how each ended.
    private(set) var approvals = ApprovalLog()

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let ai: AIService
    @ObservationIgnored private let file: AgentHistoryFile
    /// Records removed from the history while their run may still be live, so a later turn of the
    /// same run doesn't bring them back.
    @ObservationIgnored private var removed: Set<String> = []
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var clearedBeforeLoad = false
    /// Counts changes, so the file keeps the newest write (see `AgentHistoryFile`).
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    private static let writeDelay: Duration = .seconds(1)
    @ObservationIgnored private let approvalFile: HistoryFile<ApprovalLog>
    @ObservationIgnored private var approvalsLoaded = false
    @ObservationIgnored private var approvalsClearedBeforeLoad = false
    @ObservationIgnored private var approvalGeneration = 0
    @ObservationIgnored private var approvalWriteTask: Task<Void, Never>?

    init(preferences: Preferences, ai: AIService, folder: URL = AgentHistoryStore.folder) {
        self.preferences = preferences
        self.ai = ai
        file = AgentHistoryFile(folder: folder, name: "history.json")
        approvalFile = HistoryFile(folder: folder, name: "approvals.json")
        Task { [weak self, file] in
            let saved = await file.load(now: .now)
            self?.finishLoading(saved)
        }
        Task { [weak self, approvalFile] in
            let saved = await approvalFile.load(now: .now)
            self?.finishLoadingApprovals(saved)
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

    /// How long the activity map's counts are kept, which sets how many weeks it shows.
    var activityRetention: ActivityRetention { preferences.activityRetention }

    /// Saves a record when history is on and something happened in it.
    func save(_ record: SessionRecord) {
        guard preferences.agentHistory, !record.isEmpty, !removed.contains(record.id) else { return }
        history.save(record, now: .now)
        history.pruneActivity(keeping: preferences.activityRetention, now: .now)
        scheduleWrite()
    }

    /// Drops daily counts older than the retention setting now, for a shorter choice.
    func applyRetention() {
        let before = history.activity
        history.pruneActivity(keeping: preferences.activityRetention, now: .now)
        if history.activity != before { scheduleWrite() }
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

    /// A run still going keeps its record id, so cleared ids stay out when its next turn saves.
    func clear() {
        if !loaded { clearedBeforeLoad = true }
        removed.formUnion(history.records.map(\.id))
        history.clear()
        scheduleWrite()
        if !approvalsLoaded { approvalsClearedBeforeLoad = true }
        approvals.clear()
        scheduleApprovalWrite()
    }

    /// Keeps how a request ended, while history is on.
    func record(_ approval: ApprovalRecord) {
        guard preferences.agentHistory else { return }
        approvals.add(approval, now: .now)
        scheduleApprovalWrite()
    }

    /// Writes the latest history now, on this thread, unless a write of it already finished, so
    /// quitting doesn't lose the last turn. A slower write of older data can't land after it.
    /// Before the launch read has finished, the file is read here and the changes merged onto it,
    /// so neither is lost.
    func flush() {
        flushApprovals()
        guard generation > 0 else { return }
        writeTask?.cancel()
        writeTask = nil
        if !loaded {
            history = merged(onto: file.readNow(now: .now))
            loaded = true
        }
        file.writeNow(encoded(), generation: generation)
    }

    private func encoded() -> Data? {
        history.isEmpty ? nil : try? JSONEncoder().encode(history)
    }

    /// The changes made here (saves, removals, a clear) applied on top of the file's history.
    private func merged(onto saved: SessionHistory) -> SessionHistory {
        var merged = clearedBeforeLoad ? SessionHistory() : saved
        for record in history.records where !removed.contains(record.id) { merged.save(record, now: .now) }
        for id in removed { merged.remove(id) }
        return merged
    }

    /// Records saved before the file was read are kept on top of it.
    private func finishLoading(_ saved: SessionHistory) {
        guard !loaded else { return }
        history = merged(onto: saved)
        history.pruneActivity(keeping: preferences.activityRetention, now: .now)
        loaded = true
        if writeTask != nil {
            writeTask?.cancel()
            writeTask = nil
            scheduleWrite()
        }
    }

    private func scheduleWrite() {
        generation += 1
        guard writeTask == nil else { return }
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard let self, !Task.isCancelled, self.loaded else { return }
            self.writeTask = nil
            // Encoded here, so the snapshot is the history as it is now; written off the main actor.
            self.file.write(self.encoded(), generation: self.generation)
        }
    }

    // MARK: Approvals

    private func flushApprovals() {
        guard approvalGeneration > 0 else { return }
        approvalWriteTask?.cancel()
        approvalWriteTask = nil
        if !approvalsLoaded {
            approvals = mergedApprovals(onto: approvalFile.readNow(now: .now))
            approvalsLoaded = true
        }
        approvalFile.writeNow(encodedApprovals(), generation: approvalGeneration)
    }

    private func encodedApprovals() -> Data? {
        approvals.records.isEmpty ? nil : try? JSONEncoder().encode(approvals)
    }

    /// Requests recorded before the file was read go on top of it.
    private func mergedApprovals(onto saved: ApprovalLog) -> ApprovalLog {
        var merged = approvalsClearedBeforeLoad ? ApprovalLog() : saved
        let known = Set(merged.records.map(\.id))
        for record in approvals.records where !known.contains(record.id) { merged.add(record, now: .now) }
        return merged
    }

    private func finishLoadingApprovals(_ saved: ApprovalLog) {
        guard !approvalsLoaded else { return }
        approvals = mergedApprovals(onto: saved)
        approvalsLoaded = true
        if approvalWriteTask != nil {
            approvalWriteTask?.cancel()
            approvalWriteTask = nil
            scheduleApprovalWrite()
        }
    }

    private func scheduleApprovalWrite() {
        approvalGeneration += 1
        guard approvalWriteTask == nil else { return }
        approvalWriteTask = Task { [weak self] in
            try? await Task.sleep(for: Self.writeDelay)
            guard let self, !Task.isCancelled, self.approvalsLoaded else { return }
            self.approvalWriteTask = nil
            self.approvalFile.write(self.encodedApprovals(), generation: self.approvalGeneration)
        }
    }
}

/// A history kept in a file: the session history or the approval log.
protocol StoredHistory: Codable, Sendable {
    static var empty: Self { get }
    /// The saved file, pruned; throws only when the file as a whole can't be read.
    static func decode(_ data: Data, now: Date) throws -> Self
}

extension SessionHistory: StoredHistory {
    static var empty: SessionHistory { SessionHistory() }
}

extension ApprovalLog: StoredHistory {
    static var empty: ApprovalLog { ApprovalLog() }
}

typealias AgentHistoryFile = HistoryFile<SessionHistory>

/// A history file, read and written on a serial queue away from the main actor. Each write
/// carries the history's generation, and one older than the last written is dropped, so a
/// queued write can't replace what `writeNow` saved at quit.
final class HistoryFile<Value: StoredHistory>: Sendable {
    let folder: URL
    let url: URL
    private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "agent-history")
    private let queue = DispatchQueue(label: "com.ayomideodewale.wisp.agent-history")
    /// Held while writing, so writes never interleave and an older one never lands last.
    private let gate = OSAllocatedUnfairLock(initialState: WriteGate())

    init(folder: URL, name: String) {
        self.folder = folder
        url = folder.appendingPathComponent(name)
    }

    func load(now: Date) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.read(now: now)) }
        }
    }

    func write(_ data: Data?, generation: Int) {
        queue.async { self.store(data, generation: generation) }
    }

    /// Writes straight away on the caller's thread; for quitting.
    func writeNow(_ data: Data?, generation: Int) {
        store(data, generation: generation)
    }

    /// Reads on the caller's thread; for quitting before the launch read finished.
    func readNow(now: Date) -> Value {
        read(now: now)
    }

    private func store(_ data: Data?, generation: Int) {
        gate.withLock { gate in
            guard gate.admit(generation) else { return }
            save(data)
        }
    }

    /// The saved history, or an empty one. A file that can't be read at all is moved aside with
    /// `.bak` on the end, so the next write doesn't replace it.
    private func read(now: Date) -> Value {
        guard let data = try? Data(contentsOf: url) else { return Value.empty }
        do {
            return try Value.decode(data, now: now)
        } catch {
            let name = url.lastPathComponent
            log.error(
                "\(name, privacy: .public) unreadable, kept as .bak: \(error.localizedDescription, privacy: .public)")
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return Value.empty
        }
    }

    /// Writes `data`, readable by this user only, or removes the file when there's nothing to keep.
    private func save(_ data: Data?) {
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
            let name = url.lastPathComponent
            log.error("could not save \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

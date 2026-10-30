import Foundation
import OSLog
import WispCore

/// Runs the bundled media bridge library inside /usr/bin/perl and exchanges JSON
/// lines with it. See WispMediaBridge/WispMediaBridge.m for why perl hosts it.
@MainActor
final class MediaBridge {
    var onEvent: (MediaBridgeEvent) -> Void = { _ in }
    /// Called when the bridge cannot run, so the caller can fall back.
    var onUnavailable: () -> Void = {}

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var restarts: [Date] = []
    private let log = Logger(subsystem: "com.maestro.wisp", category: "media")

    /// Installs the library as a Perl XSUB and calls it. The library path is argv[0].
    private static let loader = """
        use DynaLoader;
        my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $s = DynaLoader::dl_find_symbol($h, "wisp_media_bridge_run") or die "missing entry point";
        DynaLoader::dl_install_xsub("main::run", $s);
        main::run();
        """

    static var libraryURL: URL? {
        Bundle.main.url(forResource: "libWispMediaBridge", withExtension: "dylib")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    @discardableResult
    func start() -> Bool {
        guard process == nil else { return true }
        guard let library = Self.libraryURL else {
            log.error("media bridge library missing from bundle")
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.loader, library.path]
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        let stderr = Pipe()
        process.standardError = stderr
        stderr.fileHandleForReading.readabilityHandler = { [log] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            if !text.isEmpty { log.error("media bridge: \(text, privacy: .public)") }
        }

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in self?.terminated(status: status) }
        }

        do {
            try process.run()
        } catch {
            log.error("could not start media bridge: \(error.localizedDescription, privacy: .public)")
            return false
        }
        self.process = process
        input = stdin.fileHandleForWriting
        return true
    }

    func stop() {
        process?.terminationHandler = nil
        try? input?.close()
        process?.terminate()
        process = nil
        input = nil
    }

    func send(_ command: MediaBridgeCommand) {
        guard let input else { return }
        do {
            try input.write(contentsOf: Data(command.line.utf8))
        } catch {
            log.error("media bridge write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            let event = MediaBridgeParser.parse(line)
            if event != .invalid { onEvent(event) }
        }
    }

    /// Restarts after a crash, at most three times a minute; then reports unavailable.
    private func terminated(status: Int32) {
        process = nil
        input = nil
        buffer.removeAll()
        let now = Date.now
        restarts = restarts.filter { now.timeIntervalSince($0) < 60 } + [now]
        log.notice("media bridge exited with status \(status, privacy: .public)")
        if restarts.count <= 3, start() { return }
        onUnavailable()
    }
}

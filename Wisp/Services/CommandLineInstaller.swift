import Foundation
import OSLog
import Observation
import WispCore

/// Installs `wisp` as a link to this app's helper in `~/.local/bin`. Only a link Wisp made
/// is ever replaced or removed; anything else called `wisp` there is left alone.
@MainActor @Observable
final class CommandLineInstaller {
    enum PathCheck: Equatable {
        case checking, onPath, notOnPath, unknown
    }

    private(set) var state: CommandLineTool.State = .notInstalled
    private(set) var path: PathCheck = .checking
    /// Why the last install or uninstall failed, for the pane.
    private(set) var problem: String?

    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "cli")
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var folder: URL { home.appendingPathComponent(CommandLineTool.folder) }
    var link: URL { folder.appendingPathComponent(AgentCLI.linkName) }

    func refresh() {
        state = currentState()
        Task { await checkPath() }
    }

    func install() {
        problem = nil
        guard let helper = AgentHub.helperURL else { return }
        do {
            switch currentState() {
            case .foreign:
                problem = "~/.local/bin/wisp is another program, so Wisp leaves it alone."
                return
            case .installed:
                return
            case .otherApp:
                try FileManager.default.removeItem(at: link)
            case .notInstalled:
                break
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
        } catch {
            problem = "Couldn't install: \(error.localizedDescription)"
            log.error("cli install failed: \(error.localizedDescription, privacy: .public)")
        }
        state = currentState()
    }

    func uninstall() {
        problem = nil
        switch currentState() {
        case .installed, .otherApp:
            do {
                try FileManager.default.removeItem(at: link)
            } catch {
                problem = "Couldn't uninstall: \(error.localizedDescription)"
            }
        case .foreign, .notInstalled:
            break
        }
        state = currentState()
    }

    private func currentState() -> CommandLineTool.State {
        let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        return CommandLineTool.state(
            exists: FileManager.default.fileExists(atPath: link.path), linkTarget: target,
            helper: AgentHub.helperURL?.path ?? "")
    }

    /// Asks the login shell, since Wisp's own PATH isn't the one Terminal uses.
    private func checkPath() async {
        path = .checking
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let output = try? await ProcessRunner.run(
            shell, ["-ilc", CommandLineTool.printPathCommand], timeout: .seconds(3))
        guard let found = output.flatMap(CommandLineTool.path(fromShellOutput:)) else {
            path = .unknown
            return
        }
        path = CommandLineTool.isOnPath(found, home: home.path) ? .onPath : .notOnPath
    }
}

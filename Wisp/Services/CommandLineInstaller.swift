import Foundation
import OSLog
import Observation
import WispCore

/// Installs `wisp` as a link to this app's helper in `~/.local/bin`. Only a link Wisp made
/// is ever replaced or removed; anything else called `wisp` there is left alone.
@MainActor @Observable
final class CommandLineInstaller {
    /// One for the app, so the PATH check isn't repeated each time the pane opens.
    static let shared = CommandLineInstaller()

    enum PathCheck: Equatable {
        case unchecked, checking, onPath, notOnPath, unknown
    }

    private(set) var state: CommandLineTool.State = .notInstalled
    private(set) var path: PathCheck = .unchecked
    /// Why the last install or uninstall failed, for the pane.
    private(set) var problem: String?

    @ObservationIgnored private let log = Logger(subsystem: "com.ayomideodewale.wisp", category: "cli")
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var folder: URL { home.appendingPathComponent(CommandLineTool.folder) }
    var link: URL { folder.appendingPathComponent(AgentCLI.linkName) }

    /// The PATH check runs the login shell, so it only happens once the link is there,
    /// and once per launch.
    func refresh() {
        state = currentState()
        checkPathOnce()
    }

    func install() {
        problem = nil
        guard let helper = AgentHub.helperURL else { return }
        do {
            try CommandLineTool.install(at: link, helper: helper)
        } catch CommandLineTool.Problem.taken {
            problem = "~/.local/bin/wisp is another program, so Wisp leaves it alone."
        } catch {
            problem = "Couldn't install: \(error.localizedDescription)"
            log.error("cli install failed: \(error.localizedDescription, privacy: .public)")
        }
        state = currentState()
        checkPathOnce()
    }

    func uninstall() {
        problem = nil
        guard let helper = AgentHub.helperURL else { return }
        do {
            try CommandLineTool.uninstall(at: link, helper: helper)
        } catch {
            problem = "Couldn't uninstall: \(error.localizedDescription)"
        }
        state = currentState()
    }

    private func currentState() -> CommandLineTool.State {
        guard let helper = AgentHub.helperURL else { return .notInstalled }
        return CommandLineTool.state(at: link, helper: helper)
    }

    private func checkPathOnce() {
        guard state == .installed, path == .unchecked else { return }
        path = .checking
        Task { await checkPath() }
    }

    /// Asks the login shell, since Wisp's own PATH isn't the one Terminal uses.
    private func checkPath() async {
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

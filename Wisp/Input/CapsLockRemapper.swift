import Foundation
import WispCore

/// Remaps Caps Lock to F18 system-wide via `/usr/bin/hidutil`, so it can act as a
/// Hyper modifier. Merges with the user's existing mappings and removes only its own.
/// The mapping is lost on reboot and must be re-applied when a keyboard connects.
///
/// Each change waits for `hidutil` to exit, so changes run on a serial queue of their own, in
/// the order they were asked for, and report back on the main actor.
final class CapsLockRemapper: Sendable {
    enum RemapError: Error, CustomStringConvertible {
        case hidutilFailed(status: Int32, output: String)

        var description: String {
            switch self {
            case .hidutilFailed(let status, let output): "hidutil exited with \(status): \(output)"
            }
        }
    }

    private let hidutil = URL(fileURLWithPath: "/usr/bin/hidutil")
    private let queue = DispatchQueue(label: "com.ayomideodewale.wisp.hidutil", qos: .userInitiated)

    /// Adds the remap; `done` gets the error, if any.
    func enable(then done: @escaping @MainActor @Sendable ((any Error)?) -> Void) {
        perform({ try $0.enableNow() }, then: done)
    }

    /// Removes the remap; `done` gets the error, if any.
    func disable(then done: @escaping @MainActor @Sendable ((any Error)?) -> Void) {
        perform({ try $0.disableNow() }, then: done)
    }

    /// Removes the remap before returning, after any change still queued. For quitting, when
    /// Caps Lock has to work again before the process ends.
    func disableAndWait() throws {
        try queue.sync { try disableNow() }
    }

    private func perform(
        _ change: @escaping @Sendable (CapsLockRemapper) throws -> Void,
        then done: @escaping @MainActor @Sendable ((any Error)?) -> Void
    ) {
        queue.async {
            let error: (any Error)?
            do {
                try change(self)
                error = nil
            } catch let failure {
                error = failure
            }
            Task { @MainActor in done(error) }
        }
    }

    private func enableNow() throws {
        try write(KeyMappingCodec.adding(.capsLockToF18, to: currentMappings()))
    }

    private func disableNow() throws {
        let current = try currentMappings()
        guard current.contains(.capsLockToF18) else { return }
        try write(KeyMappingCodec.removing(.capsLockToF18, from: current))
    }

    private func currentMappings() throws -> [KeyMapping] {
        KeyMappingCodec.parse(try run(["property", "--get", "UserKeyMapping"]))
    }

    private func write(_ mappings: [KeyMapping]) throws {
        _ = try run(["property", "--set", KeyMappingCodec.encode(mappings)])
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = hidutil
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw RemapError.hidutilFailed(status: process.terminationStatus, output: output)
        }
        return output
    }
}

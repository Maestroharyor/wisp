import Foundation
import WispCore

/// Remaps Caps Lock to F18 system-wide via `/usr/bin/hidutil`, so it can act as a
/// Hyper modifier. Merges with the user's existing mappings and removes only its own.
/// The mapping is lost on reboot and must be re-applied when a keyboard connects.
@MainActor
final class CapsLockRemapper {
    enum RemapError: Error, CustomStringConvertible {
        case hidutilFailed(status: Int32, output: String)

        var description: String {
            switch self {
            case .hidutilFailed(let status, let output): "hidutil exited with \(status): \(output)"
            }
        }
    }

    private let hidutil = URL(fileURLWithPath: "/usr/bin/hidutil")

    func enable() throws {
        try write(KeyMappingCodec.adding(.capsLockToF18, to: currentMappings()))
    }

    func disable() throws {
        let current = try currentMappings()
        guard current.contains(.capsLockToF18) else { return }
        try write(KeyMappingCodec.removing(.capsLockToF18, from: current))
    }

    func currentMappings() throws -> [KeyMapping] {
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

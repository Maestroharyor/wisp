import Darwin
import Foundation

/// Fire-and-forget delivery to Wisp's socket for messages that never get a reply. Plain
/// BSD sockets instead of Network: a Unix connect fails at once when Wisp isn't there, and
/// there's no run loop to start, which keeps the status bar fast.
enum SocketSend {
    /// Sends `data`, waits up to `timeout` for Wisp to close its end, then closes. Hanging up
    /// right after writing loses the message: Wisp's connection can fail before it starts
    /// reading. Any failure is silent; the caller carries on regardless.
    static func send(_ data: Data, to path: String, timeout: TimeInterval) {
        guard let descriptor = connect(to: path, timeout: timeout) else { return }
        defer { close(descriptor) }
        guard write(data, to: descriptor) else { return }
        // Wisp sends nothing back for these messages; EOF means it has read them.
        var scratch: UInt8 = 0
        while read(descriptor, &scratch, 1) > 0 {}
    }

    enum Reply {
        /// Nothing is listening: Wisp isn't running.
        case notRunning
        /// Wisp took the message but didn't finish answering within the timeout.
        case timedOut
        /// The whole reply; empty when Wisp didn't answer (a version that doesn't know the message).
        case data(Data)
    }

    /// Sends `data` and reads Wisp's reply to the end.
    static func request(_ data: Data, to path: String, timeout: TimeInterval) -> Reply {
        guard let descriptor = connect(to: path, timeout: timeout) else { return .notRunning }
        defer { close(descriptor) }
        guard write(data, to: descriptor) else { return .timedOut }
        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { return .data(reply) }
            if count < 0 { return .timedOut }
            reply.append(contentsOf: buffer[0..<count])
        }
    }

    /// A connected socket with send and receive timeouts, or nil.
    private static func connect(to path: String, timeout: TimeInterval) -> Int32? {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let whole = timeout.rounded(.down)
        var limit = timeval(tv_sec: Int(whole), tv_usec: Int32((timeout - whole) * 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(descriptor)
            return nil
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    /// Writes all of `data`, then closes the sending side so Wisp sees the end. False on failure.
    private static func write(_ data: Data, to descriptor: Int32) -> Bool {
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if count <= 0 { return false }
                offset += count
            }
            return true
        }
        if written { shutdown(descriptor, SHUT_WR) }
        return written
    }
}

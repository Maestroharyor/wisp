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
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let whole = timeout.rounded(.down)
        var limit = timeval(tv_sec: Int(whole), tv_usec: Int32((timeout - whole) * 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, base + offset, buffer.count - offset)
                if written <= 0 { return }
                offset += written
            }
        }
        shutdown(descriptor, SHUT_WR)
        // Wisp sends nothing back for these messages; EOF means it has read them.
        var scratch: UInt8 = 0
        while read(descriptor, &scratch, 1) > 0 {}
    }
}

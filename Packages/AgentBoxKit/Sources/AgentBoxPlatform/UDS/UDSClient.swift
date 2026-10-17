import AgentBoxProtocol
import Darwin
import Foundation

/// Conexão cliente a um socket UNIX com framing `u32 len | payload` (08 AR-106). Não bloqueia thread.
public actor UDSConnection {
    private let fd: Int32
    private var decoder: AppSockFrameDecoder
    private var closed = false

    init(fd: Int32, maxFrame: Int) {
        self.fd = fd
        self.decoder = AppSockFrameDecoder(maxLength: maxFrame)
    }

    public func send(_ payload: Data) async throws {
        guard !closed else { throw UDSError.closed }
        try await writeAll(fd: fd, AppSockFrame.encode(payload))
    }

    /// Próximo frame completo; lança `UDSError.closed` no EOF.
    public func receive() async throws -> Data {
        while true {
            if let frame = try decoder.next() { return frame }
            guard !closed else { throw UDSError.closed }
            let chunk = try await readSome(fd: fd)
            if chunk.isEmpty { throw UDSError.closed }
            decoder.append(chunk)
        }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }
}

public enum UDSClient {
    public static func connect(path: String, maxFrame: Int = AppSockFrame.defaultMaxLength) throws -> UDSConnection {
        var addr = try makeSockAddr(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UDSError.syscall("socket", errno) }
        let rc = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let e = errno
            Darwin.close(fd)
            throw UDSError.syscall("connect", e)
        }
        do { try setNonBlocking(fd) } catch {
            Darwin.close(fd)
            throw error
        }
        return UDSConnection(fd: fd, maxFrame: maxFrame)
    }

    /// `true` se alguém aceita conexões em `path`.
    public static func isListening(path: String) -> Bool {
        guard let addr0 = try? makeSockAddr(path) else { return false }
        var addr = addr0
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        return withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
    }
}

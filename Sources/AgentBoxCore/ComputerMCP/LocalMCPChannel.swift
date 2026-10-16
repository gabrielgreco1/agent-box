import Darwin
import Foundation

public enum LocalMCPError: Error, LocalizedError, Equatable {
    case invalidSocketPath, insecureDirectory, socketExists, connectionFailed
    case malformedMessage, messageTooLarge, responseTooLarge, timedOut, stopped

    public var errorDescription: String? {
        switch self {
        case .invalidSocketPath: return "Caminho do socket MCP inválido."
        case .insecureDirectory: return "A pasta do socket MCP precisa pertencer ao usuário e ter permissão 0700."
        case .socketExists: return "O caminho do socket MCP já existe."
        case .connectionFailed: return "Não foi possível conectar ao canal MCP local."
        case .malformedMessage: return "Mensagem MCP inválida."
        case .messageTooLarge: return "Mensagem MCP excede 64 KiB."
        case .responseTooLarge: return "Resposta MCP excede 12 MiB."
        case .timedOut: return "O canal MCP local não respondeu no prazo."
        case .stopped: return "O canal MCP local foi encerrado."
        }
    }
}

private enum LocalMCPWire {
    static let requestLimit = 65_536
    static let responseLimit = 12 * 1_048_576
    static let requestTimeoutSeconds = 10
    static let handlerTimeoutSeconds = 60
    static let responseTimeoutSeconds = 65

    static func address(_ path: String) throws -> (sockaddr_un, socklen_t) {
        guard path.hasPrefix("/"), !path.contains("\n"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { throw LocalMCPError.invalidSocketPath }
        let bytes = Array(path.utf8CString)
        var address = sockaddr_un()
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw LocalMCPError.invalidSocketPath }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { source in target.copyBytes(from: source) }
        }
        return (address, socklen_t(MemoryLayout<sockaddr_un>.size))
    }

    static func setTimeouts(_ fd: Int32, receiveSeconds: Int, sendSeconds: Int) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var receiveTimeout = timeval(tv_sec: receiveSeconds, tv_usec: 0)
        var sendTimeout = timeval(tv_sec: sendSeconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
    }

    static func readLine(_ fd: Int32, limit: Int, deadlineSeconds: Int) throws -> Data {
        var bytes = Data()
        var chunk = [UInt8](repeating: 0, count: 4_096)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(deadlineSeconds)
        while bytes.count <= limit {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw LocalMCPError.timedOut }
            var pollEntry = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollMilliseconds = Int32(min(Double(Int32.max), max(1, remaining * 1_000)))
            let ready = Darwin.poll(&pollEntry, 1, pollMilliseconds)
            if ready == 0 { throw LocalMCPError.timedOut }
            if ready < 0 {
                if errno == EINTR { continue }
                throw LocalMCPError.connectionFailed
            }
            guard (pollEntry.revents & Int16(POLLIN)) != 0 else { throw LocalMCPError.connectionFailed }
            let count = chunk.withUnsafeMutableBytes { buffer in
                Darwin.recv(fd, buffer.baseAddress, buffer.count, MSG_DONTWAIT)
            }
            if count > 0 {
                let received = chunk.prefix(count)
                if let newline = received.firstIndex(of: 10) {
                    let prefix = received.prefix(upTo: newline)
                    guard bytes.count + prefix.count <= limit else {
                        throw limit == requestLimit ? LocalMCPError.messageTooLarge : LocalMCPError.responseTooLarge
                    }
                    // This transport accepts exactly one line per connection.
                    guard received.distance(from: newline, to: received.endIndex) == 1 else {
                        throw LocalMCPError.malformedMessage
                    }
                    bytes.append(contentsOf: prefix)
                    return bytes
                }
                guard bytes.count + received.count <= limit else {
                    throw limit == requestLimit ? LocalMCPError.messageTooLarge : LocalMCPError.responseTooLarge
                }
                bytes.append(contentsOf: received)
                continue
            }
            if count == 0 { throw LocalMCPError.connectionFailed }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { continue }
            throw LocalMCPError.connectionFailed
        }
        throw limit == requestLimit ? LocalMCPError.messageTooLarge : LocalMCPError.responseTooLarge
    }

    static func writeLine(_ data: Data, to fd: Int32, deadlineSeconds: Int) throws {
        var line = data
        line.append(10)
        let deadline = ProcessInfo.processInfo.systemUptime + Double(deadlineSeconds)
        try line.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { throw LocalMCPError.timedOut }
                var pollEntry = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                let pollMilliseconds = Int32(min(Double(Int32.max), max(1, remaining * 1_000)))
                let ready = Darwin.poll(&pollEntry, 1, pollMilliseconds)
                if ready == 0 { throw LocalMCPError.timedOut }
                if ready < 0 {
                    if errno == EINTR { continue }
                    throw LocalMCPError.connectionFailed
                }
                guard (pollEntry.revents & Int16(POLLOUT)) != 0 else { throw LocalMCPError.connectionFailed }
                let written = Darwin.send(fd, base.advanced(by: offset), buffer.count - offset, MSG_DONTWAIT)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else {
                    if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    throw LocalMCPError.connectionFailed
                }
                offset += written
            }
        }
    }

    static func errorResponse(_ code: Int, _ message: String) -> Data {
        let response: [String: Any] = ["jsonrpc": "2.0", "id": NSNull(),
            "error": ["code": code, "message": message]]
        return (try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func secureParent(of path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
        var info = stat()
        guard lstat(parent, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              info.st_uid == getuid(), (info.st_mode & 0o777) == 0o700 else {
            throw LocalMCPError.insecureDirectory
        }
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count <= 256, b.count <= 256 else { return false }
        var difference = a.count ^ b.count
        for index in 0..<256 { difference |= Int(index < a.count ? a[index] : 0) ^ Int(index < b.count ? b[index] : 0) }
        return difference == 0
    }
}

/// One JSON-RPC envelope per Unix socket connection. The capability never appears in logs.
public final class LocalMCPServer: @unchecked Sendable {
    private let socketPath: String
    private let capability: String
    private let handler: @Sendable (Data) async throws -> Data
    private let lock = NSLock()
    private var listener: Int32
    private var ownedInode: ino_t
    private var stopped = false
    private var clients = Set<Int32>()
    private var activeHandlers = 0

    public init(socketPath: String, capability: String,
                handler: @escaping @Sendable (Data) async throws -> Data) throws {
        guard !capability.isEmpty, capability.utf8.count <= 256 else { throw LocalMCPError.malformedMessage }
        let (address, length) = try LocalMCPWire.address(socketPath)
        try LocalMCPWire.secureParent(of: socketPath)
        var prior = stat()
        guard lstat(socketPath, &prior) != 0, errno == ENOENT else { throw LocalMCPError.socketExists }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalMCPError.connectionFailed }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var bound = false
        do {
            var mutableAddress = address
            let result = withUnsafePointer(to: &mutableAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, length) }
            }
            guard result == 0 else { throw LocalMCPError.connectionFailed }
            bound = true
            guard chmod(socketPath, 0o600) == 0, Darwin.listen(fd, 8) == 0,
                  fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else {
                throw LocalMCPError.connectionFailed
            }
            var info = stat()
            guard lstat(socketPath, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
                  info.st_uid == getuid() else { throw LocalMCPError.connectionFailed }
            self.socketPath = socketPath
            self.capability = capability
            self.handler = handler
            self.listener = fd
            self.ownedInode = info.st_ino
            DispatchQueue.global(qos: .utility).async { [self] in acceptLoop() }
        } catch {
            _ = Darwin.close(fd)
            if bound { _ = Darwin.unlink(socketPath) }
            throw error
        }
    }

    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let fd = listener
        listener = -1
        _ = Darwin.shutdown(fd, SHUT_RDWR)
        _ = Darwin.close(fd)
        for client in clients { _ = Darwin.shutdown(client, SHUT_RDWR) }
        lock.unlock()
        var info = stat()
        if lstat(socketPath, &info) == 0,
           (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
           info.st_uid == getuid(), info.st_ino == ownedInode {
            _ = Darwin.unlink(socketPath)
        }
    }

    private func acceptLoop() {
        while true {
            lock.lock(); let fd = listener; let shouldStop = stopped; lock.unlock()
            if shouldStop || fd < 0 { return }
            var pollEntry = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pollEntry, 1, 250)
            if ready <= 0 { continue }
            guard (pollEntry.revents & Int16(POLLIN)) != 0 else { continue }
            lock.lock()
            let client = stopped ? -1 : Darwin.accept(fd, nil, nil)
            lock.unlock()
            if client < 0 { continue }
            LocalMCPWire.setTimeouts(client, receiveSeconds: LocalMCPWire.requestTimeoutSeconds,
                                     sendSeconds: LocalMCPWire.responseTimeoutSeconds)
            lock.lock()
            let accepted = !stopped && clients.count < 8
            if accepted { clients.insert(client) }
            lock.unlock()
            guard accepted else { _ = Darwin.close(client); continue }
            DispatchQueue.global(qos: .utility).async { [self] in
                handle(client)
                lock.lock(); let owned = clients.remove(client) != nil; lock.unlock()
                if owned { _ = Darwin.close(client) }
            }
        }
    }

    private func handle(_ client: Int32) {
        let request: Data
        do {
            request = try LocalMCPWire.readLine(client, limit: LocalMCPWire.requestLimit,
                                                 deadlineSeconds: LocalMCPWire.requestTimeoutSeconds)
        }
        catch {
            try? LocalMCPWire.writeLine(LocalMCPWire.errorResponse(-32002, "Invalid or oversized request"),
                                        to: client, deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
            return
        }
        guard let envelope = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
              let supplied = envelope["capability"] as? String,
              LocalMCPWire.constantTimeEqual(supplied, capability) else {
            try? LocalMCPWire.writeLine(LocalMCPWire.errorResponse(-32001, "Unauthorized"),
                                        to: client, deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
            return
        }
        guard let message = envelope["message"] as? [String: Any],
              let raw = try? JSONSerialization.data(withJSONObject: message),
              raw.count <= LocalMCPWire.requestLimit else {
            try? LocalMCPWire.writeLine(LocalMCPWire.errorResponse(-32700, "Invalid JSON-RPC message"),
                                        to: client, deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
            return
        }
        lock.lock()
        let canHandle = !stopped && activeHandlers < 8
        if canHandle { activeHandlers += 1 }
        lock.unlock()
        guard canHandle else {
            try? LocalMCPWire.writeLine(LocalMCPWire.errorResponse(-32004, "Server busy"),
                                        to: client, deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
            return
        }
        let completion = HandlerCompletion()
        let task = Task {
            do { completion.finish(.success(try await handler(raw))) }
            catch { completion.finish(.failure(error)) }
            handlerFinished()
        }
        guard let response = completion.wait(seconds: LocalMCPWire.handlerTimeoutSeconds) else {
            task.cancel()
            try? LocalMCPWire.writeLine(LocalMCPWire.errorResponse(-32003, "Handler timed out"),
                                        to: client, deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
            return
        }
        do {
            let data = try response.get()
            guard data.count <= LocalMCPWire.responseLimit else { throw LocalMCPError.responseTooLarge }
            if !data.isEmpty {
                guard (try? JSONSerialization.jsonObject(with: data)) != nil else { throw LocalMCPError.malformedMessage }
            }
            try LocalMCPWire.writeLine(data, to: client,
                                       deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
        } catch {
            try? LocalMCPWire.writeLine(LocalMCPWire.errorResponse(-32603, "Internal error"),
                                        to: client, deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
        }
    }

    private func handlerFinished() {
        lock.lock(); activeHandlers -= 1; lock.unlock()
    }

    private final class HandlerCompletion: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var outcome: Result<Data, Error>?
        func finish(_ value: Result<Data, Error>) {
            lock.lock(); outcome = value; lock.unlock(); semaphore.signal()
        }
        func wait(seconds: Int) -> Result<Data, Error>? {
            guard semaphore.wait(timeout: .now() + .seconds(seconds)) == .success else { return nil }
            lock.lock(); defer { lock.unlock() }; return outcome
        }
    }
}

public enum LocalMCPClient {
    public static func send(message: Data, socketPath: String, capability: String) throws -> Data {
        guard message.count <= LocalMCPWire.requestLimit else { throw LocalMCPError.messageTooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any] else {
            throw LocalMCPError.malformedMessage
        }
        let envelope = try JSONSerialization.data(withJSONObject: ["capability": capability, "message": object])
        guard envelope.count <= LocalMCPWire.requestLimit else { throw LocalMCPError.messageTooLarge }
        let (address, length) = try LocalMCPWire.address(socketPath)
        try LocalMCPWire.secureParent(of: socketPath)
        var socketInfo = stat()
        guard lstat(socketPath, &socketInfo) == 0,
              (socketInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
              socketInfo.st_uid == getuid(), (socketInfo.st_mode & 0o777) == 0o600 else {
            throw LocalMCPError.connectionFailed
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalMCPError.connectionFailed }
        defer { _ = Darwin.close(fd) }
        LocalMCPWire.setTimeouts(fd, receiveSeconds: LocalMCPWire.responseTimeoutSeconds,
                                 sendSeconds: LocalMCPWire.requestTimeoutSeconds)
        var mutableAddress = address
        let connected = withUnsafePointer(to: &mutableAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
        }
        guard connected == 0 else { throw LocalMCPError.connectionFailed }
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(fd, &peerUID, &peerGID) == 0, peerUID == getuid() else {
            throw LocalMCPError.connectionFailed
        }
        try LocalMCPWire.writeLine(envelope, to: fd,
                                   deadlineSeconds: LocalMCPWire.requestTimeoutSeconds)
        return try LocalMCPWire.readLine(fd, limit: LocalMCPWire.responseLimit,
                                         deadlineSeconds: LocalMCPWire.responseTimeoutSeconds)
    }
}

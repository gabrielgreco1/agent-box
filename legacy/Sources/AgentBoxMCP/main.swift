import AgentBoxCore
import Darwin
import Foundation

private func readCapability(_ path: String) throws -> String {
    var info = stat()
    guard path.hasPrefix("/"), lstat(path, &info) == 0,
          (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
          info.st_uid == getuid(), (info.st_mode & 0o777) == 0o600,
          info.st_size > 0, info.st_size <= 256 else { throw LocalMCPError.malformedMessage }
    let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw LocalMCPError.malformedMessage }
    defer { _ = Darwin.close(fd) }
    var opened = stat()
    guard fstat(fd, &opened) == 0, opened.st_ino == info.st_ino,
          opened.st_uid == getuid(), (opened.st_mode & 0o777) == 0o600,
          opened.st_size == info.st_size else {
        throw LocalMCPError.malformedMessage
    }
    var bytes = [UInt8](repeating: 0, count: Int(info.st_size))
    var offset = 0
    while offset < bytes.count {
        let remaining = bytes.count - offset
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(fd, buffer.baseAddress!.advanced(by: offset), remaining)
        }
        guard count > 0 else { throw LocalMCPError.malformedMessage }
        offset += count
    }
    guard var value = String(bytes: bytes, encoding: .utf8) else { throw LocalMCPError.malformedMessage }
    if value.hasSuffix("\n") { value.removeLast() }
    guard !value.isEmpty, value.utf8.count <= 256, !value.contains("\n") else {
        throw LocalMCPError.malformedMessage
    }
    return value
}

private func readStdinLine() throws -> Data? {
    var data = Data()
    while data.count <= 65_536 {
        var byte: UInt8 = 0
        let count = Darwin.read(STDIN_FILENO, &byte, 1)
        if count == 1 {
            if byte == 10 { return data }
            data.append(byte)
            continue
        }
        if count == 0 { return data.isEmpty ? nil : data }
        if errno == EINTR { continue }
        throw LocalMCPError.connectionFailed
    }
    throw LocalMCPError.messageTooLarge
}

private func writeStdout(_ response: Data) throws {
    guard !response.isEmpty else { return }
    var line = response
    line.append(10)
    try line.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        var offset = 0
        while offset < buffer.count {
            let count = Darwin.write(STDOUT_FILENO, base.advanced(by: offset), buffer.count - offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw LocalMCPError.connectionFailed }
            offset += count
        }
    }
}

private final class ForwardingState: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false

    var hasFailed: Bool {
        lock.lock(); defer { lock.unlock() }
        return failed
    }

    func send(_ response: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !failed else { return }
        do { try writeStdout(response) }
        catch {
            // Hold the stdout lock through process exit so another worker
            // cannot begin a JSON-RPC line after this transport has failed.
            failed = true
            Darwin._exit(3)
        }
    }

    func failAndExit() {
        // There is no safe invented response ID for a failed socket request.
        // Exiting closes stdio immediately, waking a CLI that is still waiting
        // for its reply while keeping any other stdout line complete.
        lock.lock()
        failed = true
        Darwin._exit(3)
    }
}

private func method(of request: Data) -> String? {
    guard let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any] else { return nil }
    return object["method"] as? String
}

let arguments = CommandLine.arguments
guard arguments.count == 5, arguments[1] == "--socket", arguments[3] == "--capability-file" else {
    exit(2)
}
do {
    // A closed Claude reader must make write(2) fail cleanly rather than kill
    // the helper with SIGPIPE while another request is still in flight.
    _ = signal(SIGPIPE, SIG_IGN)
    let capability = try readCapability(arguments[4])
    let state = ForwardingState()
    let slots = DispatchSemaphore(value: 8)
    let pending = DispatchGroup()
    var initialized = false
    var notificationSeen = false
    while let request = try readStdinLine() {
        guard !state.hasFailed else { throw LocalMCPError.connectionFailed }
        let requestMethod = method(of: request)
        if !notificationSeen {
            // Keep initialization and its notification ordered on the local
            // transport. A malformed/pre-init message is still handled by the
            // server, but cannot open the concurrent forwarding phase.
            let response = try LocalMCPClient.send(message: request, socketPath: arguments[2], capability: capability)
            try writeStdout(response)
            if requestMethod == "initialize", !response.isEmpty { initialized = true }
            if initialized, requestMethod == "notifications/initialized" { notificationSeen = true }
            continue
        }
        slots.wait() // At most eight workers; stdin pipe supplies backpressure.
        guard !state.hasFailed else { slots.signal(); throw LocalMCPError.connectionFailed }
        pending.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { slots.signal(); pending.leave() }
            do {
                let response = try LocalMCPClient.send(message: request, socketPath: arguments[2], capability: capability)
                state.send(response) // One complete JSON-RPC line per locked write.
            } catch { state.failAndExit() }
        }
    }
    pending.wait() // EOF is not completion until every owned request has replied.
    guard !state.hasFailed else { throw LocalMCPError.connectionFailed }
} catch {
    // This helper emits only JSON-RPC responses on stdout. Do not print secrets or raw input.
    exit(3)
}

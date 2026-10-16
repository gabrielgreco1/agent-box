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

let arguments = CommandLine.arguments
guard arguments.count == 5, arguments[1] == "--socket", arguments[3] == "--capability-file" else {
    exit(2)
}
do {
    let capability = try readCapability(arguments[4])
    while let request = try readStdinLine() {
        let response = try LocalMCPClient.send(message: request, socketPath: arguments[2], capability: capability)
        try writeStdout(response)
    }
} catch {
    // This helper emits only JSON-RPC responses on stdout. Do not print secrets or raw input.
    exit(3)
}

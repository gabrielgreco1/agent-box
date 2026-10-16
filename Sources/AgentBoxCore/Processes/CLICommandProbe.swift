import Foundation
import Darwin

public struct CLICommandResult: Equatable {
    public let exitCode: Int32?
    public let output: String
    public let timedOut: Bool

    public init(exitCode: Int32?, output: String, timedOut: Bool) {
        self.exitCode = exitCode; self.output = output; self.timedOut = timedOut
    }
}

/// Runs a read-only CLI probe off the main thread. Callers choose only documented,
/// non-mutating argv. Output is bounded and never logged by this runner.
public enum CLICommandProbe {
    public static func run(executable: String, arguments: [String], timeout: TimeInterval = 3) async -> CLICommandResult {
        await Task.detached(priority: .utility) {
            runSynchronously(executable: executable, arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runSynchronously(executable: String, arguments: [String], timeout: TimeInterval) -> CLICommandResult {
        let process = Process()
        let pipe = Pipe()
        let lock = NSLock()
        var captured = Data()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            lock.lock()
            if captured.count < 16_384 { captured.append(bytes.prefix(16_384 - captured.count)) }
            lock.unlock()
        }
        do { try process.run() }
        catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return CLICommandResult(exitCode: nil, output: error.localizedDescription, timedOut: false)
        }

        let done = DispatchGroup()
        done.enter()
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            done.leave()
        }
        let limit = max(0.05, timeout)
        let timedOut = done.wait(timeout: .now() + limit) == .timedOut
        if timedOut {
            _ = Darwin.kill(process.processIdentifier, SIGTERM)
            if done.wait(timeout: .now() + 0.3) == .timedOut {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 1)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        // Drain only bytes currently available. A descendant may still hold the
        // pipe open after the direct CLI exits, so waiting for EOF could hang.
        let fd = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        var remaining = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while remaining.count < 16_384 {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count <= 0 { break }
            remaining.append(contentsOf: buffer.prefix(count))
        }
        lock.lock()
        if captured.count < 16_384 { captured.append(remaining.prefix(16_384 - captured.count)) }
        let text = String(decoding: captured, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        return CLICommandResult(exitCode: timedOut ? nil : process.terminationStatus, output: text, timedOut: timedOut)
    }
}

public enum CLIVersionProbeResult: Equatable {
    case version(String)
    case timedOut
    case failed(String)
}

public enum CLIVersionProbe {
    public static func run(executable: String, timeout: TimeInterval = 3) async -> CLIVersionProbeResult {
        let result = await CLICommandProbe.run(executable: executable, arguments: ["--version"], timeout: timeout)
        if result.timedOut { return .timedOut }
        if result.exitCode == 0 && !result.output.isEmpty { return .version(result.output) }
        return .failed(result.output.isEmpty ? "Version check failed." : result.output)
    }
}

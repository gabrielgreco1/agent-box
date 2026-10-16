import Foundation
import Darwin

public struct GitCommandResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr
    }
}

public enum GitCommandError: Error, LocalizedError {
    case executableMissing
    case launchFailed(String)
    case timedOut
    public var errorDescription: String? {
        switch self {
        case .executableMissing: return "Git não está instalado."
        case .launchFailed(let detail): return "Não foi possível iniciar Git: \(detail)"
        case .timedOut: return "O comando Git excedeu o tempo limite."
        }
    }
}

public protocol GitCommandRunning {
    func run(_ arguments: [String], timeout: TimeInterval) throws -> GitCommandResult
}

/// Runs Git as argv, never through a shell. Output and execution time are bounded.
public struct GitProcessRunner: GitCommandRunning {
    public let executableURL: URL?
    public init(executableURL: URL? = GitProcessRunner.findExecutable()) { self.executableURL = executableURL }

    public static func findExecutable() -> URL? {
        let directories = ["/usr/bin", "/opt/homebrew/bin", "/usr/local/bin"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("git")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public func run(_ arguments: [String], timeout: TimeInterval) throws -> GitCommandResult {
        guard let executableURL else { throw GitCommandError.executableMissing }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw GitCommandError.launchFailed(error.localizedDescription) }
        output.fileHandleForWriting.closeFile()
        errors.fileHandleForWriting.closeFile()
        let group = DispatchGroup()
        let capturedOutput = GitBoundedOutput(), capturedErrors = GitBoundedOutput()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capturedOutput.drain(output.fileHandleForReading); group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capturedErrors.drain(errors.fileHandleForReading); group.leave()
        }
        if finished.wait(timeout: .now() + max(0.1, timeout)) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            output.fileHandleForReading.closeFile()
            errors.fileHandleForReading.closeFile()
            throw GitCommandError.timedOut
        }
        if group.wait(timeout: .now() + 2) == .timedOut {
            output.fileHandleForReading.closeFile()
            errors.fileHandleForReading.closeFile()
        }
        return GitCommandResult(exitCode: process.terminationStatus,
                                stdout: capturedOutput.text, stderr: capturedErrors.text)
    }
}

private final class GitBoundedOutput {
    private let lock = NSLock()
    private var data = Data()
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 16 * 1024)
            if chunk.isEmpty { return }
            lock.lock()
            if data.count < 1_048_576 { data.append(chunk.prefix(1_048_576 - data.count)) }
            lock.unlock()
        }
    }
}

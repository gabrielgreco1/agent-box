import Foundation
import Darwin

public struct DockerCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode; self.stdout = stdout; self.stderr = stderr
    }
}

public enum DockerCommandError: Error, LocalizedError, Equatable {
    case executableMissing
    case timedOut
    case launchFailed(String)
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .executableMissing: return "Docker CLI não encontrado. Instale e inicie um runtime compatível."
        case .timedOut: return "O comando Docker excedeu o tempo limite. Verifique o runtime."
        case .launchFailed(let detail): return "Não foi possível executar Docker: \(detail)"
        case .failed(let detail): return detail
        }
    }
}

public protocol DockerCommandRunning {
    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult
}

/// Uses argv directly; neither shell expansion nor inherited stdin is involved.
public struct DockerProcessRunner: DockerCommandRunning {
    public let executableURL: URL?
    public init(executableURL: URL? = DockerProcessRunner.findExecutable()) { self.executableURL = executableURL }

    public static func findExecutable() -> URL? {
        let envPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let paths = envPaths + ["/usr/local/bin", "/opt/homebrew/bin", "/Applications/Docker.app/Contents/Resources/bin"]
        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent("docker")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        guard let executableURL else { throw DockerCommandError.executableMissing }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw DockerCommandError.launchFailed(error.localizedDescription) }
        let group = DispatchGroup()
        let capturedOut = BoundedOutput(), capturedErr = BoundedOutput()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capturedOut.drain(out.fileHandleForReading)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capturedErr.drain(err.fileHandleForReading)
            group.leave()
        }
        if finished.wait(timeout: .now() + max(0.1, timeout)) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            out.fileHandleForReading.closeFile(); err.fileHandleForReading.closeFile()
            throw DockerCommandError.timedOut
        }
        _ = group.wait(timeout: .now() + 2)
        return DockerCommandResult(exitCode: process.terminationStatus,
                                   stdout: capturedOut.text,
                                   stderr: capturedErr.text)
    }
}

private final class BoundedOutput {
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

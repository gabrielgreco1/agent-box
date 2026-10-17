import Foundation

/// Pedido de execução de um processo (argv, nunca shell). 08 AR-404/AR-131.
public struct ProcessRequest: Sendable {
    public var executable: URL
    public var arguments: [String]
    /// Variáveis somadas ao ambiente herdado (valores do pedido vencem).
    public var environment: [String: String]
    public var currentDirectory: URL?
    public var timeout: Duration
    /// Limite por stream (stdout e stderr); o excedente é descartado e `truncated` fica verdadeiro.
    public var maxOutputBytes: Int

    public init(executable: URL, arguments: [String], environment: [String: String] = [:],
                currentDirectory: URL? = nil, timeout: Duration = .seconds(30),
                maxOutputBytes: Int = 4 * 1024 * 1024) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
    }
}

public struct ProcessOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data
    public let truncated: Bool

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timedOut
    case cancelled
}

/// Executa processos sem ocupar o pool cooperativo: sem semáforo nem espera bloqueante; a leitura dos
/// pipes e o término vêm por callbacks do GCD e retomam uma continuation.
public enum ProcessRunner {
    public static func run(_ request: ProcessRequest) async throws -> ProcessOutput {
        let session = ProcessSession(request: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.start(continuation)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

/// Estado de uma execução. Todo acesso passa por `lock`; nenhum I/O ocorre sob o lock.
private final class ProcessSession: @unchecked Sendable { // SAFETY: todo estado mutável é protegido por `lock`.
    private enum Ending { case timedOut, cancelled }

    private let request: ProcessRequest
    private let process = Process()
    private let outPipe = Pipe()
    private let errPipe = Pipe()
    private let lock = NSLock() // LOCK: protege só os campos abaixo, sem I/O sob o lock.
    private var continuation: CheckedContinuation<ProcessOutput, any Error>?
    private var stdout = Data()
    private var stderr = Data()
    private var truncated = false
    private var openStreams = 2
    private var exited = false
    private var exitCode: Int32 = 0
    private var ending: Ending?
    private var finished = false
    private var started = false

    init(request: ProcessRequest) { self.request = request }

    func start(_ continuation: CheckedContinuation<ProcessOutput, any Error>) {
        lock.lock()
        if ending == .cancelled {
            finished = true
            lock.unlock()
            continuation.resume(throwing: ProcessRunnerError.cancelled)
            return
        }
        self.continuation = continuation
        lock.unlock()

        process.executableURL = request.executable
        process.arguments = request.arguments
        process.currentDirectoryURL = request.currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(request.environment) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            consume(handle.availableData, isStdout: true)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            consume(handle.availableData, isStdout: false)
        }
        process.terminationHandler = { [self] proc in
            lock.lock()
            exited = true
            exitCode = proc.terminationStatus
            lock.unlock()
            // Neto que herdou o pipe (ex.: daemon do git) não pode segurar o resultado.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
                finish(force: true)
            }
            finish(force: false)
        }
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            complete(.failure(ProcessRunnerError.launchFailed(error.localizedDescription)))
            return
        }
        lock.lock()
        started = true
        let cancelledEarly = ending == .cancelled
        lock.unlock()
        if cancelledEarly { terminateHard() }
        let parts = request.timeout.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.05, seconds)) { [self] in
            expire()
        }
    }

    func cancel() {
        lock.lock()
        if finished { lock.unlock(); return }
        if ending == nil { ending = .cancelled }
        let running = started
        lock.unlock()
        if running { terminateHard() }
    }

    private func expire() {
        lock.lock()
        if finished || exited { lock.unlock(); return }
        if ending == nil { ending = .timedOut }
        lock.unlock()
        terminateHard()
    }

    /// SIGTERM e, se o processo ainda viver depois de 1 s, SIGKILL.
    private func terminateHard() {
        if process.isRunning { process.terminate() }
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [self] in
            lock.lock()
            let alive = !exited && !finished
            lock.unlock()
            if alive { kill(pid, SIGKILL) }
        }
    }

    private func consume(_ data: Data, isStdout: Bool) {
        if data.isEmpty {
            let handle = isStdout ? outPipe.fileHandleForReading : errPipe.fileHandleForReading
            handle.readabilityHandler = nil
            lock.lock()
            openStreams -= 1
            lock.unlock()
            finish(force: false)
            return
        }
        lock.lock()
        let room = request.maxOutputBytes - (isStdout ? stdout.count : stderr.count)
        if data.count > room { truncated = true }
        if room > 0 {
            if isStdout { stdout.append(data.prefix(room)) } else { stderr.append(data.prefix(room)) }
        }
        lock.unlock()
    }

    private func finish(force: Bool) {
        lock.lock()
        let ready = exited && (openStreams <= 0 || force || ending != nil)
        lock.unlock()
        guard ready else { return }
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        let result: Result<ProcessOutput, any Error>
        switch ending {
        case .timedOut: result = .failure(ProcessRunnerError.timedOut)
        case .cancelled: result = .failure(ProcessRunnerError.cancelled)
        case nil:
            result = .success(ProcessOutput(exitCode: exitCode, stdout: stdout, stderr: stderr,
                                            truncated: truncated))
        }
        lock.unlock()
        complete(result)
    }

    private func complete(_ result: Result<ProcessOutput, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        finished = true
        lock.unlock()
        pending?.resume(with: result)
    }
}

import AgentBoxPlatform
import AgentBoxProtocol
import Foundation

// MARK: Eventos de progresso (04 §7.2.2)

/// Etapa real do lançamento. A UI mostra só as que têm `title` (a lista de M-503); as demais são emitidas para
/// diagnóstico e testes.
public enum LaunchStepKey: String, Sendable, Equatable, CaseIterable {
    case cliResolve = "cli.resolve"
    case envLogin = "env.login"
    case gitFetch = "git.fetch"
    case gitWorktree = "git.worktree"
    case launchConfig = "launch.config"
    case ptySpawn = "pty.spawn"
    case cliExec = "cli.exec"

    /// Texto da linha na checklist; `nil` = a etapa não aparece (04 §7.2.2).
    public func title(agent: String) -> String? {
        switch self {
        case .gitFetch: "Fetching origin…"
        case .gitWorktree: "Creating worktree…"
        case .launchConfig: "Preparing launch"
        case .cliExec: "Starting \(agent)…"
        case .cliResolve, .envLogin, .ptySpawn: nil
        }
    }
}

public enum LaunchStepStatus: String, Sendable, Equatable {
    case running, done, failed, skipped
}

public struct LaunchProgress: Sendable, Equatable {
    public var runID: UUID
    public var step: LaunchStepKey
    public var status: LaunchStepStatus
    public var detail: String?
    public var progress: Double?
    public var at: Date

    public init(runID: UUID, step: LaunchStepKey, status: LaunchStepStatus, detail: String? = nil, progress: Double? = nil, at: Date = Date()) {
        self.runID = runID; self.step = step; self.status = status; self.detail = detail; self.progress = progress; self.at = at
    }
}

public enum LaunchEvent: Sendable, Equatable {
    case step(LaunchProgress)
    /// O ID nativo da conversa foi capturado depois do spawn (Codex/OpenCode; Claude já sai do plano).
    case nativeID(runID: UUID, id: String)
    /// Primeiro byte do PTY chegou (fim da ignição, M-504).
    case firstOutput(runID: UUID)
}

/// Falhas do lançamento mostradas no estado "Couldn't start" (03 §4.6).
public enum LaunchFailure: Error, Sendable, Equatable {
    case daemonUnavailable
    case cliNotFound(String)
    case plan(String)
    case workspace(String)
    case spawn(String)
    case cancelled
}

extension LaunchFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .daemonUnavailable: "The background service isn't running."
        case .cliNotFound(let name): "\(name) isn't installed or isn't on your PATH."
        case .plan(let detail), .workspace(let detail), .spawn(let detail): detail
        case .cancelled: "Launch cancelled."
        }
    }

    /// Etapa em que a falha aconteceu (a linha que recebe o X vermelho, M-505).
    public var step: LaunchStepKey {
        switch self {
        case .cliNotFound: .cliResolve
        case .daemonUnavailable, .spawn, .cancelled: .ptySpawn
        case .plan: .launchConfig
        case .workspace: .gitWorktree
        }
    }
}

// MARK: Dependências (injetáveis)

public protocol LaunchDaemonGateway: Sendable {
    func connect() async -> Bool
    func create(_ request: CreateRequest) async throws -> SessionSummary
    func kill(sessionID: SessionID) async
}

/// Etapa opcional de Git/worktree (T1-18) que roda antes do terminal. Recebe um emissor para `git.fetch` e `git.worktree`.
public typealias LaunchWorkspaceStep = @Sendable (_ emit: @Sendable (LaunchStepKey, LaunchStepStatus, String?) -> Void) async throws -> Void

public struct LaunchJob: Sendable {
    public var terminalID: UUID
    public var spec: LaunchSpec
    public var cwd: String
    public var addDirs: [String]
    public var projectID: UUID?
    public var coldLog: Bool
    public var cols: UInt16
    public var rows: UInt16
    public var catalog: ProfileCatalog
    public var workspace: LaunchWorkspaceStep?
    /// `.resume`/`.continueLast` no Resume depois de reabrir (T1-23); `.automatic` no start normal.
    public var mode: LaunchMode

    public init(
        terminalID: UUID, spec: LaunchSpec, cwd: String, addDirs: [String] = [], projectID: UUID? = nil, coldLog: Bool = true,
        cols: UInt16 = 100, rows: UInt16 = 30, catalog: ProfileCatalog = ProfileCatalog(), workspace: LaunchWorkspaceStep? = nil,
        mode: LaunchMode = .automatic
    ) {
        self.mode = mode
        self.terminalID = terminalID; self.spec = spec; self.cwd = cwd; self.addDirs = addDirs; self.projectID = projectID
        self.coldLog = coldLog; self.cols = cols; self.rows = rows; self.catalog = catalog; self.workspace = workspace
    }
}

public struct LaunchResult: Sendable {
    public var runID: UUID
    public var plan: LaunchPlan
    public var summary: SessionSummary
}

/// Decide o que um `exit` significa para o pane (03 §4.6, M-505): saída com erro antes de qualquer byte é falha de
/// lançamento ("Couldn't start"), não "Terminal exited".
public enum LaunchExitClassifier {
    public enum Verdict: Equatable, Sendable {
        case exited
        case failedToStart(String)
    }

    public static func classify(firstOutputSeen: Bool, code: Int?, signal: Int?, agent: String) -> Verdict {
        guard !firstOutputSeen else { return .exited }
        if let signal { return .failedToStart("\(agent) was killed (signal \(signal)) before it printed anything.") }
        if let code, code != 0 { return .failedToStart("\(agent) exited with code \(code) before it printed anything.") }
        return .exited
    }
}

/// Executa um `LaunchSpec` num pane: resolve o CLI, captura o env de login, prepara a worktree (se houver), grava os
/// arquivos de lançamento, cria a sessão no daemon e acompanha a primeira saída. Cada etapa vira um `LaunchEvent`
/// real consumido pela UI. O argv é reconstruído a cada chamada (Restart e Try Again passam por aqui de novo).
/// Nada aqui escreve no PTY (T11).
public actor LaunchCoordinator {
    public struct Configuration: Sendable {
        public var launchRoot: URL
        public var appSocketPath: String
        public var appVersion: String
        public var loginEnvironment: @Sendable () async -> [String: String]
        public var resolveExecutable: @Sendable (_ name: String, _ searchPath: String?) -> String?
        public var capabilities: @Sendable (_ provider: TerminalProvider, _ executable: String) async -> CLICapabilities?
        public var capturer: NativeIDCapturer
        public var codexRoot: URL
        public var clock: @Sendable () -> Date
        /// Fatia ligada (`AGENTBOX_SLICE`): a partir da 2, o lançamento leva as injeções por lançamento (hooks de atividade).
        public var slice: LaunchSlice
        /// Conteúdo das injeções por provider. `nil` = sem injeção (Codex sem hashes de trust sondados, helper ausente).
        public var injection: @Sendable (TerminalProvider) -> LaunchInjection?

        public init(
            launchRoot: URL, appSocketPath: String, appVersion: String = "0.1.0",
            loginEnvironment: @escaping @Sendable () async -> [String: String],
            resolveExecutable: @escaping @Sendable (String, String?) -> String? = { CLIExecutableResolver.resolve(name: $0, searchPath: $1) },
            capabilities: @escaping @Sendable (TerminalProvider, String) async -> CLICapabilities? = { _, _ in nil },
            capturer: NativeIDCapturer = NativeIDCapturer(), codexRoot: URL = CodexRolloutScanner.defaultRoot(),
            clock: @escaping @Sendable () -> Date = { Date() }, slice: LaunchSlice = .slice1,
            injection: @escaping @Sendable (TerminalProvider) -> LaunchInjection? = { _ in nil }
        ) {
            self.slice = slice; self.injection = injection
            self.launchRoot = launchRoot; self.appSocketPath = appSocketPath; self.appVersion = appVersion
            self.loginEnvironment = loginEnvironment; self.resolveExecutable = resolveExecutable; self.capabilities = capabilities
            self.capturer = capturer; self.codexRoot = codexRoot; self.clock = clock
        }
    }

    private let daemon: any LaunchDaemonGateway
    private let configuration: Configuration
    private var sinks: [UUID: @Sendable (LaunchEvent) -> Void] = [:]
    private var firstOutputSeen: Set<UUID> = []
    private var execStarted: Set<UUID> = []
    private var running: [UUID: Task<Void, Never>] = [:]
    private var sessions: [UUID: SessionID] = [:]
    private var cancelled: Set<UUID> = []

    public init(daemon: any LaunchDaemonGateway, configuration: Configuration) {
        self.daemon = daemon
        self.configuration = configuration
    }

    /// Roda o lançamento. `onEvent` recebe o progresso (em qualquer thread). `attach` liga a view ao PTY recém-criado
    /// (a primeira saída só chega depois disso); falhas dele contam como falha de spawn.
    public func launch(
        _ job: LaunchJob,
        onEvent: @escaping @Sendable (LaunchEvent) -> Void,
        attach: @escaping @Sendable (SessionSummary, UUID) async throws -> Void = { _, _ in }
    ) async throws -> LaunchResult {
        let runID = UUID.v7()
        sinks[runID] = onEvent
        cancelled.remove(job.terminalID)
        sessions[job.terminalID] = nil
        let clock = configuration.clock
        @Sendable func emit(_ step: LaunchStepKey, _ status: LaunchStepStatus, _ detail: String? = nil) {
            onEvent(.step(LaunchProgress(runID: runID, step: step, status: status, detail: detail, at: clock())))
        }
        func checkCancelled() throws {
            if cancelled.contains(job.terminalID) || Task.isCancelled { throw LaunchFailure.cancelled }
        }

        do {
            // Git / worktree (só quando há etapa; senão as linhas não existem).
            if let workspace = job.workspace {
                do {
                    try await workspace { step, status, detail in emit(step, status, detail) }
                } catch let failure as LaunchFailure {
                    throw failure
                } catch {
                    throw LaunchFailure.workspace("\(error)")
                }
            } else {
                emit(.gitFetch, .skipped)
                emit(.gitWorktree, .skipped)
            }
            try checkCancelled()

            // Env de login e CLI.
            emit(.envLogin, .running)
            let login = await configuration.loginEnvironment()
            emit(.envLogin, .done)
            let adapter = ProviderAdapters.adapter(for: job.spec.provider)
            emit(.cliResolve, .running)
            var executable = job.spec.customArgv?.first ?? ""
            if let name = adapter.executableName {
                guard let found = configuration.resolveExecutable(name, login["PATH"]) else {
                    throw LaunchFailure.cliNotFound(adapter.displayName)
                }
                executable = found
            } else if job.spec.provider == .custom, !executable.contains("/") {
                executable = configuration.resolveExecutable(executable, login["PATH"]) ?? executable
            }
            emit(.cliResolve, .done, executable)
            try checkCancelled()

            // Plano e arquivos de lançamento.
            emit(.launchConfig, .running)
            let launchDirectory = configuration.launchRoot.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true)
            let plan: LaunchPlan
            do {
                let capabilities = await configuration.capabilities(job.spec.provider, executable)
                plan = try LaunchPlanner.plan(
                    LaunchPlanInput(
                        spec: job.spec, terminalID: job.terminalID, runID: runID, cwd: job.cwd, projectID: job.projectID,
                        terminalAddDirs: job.addDirs, catalog: job.catalog, executablePath: executable, capabilities: capabilities,
                        loginEnvironment: login, launchDirectory: launchDirectory, mode: job.mode, slice: configuration.slice,
                        appVersion: configuration.appVersion, appSocketPath: configuration.appSocketPath,
                        injection: configuration.injection(job.spec.provider)))
                try LaunchFileWriter.materialize(plan)
            } catch {
                throw LaunchFailure.plan("\(error)")
            }
            emit(.launchConfig, .done)
            try checkCancelled()

            // Daemon.
            emit(.ptySpawn, .running)
            guard await daemon.connect() else { throw LaunchFailure.daemonUnavailable }
            var openCodeBefore: [OpenCodeSession] = []
            if case .openCodeSessionList(let cwd) = plan.capture {
                openCodeBefore = await configuration.capturer.snapshotOpenCode(executable: executable, environment: plan.environment, cwd: cwd)
            }
            let request = CreateRequest(
                sessionID: SessionID(), argv: plan.flattenedArgv, cwd: plan.cwd, env: plan.environment, cols: job.cols, rows: job.rows,
                coldLog: job.coldLog, owner: SessionOwner(terminalID: job.terminalID.uuidString.lowercased(), runID: runID.uuidString.lowercased()))
            let spawnedAt = clock()
            let summary: SessionSummary
            do {
                summary = try await daemon.create(request)
            } catch let error as PTYClientError {
                LaunchFileWriter.cleanup(launchDirectory: launchDirectory)
                if case .daemon(let daemonError) = error {
                    let path = daemonError.path.map { " (\($0))" } ?? ""
                    throw LaunchFailure.spawn("\(daemonError.message)\(path)")
                }
                throw LaunchFailure.daemonUnavailable
            } catch {
                LaunchFileWriter.cleanup(launchDirectory: launchDirectory)
                throw LaunchFailure.spawn("\(error)")
            }
            sessions[job.terminalID] = summary.sessionID
            if cancelled.contains(job.terminalID) {
                await daemon.kill(sessionID: summary.sessionID)
                throw LaunchFailure.cancelled
            }
            do { try await attach(summary, runID) } catch { throw LaunchFailure.spawn("Couldn't attach to the terminal: \(error)") }
            emit(.ptySpawn, .done)
            emit(.cliExec, .running)
            execStarted.insert(runID)
            if firstOutputSeen.contains(runID) { // o primeiro byte chegou durante o attach
                emit(.cliExec, .done)
                onEvent(.firstOutput(runID: runID))
            }
            startCapture(plan: plan, runID: runID, spawnedAt: spawnedAt, openCodeBefore: openCodeBefore, executable: executable, onEvent: onEvent)
            return LaunchResult(runID: runID, plan: plan, summary: summary)
        } catch {
            let failure = (error as? LaunchFailure) ?? .plan("\(error)")
            emit(failure.step, .failed, failure.errorDescription)
            sinks[runID] = nil
            execStarted.remove(runID)
            throw failure
        }
    }

    /// Chamado pela view no primeiro byte do PTY: fecha a etapa `cli.exec` (M-504). Idempotente.
    public func noteFirstOutput(runID: UUID) {
        guard firstOutputSeen.insert(runID).inserted else { return }
        guard execStarted.contains(runID), let sink = sinks[runID] else { return }
        sink(.step(LaunchProgress(runID: runID, step: .cliExec, status: .done, at: configuration.clock())))
        sink(.firstOutput(runID: runID))
    }

    public func hasSeenFirstOutput(runID: UUID) -> Bool { firstOutputSeen.contains(runID) }

    /// Cancela um lançamento em andamento (Cancel da ignição): aborta etapas pendentes e mata a sessão já criada.
    public func cancel(terminalID: UUID) async {
        cancelled.insert(terminalID)
        if let session = sessions[terminalID] { await daemon.kill(sessionID: session) }
    }

    /// Fim do ciclo de vida de uma execução (exit, restart, fechar): solta sinks e a captura de ID.
    public func finish(runID: UUID) {
        sinks[runID] = nil
        running[runID]?.cancel()
        running[runID] = nil
        firstOutputSeen.remove(runID)
        execStarted.remove(runID)
    }

    private func startCapture(
        plan: LaunchPlan, runID: UUID, spawnedAt: Date, openCodeBefore: [OpenCodeSession], executable: String,
        onEvent: @escaping @Sendable (LaunchEvent) -> Void
    ) {
        let capturer = configuration.capturer
        let codexRoot = configuration.codexRoot
        let environment = plan.environment
        let task: Task<Void, Never>?
        switch plan.capture {
        case .codexRollout(let cwd):
            task = Task {
                if let id = await capturer.captureCodex(root: codexRoot, cwd: cwd, spawnedAt: spawnedAt), !Task.isCancelled {
                    onEvent(.nativeID(runID: runID, id: id))
                }
            }
        case .openCodeSessionList(let cwd):
            task = Task {
                if let id = await capturer.captureOpenCode(before: openCodeBefore, executable: executable, environment: environment, cwd: cwd), !Task.isCancelled {
                    onEvent(.nativeID(runID: runID, id: id))
                }
            }
        case .assigned(let id):
            // Claude: o ID já está no argv e no banco; o evento serve para a UI e os testes confirmarem.
            onEvent(.nativeID(runID: runID, id: id))
            task = nil
        case .none:
            task = nil
        }
        if let task { running[runID] = task }
    }
}

/// `LaunchDaemonGateway` sobre o `PTYClient` real. `ensureConnected` sobe/aguarda o daemon (o app o inicia como filho).
public struct PTYLaunchGateway: LaunchDaemonGateway {
    public let client: PTYClient
    public let ensureConnected: @Sendable () async -> Bool

    public init(client: PTYClient, ensureConnected: @escaping @Sendable () async -> Bool) {
        self.client = client
        self.ensureConnected = ensureConnected
    }

    public func connect() async -> Bool { await ensureConnected() }

    public func create(_ request: CreateRequest) async throws -> SessionSummary {
        try await client.create(request).session
    }

    public func kill(sessionID: SessionID) async {
        try? await client.kill(sessionID: sessionID, mode: .graceful)
    }
}

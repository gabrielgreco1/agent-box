import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AppKit
import Darwin
import Foundation

/// Erros de lançamento mostrados no estado "Couldn't start" do pane (03 §4.6).
enum TerminalRuntimeError: Error, Equatable {
    case daemonUnavailable
    case cliNotFound(String)
    case plan(String)
}

extension TerminalRuntimeError: LocalizedError {
    var errorDescription: String? {
        // Sempre consultado no main (o modelo do workspace); `Bundle.module` é isolado ao MainActor neste alvo.
        MainActor.assumeIsolated {
            switch self {
            case .daemonUnavailable: String(localized: "The background service isn't running.", bundle: .module)
            case .cliNotFound(let name): String(localized: "\(name) isn't installed or isn't on your PATH.", bundle: .module)
            case .plan(let detail): detail
            }
        }
    }
}

/// Resultado de lançar um terminal no daemon (T1-14): o plano usado e a sessão criada.
struct LaunchOutcome {
    var plan: LaunchPlan
    var summary: SessionSummary
}

/// Resultado de religar um terminal que já tinha sessão no daemon (reabrir o app).
enum ReattachOutcome {
    case attached(SessionSummary)
    case exited(SessionSummary)
    case gone
}

/// Um pane de terminal no processo do app: a view (`TerminalHostView`) e, depois do lançamento, a ligação com o daemon.
/// A view vive enquanto o terminal existe, também com a tab ou a sessão fora da tela (trocar de tab nunca recria o PTY).
@MainActor
final class TerminalEntry {
    let terminalID: UUID
    let host: TerminalHostView
    private(set) var binding: TerminalSessionBinding?
    private(set) var sessionID: SessionID?
    /// Tamanho do PTY já aplicado por bindings anteriores deste pane (restart cria outro binding).
    private(set) var retiredResizes = 0

    init(terminalID: UUID, host: TerminalHostView) {
        self.terminalID = terminalID
        self.host = host
    }

    var isAttached: Bool { binding != nil }
    var resizeCount: Int { retiredResizes + (binding?.appliedResizeCount ?? 0) }

    func bind(_ binding: TerminalSessionBinding, session: SessionID) {
        self.binding = binding
        sessionID = session
    }

    func unbind() {
        if let binding {
            retiredResizes += binding.appliedResizeCount
            binding.stop()
        }
        binding = nil
        sessionID = nil
    }
}

/// Serviços de terminal do app (T1-14): conexão com o `agentboxd` (o app o inicia como filho se ainda não houver um),
/// views por terminal, lançamento (`LaunchPlanner`) e religação. Nada aqui escreve no PTY por conta própria (T11).
@MainActor
final class TerminalRuntime {
    struct Configuration {
        var daemonHome: URL
        var daemonExecutable: URL?
        /// Encerra o daemon filho ao sair (testes e automação); o produto o deixa vivo para manter os agentes (P4).
        var stopDaemonOnQuit: Bool
        var appSocketPath: String
        var appVersion = "0.1.0"
        var build = "1.0 (dev)"
        /// Env do shell de login. Padrão: captura única com cache.
        var loginEnvironment: @Sendable () async -> [String: String]
    }

    enum Connection: Equatable { case idle, connecting, connected, unavailable }

    let configuration: Configuration
    let client: PTYClient
    private let daemon: ChildDaemon
    private(set) var connection: Connection = .idle
    private var connecting: Task<Bool, Never>?
    private var entries: [UUID: TerminalEntry] = [:]
    private(set) var retiredResizes = 0
    private let log = LogFacade(.app, category: "terminal-runtime")
    private weak var registry: ActionRegistry?
    private weak var elements: UIElementStore?

    /// Eventos de cada terminal (título, cwd, saída do processo...), entregues no main.
    var onEvent: ((UUID, EventPayload) -> Void)?
    /// Pedido de foco vindo de um clique no terminal.
    var onFocusRequested: ((UUID) -> Void)?
    /// Menu de contexto de um pane (03 §4.5), montado por quem conhece as ações.
    var contextMenu: ((UUID) -> NSMenu?)?
    var onConnectionChange: ((Connection) -> Void)?

    init(configuration: Configuration, registry: ActionRegistry?, elements: UIElementStore?) {
        self.configuration = configuration
        self.registry = registry
        self.elements = elements
        daemon = ChildDaemon(home: configuration.daemonHome)
        client = PTYClient(
            configuration: PTYClientConfiguration(socketPath: daemon.socketPath, build: configuration.build))
    }

    var socketPath: String { daemon.socketPath }
    var daemonPID: Int32 { daemon.pid }

    /// Soma de resizes de PTY enviados ao daemon por todos os panes (04 MA6).
    var totalResizes: Int { retiredResizes + entries.values.reduce(0) { $0 + $1.resizeCount } }

    // MARK: Conexão

    /// Conecta ao daemon; se não houver um no socket, o app sobe o seu como filho e espera até 5 s.
    @discardableResult
    func connect() async -> Bool {
        if connection == .connected { return true }
        if let connecting { return await connecting.value }
        let task = Task { [self] in await establish() }
        connecting = task
        let ok = await task.value
        connecting = nil
        return ok
    }

    private func setConnection(_ value: Connection) {
        guard connection != value else { return }
        connection = value
        onConnectionChange?(value)
    }

    private func establish() async -> Bool {
        setConnection(.connecting)
        if (try? await client.start()) != nil {
            setConnection(.connected)
            return true
        }
        if let exe = configuration.daemonExecutable ?? ChildDaemon.defaultExecutable() {
            do { try daemon.start(executable: exe, idleExitSeconds: 60) } catch { log.error("daemon start failed: \(error)") }
        }
        for _ in 0 ..< 100 {
            if (try? await client.start()) != nil {
                setConnection(.connected)
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        setConnection(.unavailable)
        return false
    }

    /// Para o daemon filho se a configuração pede (testes, automação, `AGENTBOX_STOP_DAEMON_ON_QUIT=1`).
    func shutdown() {
        if configuration.stopDaemonOnQuit { daemon.terminate() }
    }

    // MARK: Views

    func entry(for terminalID: UUID) -> TerminalEntry {
        if let existing = entries[terminalID] { return existing }
        let host = TerminalHostView(terminalID: terminalID.uuidString, registry: registry, elements: elements)
        host.onFocusRequested = { [weak self] in self?.onFocusRequested?(terminalID) }
        host.surface.contextMenuProvider = { [weak self] in
            self?.onFocusRequested?(terminalID)
            return self?.contextMenu?(terminalID)
        }
        let entry = TerminalEntry(terminalID: terminalID, host: host)
        entries[terminalID] = entry
        return entry
    }

    func existingEntry(for terminalID: UUID) -> TerminalEntry? { entries[terminalID] }

    /// Solta a view e a ligação (o terminal foi fechado). Não mata o processo: quem fecha chama `kill` antes.
    func dispose(_ terminalID: UUID) {
        guard let entry = entries.removeValue(forKey: terminalID) else { return }
        retiredResizes += entry.resizeCount
        let session = entry.sessionID
        entry.unbind()
        entry.host.removeFromSuperview()
        if let session { Task { try? await client.forget(sessionID: session) } }
    }

    // MARK: Lançamento

    /// Lança o terminal: resolve o CLI, gera o plano, cria a sessão no daemon e anexa a view.
    func launch(_ terminal: Terminal) async throws -> LaunchOutcome {
        guard await connect() else { throw TerminalRuntimeError.daemonUnavailable }
        let entry = entry(for: terminal.id)
        let login = await configuration.loginEnvironment()
        let runID = UUID.v7()
        let adapter = ProviderAdapters.adapter(for: terminal.provider)
        var executable = terminal.launchSpec.customArgv?.first ?? ""
        if let name = adapter.executableName {
            guard let found = CLIExecutableResolver.resolve(name: name, searchPath: login["PATH"]) else {
                throw TerminalRuntimeError.cliNotFound(adapter.displayName)
            }
            executable = found
        } else if terminal.provider == .custom, !executable.contains("/") {
            executable = CLIExecutableResolver.resolve(name: executable, searchPath: login["PATH"]) ?? executable
        }
        let launchDirectory = configuration.daemonHome.appendingPathComponent("run/launch/\(runID.uuidString.lowercased())", isDirectory: true)
        let plan: LaunchPlan
        do {
            plan = try LaunchPlanner.plan(
                LaunchPlanInput(
                    spec: terminal.launchSpec, terminalID: terminal.id, runID: runID, cwd: terminal.cwd,
                    terminalAddDirs: terminal.addDirs, executablePath: executable, loginEnvironment: login,
                    launchDirectory: launchDirectory, appVersion: configuration.appVersion, appSocketPath: configuration.appSocketPath))
            try LaunchFileWriter.materialize(plan)
        } catch {
            throw TerminalRuntimeError.plan("\(error)")
        }
        let dims = entry.host.surface.terminalDimensions
        let request = CreateRequest(
            sessionID: SessionID(), argv: plan.flattenedArgv, cwd: plan.cwd, env: plan.environment,
            cols: UInt16(clamping: dims.cols), rows: UInt16(clamping: dims.rows), coldLog: terminal.coldLog,
            owner: SessionOwner(terminalID: terminal.id.uuidString.lowercased(), runID: runID.uuidString.lowercased()))
        let created = try await client.create(request)
        try await attach(entry, session: created.session.sessionID, mode: .snapshot)
        return LaunchOutcome(plan: plan, summary: created.session)
    }

    /// Religa um terminal cuja sessão o daemon manteve viva (reabrir o app).
    func reattach(_ terminal: Terminal) async -> ReattachOutcome {
        guard let raw = terminal.ptySessionID, let id = SessionID(string: raw), await connect() else { return .gone }
        guard let summary = (try? await client.list())?.first(where: { $0.sessionID == id }) else { return .gone }
        if summary.state == .exited { return .exited(summary) }
        let entry = entry(for: terminal.id)
        do {
            try await attach(entry, session: id, mode: .snapshot)
            return .attached(summary)
        } catch {
            log.error("reattach failed: \(error)")
            return .gone
        }
    }

    private func attach(_ entry: TerminalEntry, session: SessionID, mode: AttachMode) async throws {
        entry.unbind()
        let binding = TerminalSessionBinding(client: client, sessionID: session, host: entry.host)
        let terminalID = entry.terminalID
        binding.onEvent = { [weak self] event in self?.onEvent?(terminalID, event) }
        try await binding.start(mode: mode)
        entry.bind(binding, session: session)
    }

    // MARK: Processo

    func kill(_ terminal: Terminal, mode: KillMode) async {
        guard let session = Self.session(of: terminal) else { return }
        try? await client.kill(sessionID: session, mode: mode)
    }

    func sendInterrupt(_ terminal: Terminal) async {
        guard let session = Self.session(of: terminal) else { return }
        try? await client.signal(sessionID: session, signal: SIGINT, target: .group)
    }

    func summary(of terminal: Terminal) async -> SessionSummary? {
        guard let session = Self.session(of: terminal) else { return nil }
        return (try? await client.list())?.first { $0.sessionID == session }
    }

    private static func session(of terminal: Terminal) -> SessionID? { terminal.ptySessionID.flatMap { SessionID(string: $0) } }

    /// Há algo rodando que o fechamento interromperia (03 §16.1)? Agente vivo conta sempre; shell só se tiver processo filho
    /// (um shell ocioso fecha sem confirmação).
    func isBusy(_ terminal: Terminal) async -> Bool {
        guard terminal.state == .running else { return false }
        guard let summary = await summary(of: terminal), summary.state == .running else { return false }
        if terminal.provider.isAgent { return true }
        guard let pid = summary.pid else { return false }
        return ProcessTree.hasChildren(of: pid)
    }
}

/// Consulta à árvore de processos do sistema (libproc).
enum ProcessTree {
    static func hasChildren(of pid: Int32) -> Bool {
        var buffer = [Int32](repeating: 0, count: 16)
        let bytes = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
        return bytes > 0
    }
}

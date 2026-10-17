import AgentBoxCore
import AgentBoxPlatform
import AgentBoxProtocol
import AppKit
import Darwin
import Foundation
import Synchronization

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
        /// LaunchAgent do daemon (T1-24). `nil`: sempre o daemon filho (testes, automação, execução fora do `.app`).
        var backgroundAgent: BackgroundAgentHost?
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
    /// Onde o daemon roda (LaunchAgent ou filho) e, no fallback, por quê (Settings › General mostra o aviso de aprovação).
    private(set) var hostMode: DaemonHostMode = .childProcess(reason: nil)
    var onHostModeChange: ((DaemonHostMode) -> Void)?
    /// Daemon do LaunchAgent com build mais antigo que o do app: pediu `drainWhenIdle` (Diagnostics mostra "update pending").
    private(set) var daemonUpdatePending = false
    private var daemonBuild: String?
    /// A conexão com o daemon voltou depois de uma queda (o daemon pode ser outro: sessões podem ter sumido, T1-23).
    var onDaemonRecovered: (() -> Void)?
    private var monitor: Task<Void, Never>?

    init(configuration: Configuration, registry: ActionRegistry?, elements: UIElementStore?) {
        self.configuration = configuration
        self.registry = registry
        self.elements = elements
        daemon = ChildDaemon(home: configuration.daemonHome)
        client = PTYClient(
            configuration: PTYClientConfiguration(socketPath: daemon.socketPath, build: configuration.build))
    }

    var socketPath: String { daemon.socketPath }

    /// Escolhe onde o daemon roda e aponta o cliente para o socket certo (launchd ou o do filho).
    private func prepareHost() async {
        guard let host = configuration.backgroundAgent else { return }
        await apply(await host.prepare())
    }

    private func apply(_ mode: DaemonHostMode) async {
        let changed = mode != hostMode
        hostMode = mode
        let path: String
        switch mode {
        case .launchAgent(let socket): path = socket
        case .childProcess: path = daemon.socketPath
        }
        await client.updateSocketPath(path)
        if changed {
            let description = mode.isLaunchAgent ? "launch agent" : "child process (\(mode.fallbackReason?.summary ?? "chosen"))"
            log.info("daemon host: \(description)")
            onHostModeChange?(mode)
        }
    }

    /// Sem LaunchAgent aprovado o app usa o daemon filho; o botão de Settings abre os Itens de Início (nunca sozinho).
    var needsLoginItemApproval: Bool { hostMode.fallbackReason == .requiresApproval }

    func openLoginItemsSettings() { configuration.backgroundAgent?.openLoginItemsSettings() }

    /// Depois da conexão: compara os builds e, se o daemon do LaunchAgent for mais antigo, pede `drainWhenIdle` (06 §1.10).
    private func checkDaemonUpgrade(build: String?) async {
        guard hostMode.isLaunchAgent, let build else { return }
        daemonBuild = build
        guard DaemonUpgradePolicy.decide(appBuild: configuration.build, daemonBuild: build) == .drainWhenIdle else { return }
        guard !daemonUpdatePending else { return }
        daemonUpdatePending = (try? await client.drainWhenIdle()) != nil
    }
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

    /// Diretório do cold log (`<home>/sessions/<ptySessionID>/`, 06 §1.5).
    var coldLogReader: ColdLogReader {
        ColdLogReader(sessionsDirectory: configuration.daemonHome.appendingPathComponent("sessions", isDirectory: true))
    }

    /// Pergunta ao daemon o que ele mantém vivo **sem** subir um novo (reabertura do app): `nil` = não há daemon.
    func probeDaemon() async -> [SessionSummary]? {
        guard connection != .connected else { return try? await client.list() }
        await prepareHost()
        guard (try? await client.start()) != nil else { return nil }
        setConnection(.connected)
        startMonitor()
        return try? await client.list()
    }

    /// Acompanha a conexão: depois de uma queda espera 2 s pela reconexão automática e, se o daemon não voltou, sobe outro
    /// como filho (as sessões do antigo estão perdidas; a UI as marca `interrupted` em `onDaemonRecovered`).
    private func startMonitor() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            guard let client = self?.client else { return }
            var wasConnected = false
            var lost = false
            var respawn: Task<Void, Never>?
            for await state in await client.connectionStates() {
                switch state {
                case .connected(let daemonBuild, _):
                    respawn?.cancel()
                    await self?.checkDaemonUpgrade(build: daemonBuild)
                    if lost {
                        lost = false
                        self?.setConnection(.connected)
                        self?.onDaemonRecovered?()
                    }
                    wasConnected = true
                case .disconnected:
                    guard wasConnected, !lost else { continue }
                    lost = true
                    self?.setConnection(.connecting)
                    respawn = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled else { return }
                        self?.respawnDaemon()
                    }
                case .connecting:
                    break
                }
            }
        }
    }

    private func respawnDaemon() {
        if hostMode.isLaunchAgent, let host = configuration.backgroundAgent {
            // LaunchAgent: o launchd relança o daemon na próxima conexão; antes, garante que o binário novo pode subir.
            daemonUpdatePending = false
            Task { [weak self] in
                let mode = await host.recover()
                await self?.apply(mode)
            }
            return
        }
        guard let exe = configuration.daemonExecutable ?? ChildDaemon.defaultExecutable() else { return }
        do { try daemon.start(executable: exe, idleExitSeconds: 60) } catch { log.error("daemon respawn failed: \(error)") }
    }

    private func setConnection(_ value: Connection) {
        guard connection != value else { return }
        connection = value
        onConnectionChange?(value)
    }

    private func establish() async -> Bool {
        setConnection(.connecting)
        await prepareHost()
        if hostMode.isLaunchAgent {
            // O launchd sobe o daemon na primeira conexão ao socket dele (o handshake espera até 2 s).
            for _ in 0 ..< 3 {
                if (try? await client.start()) != nil {
                    setConnection(.connected)
                    startMonitor()
                    return true
                }
            }
            log.error("launch agent did not answer; falling back to a child daemon")
            await apply(.childProcess(reason: .daemonUnreachable))
        }
        if (try? await client.start()) != nil {
            setConnection(.connected)
            startMonitor()
            return true
        }
        if let exe = configuration.daemonExecutable ?? ChildDaemon.defaultExecutable() {
            do { try daemon.start(executable: exe, idleExitSeconds: 60) } catch { log.error("daemon start failed: \(error)") }
        }
        for _ in 0 ..< 100 {
            if (try? await client.start()) != nil {
                setConnection(.connected)
                startMonitor()
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

    /// Coordenador de lançamento (T1-16): o mesmo caminho para o primeiro start, Restart e Try Again.
    private(set) lazy var coordinator: LaunchCoordinator = {
        let gateway = PTYLaunchGateway(client: client, ensureConnected: { [weak self] in await self?.connect() ?? false })
        let login = configuration.loginEnvironment
        return LaunchCoordinator(
            daemon: gateway,
            configuration: .init(
                launchRoot: configuration.daemonHome.appendingPathComponent("run/launch", isDirectory: true),
                appSocketPath: configuration.appSocketPath, appVersion: configuration.appVersion, loginEnvironment: login))
    }()

    /// Lança o terminal pelo `LaunchCoordinator`: resolve o CLI, gera o plano, cria a sessão no daemon e anexa a view.
    /// `onEvent` recebe o progresso real (qualquer thread).
    func launch(_ terminal: Terminal, mode: LaunchMode = .automatic, onEvent: @escaping @Sendable (LaunchEvent) -> Void) async throws -> LaunchResult {
        let entry = entry(for: terminal.id)
        let dims = entry.host.surface.terminalDimensions
        let job = LaunchJob(
            terminalID: terminal.id, spec: terminal.launchSpec, cwd: terminal.cwd, addDirs: terminal.addDirs, coldLog: terminal.coldLog,
            cols: UInt16(clamping: dims.cols), rows: UInt16(clamping: dims.rows), mode: mode)
        return try await coordinator.launch(
            job, onEvent: onEvent,
            attach: { [weak self] summary, runID in try await self?.attach(entry, session: summary.sessionID, mode: .snapshot, runID: runID) })
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

    /// Mostra o último scrollback do cold log no pane de um terminal sem processo (Interrupted, Exited depois de reabrir).
    /// Nunca escreve no PTY: só alimenta o emulador local. Devolve `false` se não há log.
    @discardableResult
    func showColdLog(of terminal: Terminal) -> Bool {
        guard let session = terminal.ptySessionID, let tail = coldLogReader.tail(sessionID: session) else { return false }
        let entry = entry(for: terminal.id)
        guard !entry.isAttached else { return false }
        let surface = entry.host.surface
        let feeder = surface.feedSender
        surface.setReplaying(true)
        feeder.feed(byteArray: [0x1b, 0x63][...])
        feeder.feed(byteArray: tail.bytes[...])
        feeder.feed(byteArray: Array("\r\n".utf8)[...])
        surface.setReplaying(false)
        return true
    }

    private func attach(_ entry: TerminalEntry, session: SessionID, mode: AttachMode, runID: UUID? = nil) async throws {
        entry.unbind()
        let binding = TerminalSessionBinding(client: client, sessionID: session, host: entry.host)
        let terminalID = entry.terminalID
        binding.onEvent = { [weak self] event in self?.onEvent?(terminalID, event) }
        if let runID {
            // Primeiro byte do PTY: fecha a ignição (M-504). Uma vez só; o observador roda na thread de parse.
            let coordinator = coordinator
            let fired = Mutex(false)
            binding.frameObserver.set { _ in
                guard fired.withLock({ let was = $0; $0 = true; return !was }) else { return }
                Task { await coordinator.noteFirstOutput(runID: runID) }
            }
        }
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

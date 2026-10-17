import AgentBoxCore
import AgentBoxDesignSystem
import AgentBoxProtocol
import AgentBoxStore
import AppKit
import Foundation

/// Pedido de `session.launch` (automação e testes; o composer de T1-20 monta o mesmo pedido).
struct SessionLaunchRequest: Codable, Equatable {
    var provider: String?
    var prompt: String?
    var model: String?
    var name: String?
    var cwd: String?
    var args: [String]?
    /// `provider: custom`: comando livre (argv sem interpolação). Para testes e evidência com CLI falso.
    var argv: [String]?
    /// Origem do chip (centro do botão "Create Session"), em pontos da janela com y do topo. Padrão: base da janela.
    var origin: [Double]?
}

/// Cria uma sessão limpa com o agente escolhido já rodando (P9, M-501): linha pendente na sidebar, chip voando até ela,
/// tab com o terminal em ignição e, quando o terminal existe, o card pronto no lugar da linha pendente. O lançamento em si
/// é do `LaunchCoordinator` (via `WorkspaceModel`); aqui só orquestra a UI em volta dele.
@MainActor
final class SessionLauncher {
    private let sidebar: SidebarModel
    private let workspace: WorkspaceModel
    private let elements: UIElementStore
    private let sessionsRoot: URL
    private var store: AgentBoxStore?
    /// Terminal -> linha pendente que acompanha o lançamento.
    private var pendingByTerminal: [UUID: UUID] = [:]
    private var pendingStart: [UUID: Date] = [:]
    private var agentNames: [UUID: String] = [:]
    /// Tempo mínimo da linha pendente (o chip precisa pousar nela, M-501).
    static let minimumPendingDuration: TimeInterval = 0.62

    init(sidebar: SidebarModel, workspace: WorkspaceModel, elements: UIElementStore, sessionsRoot: URL) {
        self.sidebar = sidebar
        self.workspace = workspace
        self.elements = elements
        self.sessionsRoot = sessionsRoot
        workspace.onLaunchEvent = { [weak self] terminalID, event in self?.follow(event, terminalID: terminalID) }
    }

    func attach(store: AgentBoxStore) { self.store = store }

    func register(in registry: ActionRegistry) throws {
        try registry.register(.sessionLaunch) { [unowned self] arg in
            guard arg.kind == .set, let raw = arg.value, let data = raw.data(using: .utf8),
                  let request = try? JSONDecoder().decode(SessionLaunchRequest.self, from: data) else {
                throw ActionError.failed(.sessionLaunch, message: "expected set(<json>) with provider, prompt, model, name, cwd, args, argv")
            }
            return try await launch(request)
        }
    }

    /// Devolve um JSON com `sessionID`, `tabID` e `terminalID`.
    func launch(_ request: SessionLaunchRequest) async throws -> String {
        guard let store else { throw ActionError.failed(.sessionLaunch, message: "The store isn't open yet") }
        let provider = TerminalProvider(rawValue: request.provider ?? "claude") ?? .claude
        let prompt = request.prompt.flatMap { $0.isEmpty ? nil : $0 }
        let title = Self.title(name: request.name, prompt: prompt, provider: provider)
        let sessionID = UUID.v7(), tabID = UUID.v7(), terminalID = UUID.v7(), pendingID = UUID.v7()
        let folder: URL
        if let cwd = request.cwd, !cwd.isEmpty {
            folder = URL(fileURLWithPath: cwd, isDirectory: true)
        } else {
            folder = sessionsRoot.appendingPathComponent(Self.slug(title) + "-" + String(sessionID.uuidString.prefix(4)).lowercased(), isDirectory: true)
        }
        try LaunchFolder.ensure(folder)

        // 1. Linha pendente (M-501): a sessão fica escondida da lista até o terminal existir.
        let agent = ProviderAdapters.name(provider)
        sidebar.beginPending(PendingLaunch(id: pendingID, name: title, projectID: nil, phase: .preparing, sessionID: sessionID))
        pendingByTerminal[terminalID] = pendingID
        pendingStart[pendingID] = Date()
        agentNames[pendingID] = agent
        flyChip(provider: provider, title: title, origin: request.origin, pendingID: pendingID)

        // 2. Sessão, tab e terminal no Store; o terminal é lançado quando o pane tem tamanho.
        let spec = LaunchSpec(provider: provider, model: request.model, extraArgs: request.args ?? [], customArgv: request.argv, initialPrompt: prompt)
        var session = Session(id: sessionID, kind: .clean, folderPath: folder.path, title: title)
        session.managedFolder = request.cwd == nil
        let terminal = Terminal(id: terminalID, tabID: tabID, provider: provider, title: title, cwd: folder.path, launchSpec: spec)
        let tab = Tab(id: tabID, sessionID: sessionID, title: title, layout: .leaf(Pane(content: .terminal(terminalID))), focusedTerminalID: terminalID)
        do {
            try await store.saveBundle(session: session, tabs: [tab], terminals: [terminal])
        } catch {
            sidebar.finish(pending: pendingID)
            throw ActionError.failed(.sessionLaunch, message: "\(error)")
        }
        // 3. Seleciona assim que o snapshot do Store traz a sessão; o workspace carrega as tabs e lança o terminal.
        for _ in 0 ..< 500 where !sidebar.select(sessionID) { try? await Task.sleep(for: .milliseconds(20)) }
        let payload: [String: String] = ["sessionID": sessionID.uuidString, "tabID": tabID.uuidString, "terminalID": terminalID.uuidString, "pendingID": pendingID.uuidString]
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) }
        return json ?? sessionID.uuidString
    }

    private func flyChip(provider: TerminalProvider, title: String, origin: [Double]?, pendingID: UUID) {
        guard let window = elements.window else { return }
        let bounds = window.contentView?.bounds ?? .zero
        let from: CGRect
        if let origin, origin.count == 2 {
            from = CGRect(x: origin[0], y: origin[1], width: 0, height: 0)
        } else {
            from = CGRect(x: bounds.midX, y: bounds.height - DS.Space.s10 * 2, width: 0, height: 0)
        }
        Task { @MainActor in
            // A linha pendente precisa ter sido desenhada (e registrada) para o chip saber onde pousar.
            var target: CGRect?
            for _ in 0 ..< 40 {
                target = elements.frame(of: .sidebarPending(pendingID.uuidString))
                if let target, target.width > 0 { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
            guard let target else { return }
            LaunchChipFlight.play(in: window, from: from, to: target, provider: provider, title: title)
        }
    }

    /// Eventos reais do coordenador movem a fase da linha pendente; ao criar o PTY, ela vira o card (M-501 `T_ready`).
    private func follow(_ event: LaunchEvent, terminalID: UUID) {
        guard let pendingID = pendingByTerminal[terminalID] else { return }
        guard case .step(let progress) = event else { return }
        let agent = agentNames[pendingID] ?? ""
        switch (progress.step, progress.status) {
        case (.gitFetch, .running): sidebar.advance(pending: pendingID, to: .fetching)
        case (.gitWorktree, .running): sidebar.advance(pending: pendingID, to: .creatingWorktree)
        case (.launchConfig, .running): sidebar.advance(pending: pendingID, to: .preparing)
        case (.ptySpawn, .running), (.cliExec, .running): sidebar.advance(pending: pendingID, to: .startingAgent(agent))
        case (.ptySpawn, .done): ready(pendingID, terminalID: terminalID)
        case (_, .failed): ready(pendingID, terminalID: terminalID)  // o pane mostra "Couldn't start"; a sessão existe
        default: break
        }
    }

    private func ready(_ pendingID: UUID, terminalID: UUID) {
        guard pendingStart[pendingID] != nil else { return }
        let elapsed = Date().timeIntervalSince(pendingStart[pendingID] ?? Date())
        let wait = MotionPolicy.shared.reduceMotion ? 0 : max(0, Self.minimumPendingDuration - elapsed)
        pendingStart[pendingID] = nil
        pendingByTerminal[terminalID] = nil
        Task { @MainActor in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            sidebar.finish(pending: pendingID)
            agentNames[pendingID] = nil
        }
    }

    // MARK: Nomes

    /// Com prompt, o título são as primeiras palavras como digitadas (AC-303); sem prompt, o nome do agente.
    static func title(name: String?, prompt: String?, provider: TerminalProvider) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let prompt {
            let words = prompt.split(whereSeparator: \.isWhitespace).prefix(5).joined(separator: " ")
            if !words.isEmpty { return words }
        }
        return ProviderAdapters.name(provider)
    }

    static func slug(_ title: String) -> String {
        let mapped = title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        let parts = mapped.split(separator: "-", omittingEmptySubsequences: true).prefix(5)
        return parts.isEmpty ? "session" : parts.joined(separator: "-")
    }
}

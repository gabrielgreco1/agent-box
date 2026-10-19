import AgentBoxDocker
import AgentBoxPlatform
import AgentBoxProtocol
import AgentBoxStore
import Foundation

// F12/F13: a fiação que a T3-04 deixou fora do app. Um orquestrador por app: hub, scheduler, ferramentas MCP, porta de consentimento
// (Off/Ask/Full) e o preparo das imagens. A cada lançamento de um Claude com "Subagent computers" ligado o app chama `prepareParent`,
// que gera `--mcp-config` + `--plugin-dir` + `--agents` + deny de `Skill(agentbox)` (OrchestrationInjectionBuilder) e registra as identidades.

public final class ComputerOrchestrator: Sendable {
    public let hub: ComputerHub
    public let scheduler: ComputerScheduler
    public let approvals: ComputerApprovalCenter
    public let parents: ParentDirectory
    public let tools: ComputerToolService
    public let provisioning: AppComputerProvisioning
    public let helperPath: String
    public let server: ComputerMCPServer
    private let store: AgentBoxStore?

    /// `waitSeconds`: quanto uma chamada de `boxes_reserve` espera a decisão do Ask antes de devolver `pending` (45 s no app).
    public init(
        helperPath: String, store: AgentBoxStore?, provisioning: AppComputerProvisioning, runsRoot: URL, waitSeconds: TimeInterval = 45,
        fixedEstimates: Bool? = nil, maxParallelCreations: Int = ComputerScheduler.defaultMaxParallelCreations,
        proxies: (any ProxyDirectory)? = nil
    ) {
        self.helperPath = helperPath
        self.store = store
        self.provisioning = provisioning
        let hub = ComputerHub()
        self.hub = hub
        let parents = ParentDirectory()
        self.parents = parents
        scheduler = ComputerScheduler(
            hub: hub, provisioning: provisioning, capacity: { await provisioning.vmCapacity() },
            runDirectory: { parent, name in runsRoot.appendingPathComponent("\(parent.prefix(8))/\(name)", isDirectory: true) },
            store: store, maxParallelCreations: maxParallelCreations, fixedEstimates: fixedEstimates, proxies: proxies,
            sessionProxy: { parent in await parents.info(parent)?.proxy })
        let approvals = ComputerApprovalCenter()
        self.approvals = approvals
        let scheduler = scheduler
        tools = ComputerToolService(
            hub: hub, orchestrator: scheduler,
            gate: SubagentComputersGate(
                parents: parents, approvals: approvals, waitSeconds: waitSeconds,
                effectiveProxy: { parent, requested in await scheduler.effectiveProxy(parent: parent, requested: requested) }))
        server = ComputerMCPServer(tools: tools)
        if let store {
            Task { await parents.observeProxyChanges { id, proxy in Task { try? await store.updateOrchestrationParentProxy(id: id, proxy: proxy) } } }
        }
    }

    /// Serviço `mcp` do `app.sock` (o helper `agentbox mcp` do Claude fala com ele).
    public var mcpProvider: McpServiceProvider { McpServiceProvider(server: server, hub: hub) }

    /// Liga o scheduler ao hub e o progresso das imagens às linhas dos computadores. `onProblem` recebe "Docker isn't running".
    public func start(onProblem: (@Sendable (ComputerSetupError) -> Void)? = nil) async {
        await scheduler.attach()
        let hub = hub
        await provisioning.setObserver(
            state: { state in
                Task {
                    for computer in await hub.allComputers where await computer.state == .provisioning { await computer.setDetail(state.label) }
                }
            },
            problem: onProblem)
    }

    /// Por lançamento do Claude pai (Ask ou Full): peças de injeção já registradas. Chamar de novo (Resume) gera identidades novas.
    public func prepareParent(_ info: ParentInfo, options: OrchestrationInjectionBuilder.Options = .init()) async throws -> OrchestrationBundle {
        precondition(info.mode.isOn, "prepareParent só vale com Subagent computers ligado")
        var info = info
        if info.proxy == nil, let session = info.sessionID { info.proxy = await parents.proxy(forSession: session) }
        var bundle = try OrchestrationInjectionBuilder.make(parentID: info.parentID, helperPath: helperPath, options: options)
        bundle.spawnGuardMode = info.mode
        await parents.register(info)
        // A identidade (só o hash da capability) e o que o pai sabe da sessão sobrevivem a um reinício do app (adoção).
        try? await store?.saveOrchestrationParent(OrchestrationParentRecord(
            id: info.parentID, parentRunID: UUID(uuidString: info.parentID), sessionID: info.sessionID, sessionTitle: info.sessionTitle,
            mode: info.mode.rawValue, proxy: info.proxy, capabilityHash: ComputerHub.fingerprint(bundle.parentCapability)))
        await OrchestrationInjectionBuilder.register(bundle, hub: hub, scheduler: scheduler, parentRunID: UUID(uuidString: info.parentID))
        return bundle
    }

    /// O terminal pai terminou (saiu, foi fechado ou relançado): solta o que ele reservou e os pedidos que esperavam o usuário.
    public func endParent(_ parentID: String) async {
        await approvals.cancel(parent: parentID)
        let names = await scheduler.computerNames(of: parentID)
        if !names.isEmpty { _ = await scheduler.release(parent: parentID, names: names, keep24h: false) }
        await parents.remove(parentID)
        try? await store?.deleteOrchestrationParent(id: parentID)
        await hub.unregisterChild(id: parentID)
        for child in await hub.children(of: parentID) { await hub.unregisterChild(id: child) }
    }

    /// Pais com identidade persistida mais velhos que isto não voltam (o terminal deles já terminou há muito).
    static let parentRetention: TimeInterval = 14 * 24 * 3600

    /// App reiniciado: o Claude pai e os subagentes seguiram vivos (o daemon os manteve) com as capabilities do lançamento antigo nos
    /// argumentos. Devolve ao hub e ao diretório de pais o que foi persistido, para o `agentbox mcp` deles voltar a ser aceito. Só lê o
    /// Store (rápido); chamar antes de aceitar conexões MCP.
    public func restoreIdentities() async { await Self.restoreIdentities(store: store, hub: hub, parents: parents) }

    static func restoreIdentities(store: AgentBoxStore?, hub: ComputerHub, parents: ParentDirectory) async {
        guard let store else { return }
        try? await store.pruneOrchestrationParents(olderThan: Date().addingTimeInterval(-parentRetention))
        for record in (try? await store.orchestrationParents()) ?? [] {
            guard await hub.role(of: record.id) == nil else { continue }  // já registrado neste processo
            await hub.registerParent(id: record.id, capabilityHash: record.capabilityHash)
            await parents.register(ParentInfo(
                parentID: record.id, sessionID: record.sessionID, sessionTitle: record.sessionTitle, mode: SubagentComputersMode(rawValue: record.mode) ?? .ask,
                proxy: record.proxy))
            if record.proxy != nil { await parents.setProxy(record.proxy, for: record.id) }
            for child in (try? await store.orchestrationChildren(parentID: record.id)) ?? [] {
                guard let hash = child.capabilityHash, await hub.role(of: child.id) == nil else { continue }
                await hub.registerChild(id: child.id, capabilityHash: hash, parent: record.id)
            }
        }
    }

    /// Identidades + computadores: depois de `restoreIdentities`, adota os containers que seguiram vivos (precisa do Docker de pé; sem ele
    /// não faz nada). Devolve os nomes adotados.
    @discardableResult
    public func adoptRunning() async -> [String] {
        await restoreIdentities()
        return await scheduler.adoptRunning()
    }

    /// Qual sessão do app é dona do computador (linha filha, título do Inbox).
    public func sessionID(ofComputer name: String) async -> UUID? {
        guard let parent = await scheduler.parent(of: name) else { return nil }
        return await parents.info(parent)?.sessionID
    }
}

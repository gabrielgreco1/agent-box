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

    /// `waitSeconds`: quanto uma chamada de `boxes_reserve` espera a decisão do Ask antes de devolver `pending` (45 s no app).
    public init(
        helperPath: String, store: AgentBoxStore?, provisioning: AppComputerProvisioning, runsRoot: URL, waitSeconds: TimeInterval = 45,
        fixedEstimates: Bool? = nil, maxParallelCreations: Int = ComputerScheduler.defaultMaxParallelCreations
    ) {
        self.helperPath = helperPath
        self.provisioning = provisioning
        let hub = ComputerHub()
        self.hub = hub
        scheduler = ComputerScheduler(
            hub: hub, provisioning: provisioning, capacity: { await provisioning.vmCapacity() },
            runDirectory: { parent, name in runsRoot.appendingPathComponent("\(parent.prefix(8))/\(name)", isDirectory: true) },
            store: store, maxParallelCreations: maxParallelCreations, fixedEstimates: fixedEstimates)
        let approvals = ComputerApprovalCenter()
        self.approvals = approvals
        let parents = ParentDirectory()
        self.parents = parents
        tools = ComputerToolService(
            hub: hub, orchestrator: scheduler, gate: SubagentComputersGate(parents: parents, approvals: approvals, waitSeconds: waitSeconds))
        server = ComputerMCPServer(tools: tools)
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
        var bundle = try OrchestrationInjectionBuilder.make(parentID: info.parentID, helperPath: helperPath, options: options)
        bundle.spawnGuardMode = info.mode
        await parents.register(info)
        await OrchestrationInjectionBuilder.register(bundle, hub: hub, scheduler: scheduler, parentRunID: UUID(uuidString: info.parentID))
        return bundle
    }

    /// O terminal pai terminou (saiu, foi fechado ou relançado): solta o que ele reservou e os pedidos que esperavam o usuário.
    public func endParent(_ parentID: String) async {
        await approvals.cancel(parent: parentID)
        let names = await scheduler.computerNames(of: parentID)
        if !names.isEmpty { _ = await scheduler.release(parent: parentID, names: names, keep24h: false) }
        await parents.remove(parentID)
        await hub.unregisterChild(id: parentID)
        for child in await hub.children(of: parentID) { await hub.unregisterChild(id: child) }
    }

    /// Qual sessão do app é dona do computador (linha filha, título do Inbox).
    public func sessionID(ofComputer name: String) async -> UUID? {
        guard let parent = await scheduler.parent(of: name) else { return nil }
        return await parents.info(parent)?.sessionID
    }
}

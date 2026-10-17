import Foundation

/// Ciclo de vida que o app injeta (T3-04): o que fazer quando o filho libera o computador (coletar, remover containers).
public protocol ComputerLifecycle: Sendable {
    func finish(_ computer: ManagedComputer, keep24h: Bool) async
}

public enum ChildRole: Sendable, Equatable { case worker, parent }

/// Registro dos computadores e roteamento por filho (07 §3.1): a identidade vem da configuração por filho do processo MCP
/// (`agentbox mcp --child <id> --capability <token>`), e um filho só opera o computador que reivindicou com `box_claim`.
/// O nome passado como argumento é dica, não autorização. `agent_id` dos hooks é só correlação.
public actor ComputerHub {
    private var computers: [String: ManagedComputer] = [:]
    private var claims: [String: String] = [:]  // filho -> nome do computador
    private var released: Set<String> = []
    private var identities: [String: String] = [:]  // filho -> capability de lançamento
    private var roles: [String: ChildRole] = [:]
    private var parents: [String: String] = [:]  // filho -> pai que o criou (slot de worker, T3-04)
    private var childOrder: [String: [String]] = [:]  // pai -> filhos por ordem de slot
    private var lifecycle: (any ComputerLifecycle)?

    public init(lifecycle: (any ComputerLifecycle)? = nil) { self.lifecycle = lifecycle }

    /// O scheduler (T3-04) é o ciclo de vida e precisa do hub: liga depois de criar os dois.
    public func setLifecycle(_ lifecycle: (any ComputerLifecycle)?) { self.lifecycle = lifecycle }

    // MARK: Identidade

    /// Registra um filho (o app faz isso no lançamento, ao montar o `mcpServers` inline do subagente). Com `parent`, o filho é um
    /// slot de worker do pai (T3-04): só esse pai pode reservar computador para ele e lhe mandar `agent_message`.
    public func registerChild(id: String, capability: String, parent: String? = nil) {
        identities[id] = capability
        roles[id] = .worker
        released.remove(id)
        if let parent {
            parents[id] = parent
            var list = childOrder[parent, default: []]
            if !list.contains(id) { list.append(id) }
            childOrder[parent] = list
        }
    }

    /// Registra o terminal pai (identidade do `--mcp-config` do lançamento do pai). Ele só enxerga as ferramentas de orquestração.
    public func registerParent(id: String, capability: String) {
        identities[id] = capability
        roles[id] = .parent
    }

    public func unregisterChild(id: String) {
        identities[id] = nil; claims[id] = nil; roles[id] = nil
        if let parent = parents[id] { childOrder[parent]?.removeAll { $0 == id } }
        parents[id] = nil
    }

    public func role(of id: String) -> ChildRole? { roles[id] }
    public func parent(of child: String) -> String? { parents[child] }
    /// Filhos (slots de worker) do pai, por ordem de registro.
    public func children(of parent: String) -> [String] { childOrder[parent] ?? [] }
    /// O nome do computador que o filho reivindicou.
    public func claimedComputer(of child: String) -> String? { claims[child] }

    /// `child` + `capability` precisam bater com o registrado no lançamento. A capability não aparece em schema nenhum.
    public func authorize(child: String, capability: String) -> Bool {
        guard let expected = identities[child] else { return false }
        return expected.utf8.count == capability.utf8.count && zip(expected.utf8, capability.utf8).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    // MARK: Computadores

    public func register(_ computer: ManagedComputer) { computers[computer.name] = computer }

    public func remove(name: String) {
        computers[name] = nil
        for (child, box) in claims where box == name { claims[child] = nil; released.insert(child) }  // o filho passa a receber `box_released`
    }

    public func computer(named name: String) -> ManagedComputer? { computers[name] }
    public var allComputers: [ManagedComputer] { Array(computers.values) }

    // MARK: Roteamento

    func claim(name: String, child: String) async throws -> ManagedComputer {
        guard let computer = computers[name] else { throw ToolError(.notFound, "no computer named \(name)") }
        if let current = claims[child], current != name {
            throw ToolError(.alreadyClaimed, "you already hold computer \(current); release it first", details: ["owner": .string(child), "box": .string(current)])
        }
        try await computer.claim(by: child)
        claims[child] = name
        released.remove(child)
        return computer
    }

    /// O computador do filho. Antes do claim: `not_claimed`. Depois do release: `box_released`.
    func computer(for child: String) throws -> ManagedComputer {
        if let name = claims[child], let computer = computers[name] { return computer }
        if released.contains(child) { throw ToolError(.boxReleased, "you released your computer; claim again to continue") }
        throw ToolError(.notClaimed, "call box_claim first; each child works on the computer it claimed")
    }

    func release(child: String, keep24h: Bool) async throws {
        let computer = try computer(for: child)
        claims[child] = nil
        released.insert(child)
        await computer.release()
        ComputerToolService.writeTimelineFile(computer)  // `logs/timeline.md` ao coletar (CS-261, CS-180)
        await computer.emit(.released(computer: computer.name))
        await lifecycle?.finish(computer, keep24h: keep24h)
    }
}

import AgentBoxDocker
import AgentBoxPlatform
import AgentBoxStore
import Foundation

// T3-04, 07 §2.4 (capacidade e fila: CS-130, CS-131), §4.2 (CS-301, CS-302), §4.3. O pai reserva computadores; o scheduler os admite pela
// memória da VM (soma das estimativas <= M - 2 GiB), cria até 4 por vez, põe o resto numa fila FIFO com posição visível e libera a vaga
// quando um computador termina.

/// Pedido de `boxes_reserve` (07 §4.2).
public struct ReserveRequest: Sendable, Equatable {
    public var names: [String]
    public var display: ComputerDisplay
    public var profile: String?
    public var proxy: String?
    public var proxiesAllowed: [String]
    public var batch: String?
    public var keep24h: Bool
    public var allowHosts: [String]

    public init(
        names: [String], display: ComputerDisplay = .headless, profile: String? = nil, proxy: String? = nil, proxiesAllowed: [String] = [],
        batch: String? = nil, keep24h: Bool = false, allowHosts: [String] = []
    ) {
        self.names = names; self.display = display; self.profile = profile; self.proxy = proxy; self.proxiesAllowed = proxiesAllowed
        self.batch = batch; self.keep24h = keep24h; self.allowHosts = allowHosts
    }
}

/// O que o provisionador precisa para subir um computador.
public struct ComputerSpec: Sendable {
    public var name: String
    public var parent: String
    public var display: ComputerDisplay
    public var profile: String?
    public var proxy: String
    public var proxiesAllowed: [String]
    public var allowHosts: [String]
    public var batch: String?
    public var run: RunFolder
}

/// Computador com containers de pé: o backend das ferramentas e o desmonte (`keep24h` não chega aqui: o scheduler decide quando).
public struct ProvisionedHandle: Sendable {
    public var backend: any ComputerBackend
    public var teardown: @Sendable () async -> Void
    public init(backend: any ComputerBackend, teardown: @escaping @Sendable () async -> Void) { self.backend = backend; self.teardown = teardown }
}

/// Fábrica de computadores. A real é `DockerComputerProvisioning`; os testes de unidade usam uma falsa.
public protocol ComputerProvisioning: Sendable {
    /// Falha rápido (sem Docker) para o pai receber `unavailable` + `docker_unavailable` em vez de um computador que nunca sobe.
    func preflight() async throws
    func provision(_ spec: ComputerSpec) async throws -> ProvisionedHandle
}

extension ComputerProvisioning {
    public func preflight() async throws {}
}

/// F29: de onde o scheduler sabe quais proxies existem e qual é o padrão global (Settings). `nil` no scheduler = sem proxies (tudo `direct`).
public protocol ProxyDirectory: Sendable {
    /// Nomes dos `ProxyProfile` salvos.
    func names() async -> [String]
    /// Nome do proxy padrão global (`nil` = `direct`).
    func globalDefault() async -> String?
}

public struct StoreProxyDirectory: ProxyDirectory {
    public let store: AgentBoxStore
    public init(store: AgentBoxStore) { self.store = store }
    public func names() async -> [String] { ((try? await store.proxies()) ?? []).map(\.name) }
    public func globalDefault() async -> String? { try? await store.defaultProxy()?.name }
}

/// Ferramentas do pai (`boxes_reserve`, `boxes_status`, `boxes_release`, `agent_message`). `parent` é a identidade MCP autenticada.
public protocol ParentOrchestrating: Sendable {
    func reserve(parent: String, _ request: ReserveRequest) async -> JSON
    func status(parent: String, names: [String]?, batch: String?) async -> JSON
    func release(parent: String, names: [String], keep24h: Bool) async -> JSON
    func message(parent: String, to child: String, text: String) async throws -> JSON
    /// Mensagens do pai ainda não entregues a este filho (saem em `box_status` como `parent_messages`).
    func drainParentMessages(for child: String) async -> [JSON]
}

public actor ComputerScheduler: ComputerLifecycle, ParentOrchestrating {
    public enum Phase: String, Sendable { case queued, creating, active, failed }

    struct Entry {
        var spec: ComputerSpec
        var id: UUID
        var computer: ManagedComputer
        var lazy: LazyComputerBackend
        var childID: String
        var phase: Phase
        var requestedAt: Date
        var handle: ProvisionedHandle?
        var warnedUnclaimed = false
        var keepUntil: Date?
        var failure: String?
        var startedAt: Date?
    }

    public static let defaultMaxParallelCreations = 4
    public static let unclaimedWarningAfter: TimeInterval = 10 * 60
    public static let unclaimedReleaseAfter: TimeInterval = 30 * 60
    public static let keepDuration: TimeInterval = 24 * 3600

    public let hub: ComputerHub
    private let provisioning: any ComputerProvisioning
    private let capacity: @Sendable () async -> VMCapacity
    private let runDirectory: @Sendable (_ parent: String, _ name: String) -> URL
    private let store: AgentBoxStore?
    private let proxies: (any ProxyDirectory)?
    /// Proxy padrão da sessão do pai (escolhido no card de aprovação); `nil` = usar o padrão global.
    private let sessionProxy: @Sendable (_ parent: String) async -> String?
    private let now: @Sendable () -> Date
    private let log = LogFacade(.app, category: "scheduler")
    private var tracker: EstimateTracker

    private var entries: [String: Entry] = [:]
    private var queue: [String] = []
    private var creating = 0
    private var permits: Int
    private var permitWaiters: [CheckedContinuation<Void, Never>] = []
    private var agentToChild: [String: String] = [:]
    private var loggedMessages: Set<String> = []
    private var pendingMessages: [String: [StoredAgentMessage]] = [:]  // sem store (testes): inbox em memória

    public init(
        hub: ComputerHub, provisioning: any ComputerProvisioning, capacity: @escaping @Sendable () async -> VMCapacity,
        runDirectory: @escaping @Sendable (_ parent: String, _ name: String) -> URL, store: AgentBoxStore? = nil,
        maxParallelCreations: Int = ComputerScheduler.defaultMaxParallelCreations, fixedEstimates: Bool? = nil,
        proxies: (any ProxyDirectory)? = nil, sessionProxy: @escaping @Sendable (_ parent: String) async -> String? = { _ in nil },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.proxies = proxies; self.sessionProxy = sessionProxy
        self.hub = hub; self.provisioning = provisioning; self.capacity = capacity; self.runDirectory = runDirectory; self.store = store
        self.permits = max(1, maxParallelCreations); self.now = now
        // Nos testes (`AGENTBOX_CAPACITY_ESTIMATES=fixed`) a tabela inicial fica fixa para os aceites serem determinísticos (CS-130).
        let fixed = fixedEstimates ?? (ProcessInfo.processInfo.environment["AGENTBOX_CAPACITY_ESTIMATES"] == "fixed")
        tracker = EstimateTracker(fixed: fixed)
    }

    /// Liga o scheduler ao hub como ciclo de vida: `box_release` do filho passa a desmontar o computador e devolver a vaga.
    public func attach() async { await hub.setLifecycle(self) }

    // MARK: Lançamento do pai

    /// Registra os slots de worker de um pai: cada slot é uma identidade MCP (`agentbox mcp --child <id> --capability <cap>`) que o filho
    /// nativo usa; só o pai dono pode lhe reservar computador e mandar mensagem (P12).
    public func registerWorkers(parent: String, parentRunID: UUID? = nil, workers: [WorkerSlot]) async {
        for worker in workers {
            await hub.registerChild(id: worker.childID, capability: worker.capability, parent: parent)
            try? await store?.registerOrchestrationChild(OrchestrationChild(
                id: worker.childID, parentID: parent, parentRunID: parentRunID, slot: worker.slot, agentType: worker.agentType))
        }
    }

    // MARK: Reserva

    nonisolated static func validName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100, let first = name.unicodeScalars.first, CharacterSet.alphanumerics.contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) }
    }

    public func reserve(parent: String, _ request: ReserveRequest) async -> JSON {
        var preflightError: String?
        do { try await provisioning.preflight() } catch { preflightError = "\(error)" }
        var results: [JSON] = []
        for name in request.names {
            results.append(await reserveOne(parent: parent, name: name, request, preflightError: preflightError))
        }
        await drain()
        // O estado devolvido reflete a admissão já feita (provisioning ou queued com posição).
        var refreshed: [JSON] = []
        for entry in results {
            if let name = entry["name"]?.string, entry["state"]?.string != "unavailable", let e = entries[name] { refreshed.append(await boxJSON(e, base: entry.object ?? [:])) }
            else { refreshed.append(entry) }
        }
        results = refreshed
        var out: [String: JSON] = ["boxes": .array(results)]
        if let batch = request.batch { out["batch_id"] = .string(batch) }
        return .object(out)
    }

    struct ProxyChoiceError: Error { var message: String }

    /// F29: `proxy` do `boxes_reserve` (nome de um ProxyProfile) > padrão da sessão (card de aprovação) > padrão global (Settings) > `direct`.
    func resolveProxy(parent: String, requested: String?) async -> Result<String, ProxyChoiceError> {
        func isDirect(_ n: String) -> Bool { n.isEmpty || n.lowercased() == "direct" || n.lowercased() == "none" }
        let known = await proxies?.names() ?? []
        if let requested, !requested.isEmpty {
            if isDirect(requested) { return .success("direct") }
            if let match = known.first(where: { $0 == requested }) ?? known.first(where: { $0.lowercased() == requested.lowercased() }) { return .success(match) }
            let list = known.isEmpty ? "none are configured (Settings > Computers > Proxies)" : known.sorted().joined(separator: ", ")
            return .failure(ProxyChoiceError(message: "unknown proxy \(requested); available: \(list). Omit `proxy` to use the user's default."))
        }
        if let chosen = await sessionProxy(parent), !isDirect(chosen) { return .success(chosen) }
        if let global = await proxies?.globalDefault(), !isDirect(global) { return .success(global) }
        return .success("direct")
    }

    /// O proxy que uma reserva sem `proxy` receberia (o card de aprovação mostra isto).
    public func effectiveProxy(parent: String, requested: String?) async -> String {
        if case .success(let name) = await resolveProxy(parent: parent, requested: requested) { return name }
        return requested ?? "direct"
    }

    private func unavailable(_ name: String, _ reason: String, _ message: String) -> JSON {
        ["name": .string(name), "state": "unavailable", "reason": .string(reason), "message": .string(message)]
    }

    private func reserveOne(parent: String, name: String, _ request: ReserveRequest, preflightError: String?) async -> JSON {
        guard Self.validName(name) else { return unavailable(name, "invalid_name", "computer names use letters, digits, '.', '_' and '-' (max 100)") }
        if let existing = entries[name] {
            guard existing.spec.parent == parent else { return unavailable(name, "name_in_use", "another orchestrator already owns a computer named \(name)") }
            if existing.phase != .failed { return await boxJSON(existing, base: [:]) }  // idempotente pelo nome (CS-116, CS-301)
            await discard(name)  // falhou antes: reservar de novo tenta outra vez
        }
        if let preflightError { return unavailable(name, "docker_unavailable", preflightError) }
        if let profile = request.profile, entries.values.contains(where: { $0.spec.profile == profile && $0.phase != .failed }) {
            return unavailable(name, "profile_busy", "browser profile \(profile) is in use by another computer")
        }
        let proxy: String
        switch await resolveProxy(parent: parent, requested: request.proxy) {
        case .success(let name): proxy = name
        case .failure(let failure): return unavailable(name, "unknown_proxy", failure.message)
        }
        let children = await hub.children(of: parent)
        let spec0 = ComputerSpec(
            name: name, parent: parent, display: request.display, profile: request.profile, proxy: proxy,
            proxiesAllowed: request.proxiesAllowed, allowHosts: request.allowHosts, batch: request.batch,
            run: RunFolder(root: runDirectory(parent, name)))
        let lazy = LazyComputerBackend()
        let computer: ManagedComputer
        do {
            computer = try ManagedComputer(
                name: name, display: request.display, run: spec0.run, backend: lazy, state: .queued, proxy: spec0.proxy,
                proxiesAllowed: request.proxiesAllowed, profile: request.profile)
        } catch {
            return unavailable(name, "docker_unavailable", "could not create the run folder: \(error.localizedDescription)")
        }
        // Daqui até inserir a entrada não há `await`: chamadas concorrentes (o scheduler reentra a cada suspensão) nunca pegam o mesmo
        // slot nem o mesmo nome.
        if let raced = entries[name] {
            guard raced.spec.parent == parent else { return unavailable(name, "name_in_use", "another orchestrator already owns a computer named \(name)") }
            return await boxJSON(raced, base: [:])
        }
        if let profile = request.profile, entries.values.contains(where: { $0.spec.profile == profile && $0.phase != .failed }) {
            return unavailable(name, "profile_busy", "browser profile \(profile) is in use by another computer")
        }
        let used = Set(entries.values.filter { $0.spec.parent == parent && $0.phase != .failed }.map(\.childID))
        guard let childID = children.first(where: { !used.contains($0) }) else {
            return unavailable(name, "no_free_worker", "all \(children.count) worker slots of this session hold a computer; release one first")
        }
        var entry = Entry(spec: spec0, id: UUID(), computer: computer, lazy: lazy, childID: childID, phase: .queued, requestedAt: now())
        if request.keep24h { entry.keepUntil = .distantFuture }  // marcado; a data real nasce no release
        entries[name] = entry
        queue.append(name)
        await hub.register(computer)
        try? await store?.updateOrchestrationChild(id: childID, state: .reserved, computerName: .some(name), batchID: .some(request.batch), at: now())
        await persist(name)
        return await boxJSON(entry, base: [:])
    }

    // MARK: Admissão e fila

    private func activeDisplays() -> [ComputerDisplay] {
        entries.values.filter { $0.phase == .creating || $0.phase == .active }.map(\.spec.display)
    }

    /// Admite da frente da fila enquanto couber (FIFO estrito: um pedido grande à frente segura os menores atrás).
    private func drain() async {
        let vm = await capacity()
        let planner = CapacityPlanner(vm: vm, estimatesGiB: tracker.estimatesGiB)
        while let head = queue.first, var entry = entries[head] {
            let active = activeDisplays()
            // VM menor que um computador: sem isto o primeiro pedido esperaria para sempre. Com a VM vazia ele entra (melhor esforço).
            let admit = active.isEmpty || planner.admission(active: active, adding: entry.spec.display) == .admit
            guard admit else { break }
            queue.removeFirst()
            entry.phase = .creating
            entry.startedAt = now()
            entries[head] = entry
            await entry.computer.setState(.provisioning)
            await persist(head)
            Task { await self.create(head) }
        }
        for (index, name) in queue.enumerated() {
            await entries[name]?.computer.setState(.queued, position: index + 1)
        }
        await persistQueue()
    }

    private func acquirePermit() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { permitWaiters.append($0) }
    }

    private func releasePermit() {
        if !permitWaiters.isEmpty { permitWaiters.removeFirst().resume() } else { permits += 1 }
    }

    private func create(_ name: String) async {
        await acquirePermit()
        defer { releasePermit() }
        guard let entry = entries[name], entry.phase == .creating else { return }
        do {
            let handle = try await provisioning.provision(entry.spec)
            guard var current = entries[name], current.phase == .creating else {
                await handle.teardown()  // liberado enquanto subia
                return
            }
            current.handle = handle
            current.phase = .active
            entries[name] = current
            current.lazy.attach(handle.backend)
            await current.computer.setState(.ready)
            await persist(name)
        } catch {
            log.error("computer \(name) failed to start: \(error)")
            guard var current = entries[name] else { return }
            current.phase = .failed
            current.failure = Self.describe(error)
            entries[name] = current
            await current.computer.setState(.failed)
            await current.computer.setDetail(String(Self.describe(error).prefix(240)))
            await persist(name)
            await drain()  // a vaga volta para a fila
        }
    }

    // MARK: Árvore: hooks dos filhos nativos (S-08)

    /// A primeira chamada de ferramenta de um filho revela `agent_id` + nome do servidor MCP (`abx-<child>`); o `SubagentStop` o encerra.
    /// Liga o slot ao `agent_run` do filho nativo (que o redutor já criou) e persiste.
    public func handleChildHook(parentRunID: UUID, event: String, agentID: String, mcpServer: String?) async {
        let prefix = "abx-"
        if let mcpServer, mcpServer.hasPrefix(prefix) {
            let childID = String(mcpServer.dropFirst(prefix.count))
            guard await hub.role(of: childID) == .worker else { return }
            let runID = ActivityProjector.childRunID(parent: parentRunID, agentID: agentID)
            try? await store?.linkOrchestrationChild(id: childID, runID: runID, providerAgentID: agentID)
            agentToChild[agentID] = childID
        }
        if event == "SubagentStop", let childID = agentToChild[agentID] {
            try? await store?.updateOrchestrationChild(id: childID, state: .ended, at: now())
        }
    }

    // MARK: Fim de vida

    /// `ComputerLifecycle`: o filho liberou (`box_release`). Coleta já foi gerada pelo hub; aqui sai o desmonte e a vaga volta.
    public func finish(_ computer: ManagedComputer, keep24h: Bool) async {
        guard var entry = entries[computer.name] else { return }
        if keep24h || entry.keepUntil == .distantFuture {
            entry.keepUntil = now().addingTimeInterval(Self.keepDuration)
            entries[computer.name] = entry
            try? await store?.updateOrchestrationChild(id: entry.childID, state: .released, at: now())
            await persist(computer.name)
            return
        }
        await discard(computer.name, childState: .released)
        await drain()
    }

    private func discard(_ name: String, childState: OrchestrationChildState = .idle) async {
        guard let entry = entries.removeValue(forKey: name) else { return }
        queue.removeAll { $0 == name }
        entry.lazy.detach()
        await entry.computer.setState(.stopped)
        await hub.remove(name: name)
        if let handle = entry.handle { await handle.teardown() }
        try? await store?.updateOrchestrationChild(id: entry.childID, state: childState, at: now())  // o slot livre é decidido pelas entradas em memória
        var row = ComputerStateRow(id: entry.id, name: name, display: entry.spec.display.rawValue, state: "removed", ownerParentID: entry.spec.parent)
        row.createdAt = entry.requestedAt
        try? await store?.saveComputerState(row)
        await persistQueue()
    }

    /// Computadores reservados e nunca reivindicados: aviso em 10 min, liberação em 30 (CS-302). Computadores mantidos por 24 h
    /// expiram aqui também. O app chama periodicamente.
    @discardableResult
    public func sweep(at date: Date? = nil) async -> (warned: [String], released: [String]) {
        let moment = date ?? now()
        var warned: [String] = [], released: [String] = []
        for name in entries.keys.sorted() {
            guard var entry = entries[name] else { continue }
            if let keepUntil = entry.keepUntil, keepUntil != .distantFuture, moment >= keepUntil {
                await discard(name, childState: .released)
                released.append(name)
                continue
            }
            guard entry.phase == .active, entry.keepUntil == nil, await entry.computer.owner == nil else { continue }
            let age = moment.timeIntervalSince(entry.requestedAt)
            if age >= Self.unclaimedReleaseAfter {
                await discard(name, childState: .expired)
                released.append(name)
            } else if age >= Self.unclaimedWarningAfter, !entry.warnedUnclaimed {
                entry.warnedUnclaimed = true
                entries[name] = entry
                await entry.computer.emit(.unclaimed(computer: name))
                warned.append(name)
            }
        }
        if !released.isEmpty { await drain() }
        return (warned, released)
    }

    // MARK: Persistência

    private func persist(_ name: String) async {
        guard let store, let entry = entries[name] else { return }
        let state = await entry.computer.state
        try? await store.saveComputerState(ComputerStateRow(
            id: entry.id, name: name, display: entry.spec.display.rawValue, state: state.rawValue, ownerParentID: entry.spec.parent, createdAt: entry.requestedAt))
    }

    private func persistQueue() async {
        guard let store else { return }
        var rows: [ComputerQueueRow] = []
        for (index, name) in queue.enumerated() {
            if let entry = entries[name] { rows.append(ComputerQueueRow(computerID: entry.id, position: index + 1, requestedAt: entry.requestedAt)) }
        }
        try? await store.replaceComputerQueue(rows)
    }

    // MARK: Consulta

    /// A fila como o pai e a UI a veem: nome e posição (a partir de 1).
    public var queueSnapshot: [(name: String, position: Int)] { queue.enumerated().map { ($0.element, $0.offset + 1) } }
    public var activeCount: Int { entries.values.filter { $0.phase == .creating || $0.phase == .active }.count }
    public func phase(of name: String) -> Phase? { entries[name]?.phase }
    public func childID(for name: String) -> String? { entries[name]?.childID }
    /// O pai (identidade MCP do lançamento) dono do computador.
    public func parent(of name: String) -> String? { entries[name]?.spec.parent }
    /// Nomes dos computadores que o pai tem agora (qualquer fase menos `failed`).
    public func computerNames(of parent: String) -> [String] { entries.values.filter { $0.spec.parent == parent }.map(\.spec.name).sorted() }
    /// O computador do subagente nativo (`agent_id` dos hooks, ligado ao slot pelo `mcp_server.name`); `nil` se ele não tem computador.
    public func computerName(forAgent agentID: String) -> String? {
        guard let childID = agentToChild[agentID] else { return nil }
        return entries.values.first { $0.childID == childID }?.spec.name
    }

    /// Falha de criação de um computador (motivo para a linha e o pai).
    public func failureReason(of name: String) -> String? { entries[name]?.failure }

    /// `"Waiting for memory · 3 of 15 queued"` (CS-131), `nil` sem fila.
    public var queueLabel: String? {
        guard !queue.isEmpty else { return nil }
        let total = entries.values.filter { $0.phase != .failed }.count
        return "Waiting for memory · \(queue.count) of \(total) queued"
    }

    /// Cancela um pedido ainda na fila (CS-131). `false` se já saiu dela.
    @discardableResult
    public func cancelQueued(name: String) async -> Bool {
        guard queue.contains(name) else { return false }
        await discard(name, childState: .idle)
        await drain()
        return true
    }

    private func boxJSON(_ entry: Entry, base: [String: JSON]) async -> JSON {
        var out = base
        let computer = entry.computer
        out["name"] = .string(entry.spec.name)
        out["display"] = .string(entry.spec.display.rawValue)
        out["child_id"] = .string(entry.childID)
        out["worker"] = .string(Self.workerType(forChild: entry.childID))
        switch entry.phase {
        case .queued:
            out["state"] = "queued"
            out["reason"] = "memory"
            if let position = queue.firstIndex(of: entry.spec.name) { out["position"] = .int(position + 1) }
        case .creating: out["state"] = "provisioning"
        case .failed:
            out["state"] = "failed"
            if let failure = entry.failure { out["message"] = .string(String(failure.prefix(300))) }
        case .active: out["state"] = .string(await computer.state.rawValue)
        }
        return .object(out)
    }

    /// Texto legível de uma falha de criação: o do próprio erro quando ele sabe se explicar (Docker parado), senão o genérico.
    nonisolated static func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "\(error)"
    }

    /// `agentbox-worker-3` para o filho `<id>-w3` (a ordem do slot está no sufixo; ver `WorkerSlot`).
    nonisolated static func workerType(forChild childID: String) -> String {
        guard let range = childID.range(of: "-w", options: .backwards) else { return "agentbox-worker" }
        return "agentbox-worker-" + childID[range.upperBound...]
    }

    public func status(parent: String, names: [String]?, batch: String?) async -> JSON {
        var boxes: [JSON] = []
        let selected = entries.values.filter { entry in
            guard entry.spec.parent == parent else { return false }
            if let names, !names.isEmpty, !names.contains(entry.spec.name) { return false }
            if let batch, entry.spec.batch != batch { return false }
            return true
        }.sorted { $0.requestedAt == $1.requestedAt ? $0.spec.name < $1.spec.name : $0.requestedAt < $1.requestedAt }
        for entry in selected {
            let computer = entry.computer
            var item: [String: JSON] = [:]
            item["name"] = .string(entry.spec.name)
            item["display"] = .string(await computer.display.rawValue)
            item["child_id"] = .string(entry.childID)
            item["worker"] = .string(Self.workerType(forChild: entry.childID))
            item["lease"] = .string(await computer.lease.rawValue)
            item["proxy"] = .string(await computer.proxy)
            switch entry.phase {
            case .queued:
                item["state"] = "queued"; item["reason"] = "memory"
                if let position = queue.firstIndex(of: entry.spec.name) { item["position"] = .int(position + 1) }
            case .creating: item["state"] = "provisioning"
            case .failed: item["state"] = "failed"
            case .active: item["state"] = .string(await computer.state.rawValue)
            }
            if let owner = await computer.owner { item["owner"] = .string(owner) }
            if let doing = await computer.lastDoing { item["last_doing"] = .string(doing) }
            if let help = await computer.openHelpID { item["help_open"] = .string(help) }
            item["usage"] = (entry.phase == .active ? (try? await computer.backend.usage()) : nil) ?? ComputerToolService.emptyUsage
            if let started = entry.startedAt {
                item["started_at"] = .string(ISO8601DateFormatter().string(from: started))
                item["runtime_s"] = .int(max(0, Int(now().timeIntervalSince(started))))
            }
            if let batch = entry.spec.batch { item["batch"] = .string(batch) }
            boxes.append(.object(item))
        }
        let queued = queue.filter { entries[$0]?.spec.parent == parent }.count
        var out: [String: JSON] = ["boxes": .array(boxes), "queue": ["length": .int(queued)]]
        if let label = queueLabel, queued > 0 { out["queue"] = ["length": .int(queued), "label": .string(label)] }
        return .object(out)
    }

    // MARK: Liberar

    public func release(parent: String, names: [String], keep24h: Bool) async -> JSON {
        var released: [String] = []
        var unknown: [String] = []
        for name in names {
            guard let entry = entries[name], entry.spec.parent == parent else { unknown.append(name); continue }
            if entry.phase == .queued || entry.phase == .failed {
                await discard(name, childState: .idle)
            } else {
                await entry.computer.release()
                ComputerToolService.writeTimelineFile(entry.computer)
                await entry.computer.emit(.released(computer: name))
                await finish(entry.computer, keep24h: keep24h)
            }
            released.append(name)
        }
        await drain()
        var out: [String: JSON] = ["released": .array(released.map { .string($0) })]
        if !unknown.isEmpty { out["not_found"] = .array(unknown.map { .string($0) }) }
        return .object(out)
    }

    // MARK: Mensagens do pai (P12)

    public func message(parent: String, to child: String, text: String) async throws -> JSON {
        // `child` é o id do slot ou o nome do computador do filho. Só vale para filho que ESTE pai criou (P12); qualquer outro: T11.
        var childID = child
        if await hub.role(of: child) == nil, let entry = entries[child], entry.spec.parent == parent { childID = entry.childID }
        guard await hub.parent(of: childID) == parent else {
            throw ToolError(.blockedByPolicy, "you can only message subagents you created; paste into other terminals is a user action")
        }
        let delivery: AgentMessageDelivery = entries.values.contains { $0.childID == childID } ? .inbox : .queued
        let stored: StoredAgentMessage
        if let store {
            stored = try await store.appendAgentMessage(parentID: parent, childID: childID, text: text, delivery: delivery, at: now())
        } else {
            stored = StoredAgentMessage(id: UUID().uuidString.lowercased(), parentID: parent, childID: childID, text: text, delivery: delivery, createdAt: now())
            pendingMessages[childID, default: []].append(stored)
        }
        if let entry = entries.values.first(where: { $0.childID == childID }) { await logMessage(stored, in: entry.computer) }
        return ["delivered": .string(delivery.rawValue), "message_id": .string(stored.id), "child_id": .string(childID)]
    }

    private func logMessage(_ message: StoredAgentMessage, in computer: ManagedComputer) async {
        guard loggedMessages.insert(message.id).inserted else { return }
        _ = try? await computer.messages.append([
            "id": .string(message.id), "from": "parent", "to": .string(message.childID), "text": .string(message.text), "text_len": .int(message.text.count),
        ])
        await computer.logEvent("agent_message", "parent -> \(message.childID) (\(message.text.count) chars)")
    }

    public func drainParentMessages(for child: String) async -> [JSON] {
        let list: [StoredAgentMessage]
        if let store { list = (try? await store.pendingAgentMessages(childID: child)) ?? [] }
        else { list = pendingMessages[child] ?? [] }
        guard !list.isEmpty else { return [] }
        if let entry = entries.values.first(where: { $0.childID == child }) {
            for message in list { await logMessage(message, in: entry.computer) }
        }
        if let store { try? await store.markAgentMessagesDelivered(list.map(\.id), at: now()) } else { pendingMessages[child] = [] }
        return list.map { ["id": .string($0.id), "text": .string($0.text), "from": "parent", "sent_at": .string(ISO8601DateFormatter().string(from: $0.createdAt))] }
    }
}

/// Um slot de worker do pai: identidade MCP do filho e o `subagent_type` que o pai usa para dispará-lo.
public struct WorkerSlot: Sendable, Equatable {
    public var childID: String
    public var slot: Int
    public var capability: String
    public var agentType: String { "agentbox-worker-\(slot)" }
    public init(childID: String, slot: Int, capability: String) { self.childID = childID; self.slot = slot; self.capability = capability }
}

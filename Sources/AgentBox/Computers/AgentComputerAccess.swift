import AgentBoxCore
import Combine
import Darwin
import Foundation

/// Viewer and CLI share the same lease authority, including across pane changes.
@MainActor enum DesktopBrokerService {
    static let result = Result { try ControlBroker() }
    private struct Entry {
        let endpoint: BrowserRuntimeEndpoint
        let bridge: ComputerControlBridge<BrowserRuntimeClient>
    }
    private static var entries: [UUID: Entry] = [:]
    /// Only the app's currently held human tickets are released on explicit quit.
    static func releaseHumanControls() async {
        for entry in Array(entries.values) {
            if let ticket = await entry.bridge.ticket(), ticket.grant.actor == .human {
                try? await entry.bridge.releaseHuman(ticket)
            }
        }
    }
    /// Called after a verified stopped-container replacement, while its terminal
    /// is reserved for maintenance. Old viewers must not reuse cached tickets.
    static func invalidateStoppedComputer(computerID: UUID) async throws {
        entries.removeValue(forKey: computerID)
        try await result.get().disconnect(computerID: computerID)
    }
    static func bridge(endpoint: BrowserRuntimeEndpoint, broker: ControlBroker,
                       session: URLSession = .shared) async -> ComputerControlBridge<BrowserRuntimeClient> {
        if let existing = entries[endpoint.computerID],
           existing.endpoint.baseURL == endpoint.baseURL,
           existing.endpoint.apiToken == endpoint.apiToken,
           await existing.bridge.currentGeneration() == endpoint.generation { return existing.bridge }
        let bridge = ComputerControlBridge(broker: broker, transport: BrowserRuntimeClient(endpoint: endpoint, session: session))
        entries[endpoint.computerID] = Entry(endpoint: endpoint, bridge: bridge)
        return bridge
    }
}

/// One native CLI connection can serve several independently authenticated runs.
/// Each run resolves its own computer; a child never falls back to its parent.
@MainActor final class AgentComputerAccess: ObservableObject {
    static let shared = AgentComputerAccess()
    @Published private(set) var connectedChildRuns: Set<UUID> = []
    @Published private(set) var cleanupFailures: [UUID: String] = [:]

    private final class Controller {
        let caller: AgentRunRecord
        let endpoint: BrowserRuntimeEndpoint
        let bridge: ComputerControlBridge<BrowserRuntimeClient>
        let actor: ControlActor
        let automaticallyStarted: Bool
        var active = true
        var busy = false
        var pausedForHuman = false
        var requestID: UUID?
        var cleanupRunning = false
        init(caller: AgentRunRecord, endpoint: BrowserRuntimeEndpoint,
             bridge: ComputerControlBridge<BrowserRuntimeClient>, automaticallyStarted: Bool) {
            self.caller = caller; self.endpoint = endpoint; self.bridge = bridge
            self.automaticallyStarted = automaticallyStarted
            if let parent = caller.parentRunID, let native = caller.nativeAgentID {
                actor = .child(parentRunID: parent, nativeID: native)
            } else { actor = .agent(runID: caller.id) }
        }
    }
    private final class Entry {
        let launch: MaterializedAgentLaunch
        let sessionID: UUID
        let context: ComputerPolicyContext
        let parentEndpoint: BrowserRuntimeEndpoint
        let directory: URL
        var verifier: ComputerCallProvenanceVerifier?
        var hookRunID: UUID?
        var server: LocalMCPServer?
        var active = false
        var controllers: [UUID: Controller] = [:]
        var busyRuns: Set<UUID> = []
        init(launch: MaterializedAgentLaunch, sessionID: UUID, context: ComputerPolicyContext,
             endpoint: BrowserRuntimeEndpoint, directory: URL) {
            self.launch = launch; self.sessionID = sessionID; self.context = context
            self.parentEndpoint = endpoint; self.directory = directory
        }
    }
    private var entries: [UUID: Entry] = [:]
    private var retiring: [UUID: Controller] = [:]
    private var unconnectedAutomatic: [UUID: AgentRunRecord] = [:]
    private var recoveringUnconnected = false
    private var observers: [AnyCancellable] = []
    private let resources: AgentComputerResources
    private let runtime: TerminalRuntimeManager
    private let policyProvider: (ComputerPolicyContext) throws -> EffectiveComputerPolicy
    private let broker: ControlBroker?
    private let runtimeSession: URLSession
    private let notifyUser: @MainActor (HumanRequest) throws -> Void
    private let completeRequest: @MainActor (UUID) throws -> Void

    init(resources: AgentComputerResources = .live, runtime: TerminalRuntimeManager? = nil,
         broker: ControlBroker? = nil, runtimeSession: URLSession = .shared,
         policyProvider: @escaping (ComputerPolicyContext) throws -> EffectiveComputerPolicy = {
             try ComputerPolicyStore().load().effective(for: $0)
         }, notifyUser: (@MainActor (HumanRequest) throws -> Void)? = nil,
         completeRequest: (@MainActor (UUID) throws -> Void)? = nil) {
        self.resources = resources
        self.runtime = runtime ?? WorkspaceServices.terminalRuntime
        self.broker = broker; self.runtimeSession = runtimeSession
        self.policyProvider = policyProvider
        self.notifyUser = notifyUser ?? { try HumanRequestCenter.shared.ingest($0) }
        self.completeRequest = completeRequest ?? {
            try HumanRequestCenter.shared.acknowledge($0)
            try HumanRequestCenter.shared.resolve($0)
        }
        observers.append(self.runtime.$processStates.sink { [weak self] states in
            guard let self else { return }
            for (id, entry) in Array(self.entries) where entry.active {
                switch states[id] {
                case .running?, .starting?: break
                default: self.stop(terminalID: id)
                }
            }
        })
        observers.append(self.runtime.nativeAgentMonitor.$runs.sink { [weak self] records in
            guard let self else { return }
            for entry in self.entries.values where entry.active {
                for (id, controller) in Array(entry.controllers) where controller.caller.kind == .nativeSubagent {
                    let alive = records.contains { $0.id == id && $0.status == .running &&
                        $0.parentRunID == entry.hookRunID }
                    if !alive {
                        entry.controllers[id] = nil
                        self.retire(controller)
                    }
                }
            }
            if !self.unconnectedAutomatic.isEmpty {
                Task { await self.recoverUnconnectedComputers() }
            }
        })
    }

    func register(launch: MaterializedAgentLaunch, sessionID: UUID,
                  policyContext: ComputerPolicyContext, endpoint: BrowserRuntimeEndpoint) async throws {
        guard let config = launch.computerMCP, launch.claudeHookDescriptor != nil,
              let terminal = launch.terminal, terminal.id == policyContext.terminalID,
              sessionID == policyContext.sessionID, config.computerID == endpoint.computerID,
              entries[terminal.id] == nil else { throw AgentLaunchError.invalidBinding }
        try launch.validateContextFile()
        _ = try policy(for: policyContext)
        _ = try await BrowserRuntimeClient(endpoint: endpoint, session: runtimeSession).health()
        guard entries[terminal.id] == nil else { throw AgentLaunchError.invalidBinding }
        let directory = URL(fileURLWithPath: config.socketPath).deletingLastPathComponent()
        guard mkdir(directory.path, 0o700) == 0 else {
            throw LibraryError.invalid("O canal deste lançamento já existe. Prepare um novo lançamento do agente.")
        }
        let entry = Entry(launch: launch, sessionID: sessionID, context: policyContext,
                          endpoint: endpoint, directory: directory)
        do {
            let capability = try String(contentsOfFile: config.capabilityPath, encoding: .utf8)
            let protocolServer = ComputerMCPProtocol { [weak self] name, data in
                guard let self else { throw ComputerMCPAccessError.callerInactive }
                return try await self.call(terminalID: terminal.id, planID: launch.planID, name: name, data: data)
            }
            entry.server = try LocalMCPServer(socketPath: config.socketPath, capability: capability) { data in
                try await protocolServer.respond(data)
            }
            entries[terminal.id] = entry
        } catch { rmdir(directory.path); throw error }
    }

    func activate(terminalID: UUID) throws {
        guard let entry = entries[terminalID], runtime.isRunning(entry.launch),
              let invocation = runtime.hookInvocation(for: terminalID, planID: entry.launch.planID),
              let token = invocation.environment["AGENT_BOX_HOOK_TOKEN"] else {
            stop(terminalID: terminalID); throw AgentLaunchError.invalidBinding
        }
        do { entry.verifier = try ComputerCallProvenanceVerifier(runID: invocation.runID, tokenHex: token) }
        catch { stop(terminalID: terminalID); throw AgentLaunchError.invalidBinding }
        entry.hookRunID = invocation.runID
        entry.active = true
    }

    func stop(terminalID: UUID) {
        guard let entry = entries.removeValue(forKey: terminalID) else { return }
        entry.active = false; entry.verifier = nil
        entry.server?.stop()
        rmdir(entry.directory.path)
        for controller in entry.controllers.values { retire(controller) }
        entry.controllers.removeAll()
        if !unconnectedAutomatic.isEmpty { Task { await self.recoverUnconnectedComputers() } }
    }

    func shutdown() { for id in Array(entries.keys) { stop(terminalID: id) } }

    /// Called after PTYs have been stopped, while the app still services async
    /// cleanup. A timeout reports unresolved computers instead of claiming success.
    func finishShutdown(timeout: TimeInterval = 20) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await DesktopBrokerService.releaseHumanControls()
            await recoverUnconnectedComputers()
            if retiring.isEmpty && unconnectedAutomatic.isEmpty { return 0 }
            for controller in Array(retiring.values) { scheduleCleanup(controller) }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return retiring.count + unconnectedAutomatic.count
    }

    func humanReleased(computerID: UUID) {
        for entry in entries.values {
            for controller in entry.controllers.values where controller.endpoint.computerID == computerID {
                controller.pausedForHuman = false
                if let id = controller.requestID {
                    try? completeRequest(id)
                    controller.requestID = nil
                }
            }
        }
        controlDisconnected(computerID: computerID)
    }

    /// Closing a viewer may permit retiring an ended child's box, but must not
    /// resume a still-running agent that explicitly requested human intervention.
    func controlDisconnected(computerID: UUID) {
        if let controller = retiring[computerID] { scheduleCleanup(controller) }
    }

    private func retire(_ controller: Controller) {
        controller.active = false
        connectedChildRuns.remove(controller.caller.id)
        retiring[controller.endpoint.computerID] = controller
        scheduleCleanup(controller)
    }

    /// A failed health/Keychain connection must not lose ownership of a newly
    /// started box. Retry cleanup only after the native caller has ended.
    private func recoverUnconnectedComputers() async {
        guard !recoveringUnconnected else { return }
        recoveringUnconnected = true
        defer { recoveringUnconnected = false }
        for (id, record) in Array(unconnectedAutomatic) {
            if entries[record.terminalID]?.active == true,
               runtime.nativeAgentMonitor.isCurrentNativeChild(runID: record.id,
                   parentTerminalID: record.terminalID, runtime: runtime) { continue }
            do {
                let owner = BrowserComputerOwner.nativeChild(parentTerminalID: record.terminalID, agentRunID: record.id)
                let current = try await resources.lookup(owner)
                guard let current, current.id == id, current.running else {
                    unconnectedAutomatic[id] = nil
                    cleanupFailures[id] = nil
                    continue
                }
                let endpoint = try await resources.endpoint(id)
                guard endpoint.computerID == id else { throw BrowserComputerError.unmanagedContainer }
                let bridge = await DesktopBrokerService.bridge(endpoint: endpoint,
                    broker: try broker ?? DesktopBrokerService.result.get(), session: runtimeSession)
                let controller = Controller(caller: record, endpoint: endpoint, bridge: bridge, automaticallyStarted: true)
                unconnectedAutomatic[id] = nil
                retire(controller)
            } catch {
                cleanupFailures[id] = "A box ainda não pôde ser reconectada para encerrar. Confira o computador."
            }
        }
    }

    private func scheduleCleanup(_ controller: Controller) {
        guard !controller.cleanupRunning else { return }
        controller.cleanupRunning = true
        Task { [weak self] in
            guard let self else { return }
            defer { controller.cleanupRunning = false }
            // Accepted writes finish first. No new call can enter this controller.
            for _ in 0..<600 {
                if !controller.busy { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !controller.busy else {
                cleanupFailures[controller.endpoint.computerID] = "A operação ainda não terminou. Pare a box quando ela estiver livre."
                return
            }
            do {
                if let ticket = await controller.bridge.ticket(), ticket.grant.actor == controller.actor {
                    try await controller.bridge.releaseController(ticket)
                }
                if controller.automaticallyStarted {
                    let resources = self.resources, id = controller.endpoint.computerID
                    try await controller.bridge.performIdleMaintenance { try await resources.stop(id) }
                }
                cleanupFailures[controller.endpoint.computerID] = nil
                if retiring[controller.endpoint.computerID] === controller {
                    retiring[controller.endpoint.computerID] = nil
                }
            } catch ControlBrokerError.activeRuntimeLease {
                // A human may keep using the computer. Retry only on control release.
                cleanupFailures[controller.endpoint.computerID] = "O subagente terminou. A box será parada quando o controle for devolvido."
            } catch {
                cleanupFailures[controller.endpoint.computerID] = "Não foi possível encerrar o controle ou parar a box. Confira o computador."
            }
        }
    }

    private func caller(for entry: Entry, verified: VerifiedComputerCall) async throws -> AgentRunRecord {
        guard entry.active, runtime.isRunning(entry.launch), let runID = entry.hookRunID,
              verified.runID == runID, let terminalID = entry.launch.terminal?.id else {
            throw ComputerMCPAccessError.callerInactive
        }
        let record: AgentRunRecord
        do {
            record = try await runtime.nativeAgentMonitor.verifiedCaller(terminalID: terminalID,
                runID: runID, sessionID: verified.sessionID, agentID: verified.agentID)
        } catch { throw ComputerMCPAccessError.callerInactive }
        guard entry.active, runtime.isRunning(entry.launch) else { throw ComputerMCPAccessError.callerInactive }
        return record
    }

    private func policy(for context: ComputerPolicyContext) throws -> EffectiveComputerPolicy {
        let result = try policyProvider(context)
        guard result.creation != .disabled else { throw ComputerPolicyError.creationDisabled }
        guard result.networkAllowed else { throw BrowserComputerError.networkDisabled }
        return result
    }

    func call(terminalID: UUID, planID: UUID, name: String, data: Data) async throws -> ComputerMCPResult {
        guard let entry = entries[terminalID], entry.launch.planID == planID, entry.active,
              runtime.isRunning(entry.launch), let verifier = entry.verifier else {
            throw ComputerMCPAccessError.callerInactive
        }
        let verified = try await verifier.verify(toolName: "mcp__agentbox__\(name)", argumentsData: data)
        let record = try await caller(for: entry, verified: verified)
        guard !entry.busyRuns.contains(record.id) else { throw ComputerMCPAccessError.busy }
        entry.busyRuns.insert(record.id)
        defer { entry.busyRuns.remove(record.id) }
        let arguments = try ComputerMCPToolArguments.validate(name: name, data: verified.argumentsData)
        let effective = try policy(for: entry.context)
        let requestedMode: BrowserRuntimeMode?
        if case .acquire(let mode) = arguments { requestedMode = mode } else { requestedMode = nil }
        if let requestedMode, effective.modePreference == .alwaysGraphical && requestedMode != .desktop {
            throw ComputerPolicyError.graphicalUnavailable
        }
        let controller = try await resolveController(entry: entry, record: record, verified: verified,
                                                     acquireMode: requestedMode)
        guard controller.active, !controller.busy else { throw ComputerMCPAccessError.busy }
        controller.busy = true
        defer { controller.busy = false }
        _ = try await caller(for: entry, verified: verified)
        let generation = await controller.bridge.currentGeneration()
        let client = try BrowserRuntimeClient(endpoint: controller.endpoint, session: runtimeSession).refreshed(generation: generation)
        switch arguments {
        case .status:
            let health = try await client.health()
            return .text("mode=\(health.mode.rawValue); control=\(health.activeLease?.actorID ?? "idle"); awaiting_user=\(controller.pausedForHuman)")
        case .screenshot: return .jpeg(try await client.browserOrDesktopFrame())
        case .page:
            let page = try await client.page()
            return try Self.jsonText(["url": page.url, "title": page.title, "text": page.text,
                "links": page.links.map { ["url": $0.url, "label": $0.label] }, "truncated": page.truncated])
        case .requestHelp:
            controller.pausedForHuman = true
            if let ticket = await controller.bridge.ticket(), ticket.grant.actor == controller.actor {
                try await controller.bridge.releaseController(ticket)
            }
            if controller.requestID == nil {
                let request = HumanRequest(target: .init(sessionID: entry.sessionID, terminalID: terminalID,
                    runID: record.id, computerID: controller.endpoint.computerID), kind: .other,
                    summary: "O agente pediu que você assuma este computador. Consulte o terminal para os detalhes.")
                try notifyUser(request)
                controller.requestID = request.id
            }
            return .text("User notified. Computer writes are paused until the user takes and releases control.")
        default: break
        }
        guard controller.active, !controller.pausedForHuman else { throw ComputerControlBridgeError.noTicket }
        _ = try await caller(for: entry, verified: verified)
        let ticket: ComputerControlTicket
        if let parent = record.parentRunID, let child = record.nativeAgentID {
            ticket = try await controller.bridge.assumeChild(parentRunID: parent, nativeChildID: child,
                paths: Set(ControlWritePath.allCases), allowedParentPaths: Set(ControlWritePath.allCases))
        } else { ticket = try await controller.bridge.assumeAgent(runID: record.id) }
        let currentPolicy: EffectiveComputerPolicy
        do {
            _ = try await caller(for: entry, verified: verified)
            guard controller.active else { throw ComputerMCPAccessError.callerInactive }
            currentPolicy = try policy(for: entry.context)
        } catch { try? await controller.bridge.releaseController(ticket); throw error }
        let result: ComputerMCPResult
        switch arguments {
        case .mode(let mode), .acquire(let mode):
            guard currentPolicy.modePreference != .alwaysGraphical || mode == .desktop else {
                throw ComputerPolicyError.graphicalUnavailable
            }
            let health = try await controller.bridge.changeMode(mode, ticket: ticket)
            result = .text("mode=\(health.mode.rawValue); generation=\(health.generation); computer belongs to this caller")
        case .navigate(let url):
            _ = try await controller.bridge.navigate(to: url, ticket: ticket)
            result = .text("Navigation completed. Use computer_page for text and links, or computer_screenshot to inspect visually.")
        case .httpRequest(let url, let method):
            let response = try await controller.bridge.httpRequest(to: url, method: method, ticket: ticket)
            var body: [String: Any] = ["status": response.status, "content_type": response.contentType]
            if let text = String(data: response.body, encoding: .utf8) { body["text"] = text }
            else { body["body_base64"] = response.bodyBase64 }
            result = try Self.jsonText(body)
        case .input(let action):
            try await controller.bridge.input(action, ticket: ticket)
            result = .text("Input accepted.")
        default: throw ComputerControlBridgeError.writeDenied
        }
        guard controller.active, entry.active else { throw ComputerMCPAccessError.callerInactive }
        return result
    }

    private func resolveController(entry: Entry, record: AgentRunRecord, verified: VerifiedComputerCall,
                                   acquireMode: BrowserRuntimeMode?) async throws -> Controller {
        if record.kind == .nativeSubagent {
            try runtime.requireChildScrapingContext(for: record.terminalID)
        }
        if let controller = entry.controllers[record.id], controller.active { return controller }
        if record.kind == .terminal {
            let bridge = await DesktopBrokerService.bridge(endpoint: entry.parentEndpoint,
                broker: try broker ?? DesktopBrokerService.result.get(), session: runtimeSession)
            _ = try await caller(for: entry, verified: verified)
            let controller = Controller(caller: record, endpoint: entry.parentEndpoint,
                                        bridge: bridge, automaticallyStarted: false)
            entry.controllers[record.id] = controller
            return controller
        }
        let owner = BrowserComputerOwner.nativeChild(parentTerminalID: record.terminalID, agentRunID: record.id)
        let existing = try await resources.lookup(owner)
        _ = try await caller(for: entry, verified: verified)
        if let existing, retiring[existing.id] != nil ||
            (recoveringUnconnected && unconnectedAutomatic[existing.id] != nil) {
            // Native resume may reuse a child ID. Its next invocation must wait
            // for retirement of the previous controller before reusing the box.
            throw ComputerMCPAccessError.busy
        }
        if acquireMode == nil && existing?.running != true { throw ComputerMCPAccessError.childComputerMissing }
        let currentPolicy = try policy(for: entry.context)
        let action = try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: existing,
            creation: currentPolicy.creation, callerActive: true, busy: false, capabilitySupported: true)
        let computer: BrowserManagedComputer
        switch action {
        case .connectExisting: computer = existing!
        case .create, .startExisting:
            // The service rechecks automatic permission under its creation lock.
            computer = try await resources.acquire(owner, entry.context)
        }
        guard computer.owner == owner else { throw BrowserComputerError.unmanagedContainer }
        var acquiredController: Controller?
        do {
            let endpoint = try await resources.endpoint(computer.id)
            guard endpoint.computerID == computer.id else { throw BrowserComputerError.unmanagedContainer }
            let bridge = await DesktopBrokerService.bridge(endpoint: endpoint,
                broker: try broker ?? DesktopBrokerService.result.get(), session: runtimeSession)
            let controller = Controller(caller: record, endpoint: endpoint, bridge: bridge,
                automaticallyStarted: action != .connectExisting || unconnectedAutomatic[computer.id] != nil)
            acquiredController = controller
            _ = try await caller(for: entry, verified: verified)
            _ = try policy(for: entry.context)
            entry.controllers[record.id] = controller
            unconnectedAutomatic[computer.id] = nil
            cleanupFailures[computer.id] = nil
            connectedChildRuns.insert(record.id)
            return controller
        } catch {
            if let controller = acquiredController { retire(controller) }
            else if action != .connectExisting {
                // No endpoint/lease was handed to an agent. Preserve files and attempt
                // stopping only after the live runtime can be confirmed idle.
                cleanupFailures[computer.id] = "O computador iniciou, mas não conectou. Confira e pare a box se necessário."
                unconnectedAutomatic[computer.id] = record
                if !entry.active { Task { await self.recoverUnconnectedComputers() } }
            }
            throw error
        }
    }

    private static func jsonText(_ value: [String: Any]) throws -> ComputerMCPResult {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw BrowserRuntimeError.invalidResponse }
        return .text(text)
    }
}

/// Docker CLI work never runs on the UI actor. Tests can replace resource access
/// without creating containers or reading the user's Keychain.
struct AgentComputerResources: Sendable {
    let lookup: @Sendable (BrowserComputerOwner) async throws -> BrowserManagedComputer?
    let acquire: @Sendable (BrowserComputerOwner, ComputerPolicyContext) async throws -> BrowserManagedComputer
    let endpoint: @Sendable (UUID) async throws -> BrowserRuntimeEndpoint
    let stop: @Sendable (UUID) async throws -> Void

    static var live: Self {
        let service = BrowserComputerService(runner: DockerProcessRunner(), tokens: KeychainBrowserComputerTokenStore())
        return Self(
            lookup: { owner in try await Task.detached(priority: .utility) { try service.computer(for: owner) }.value },
            acquire: { owner, context in try await Task.detached(priority: .utility) {
                try service.createAndStart(for: owner, context: context, automaticRequest: true)
            }.value },
            endpoint: { id in
                var last: Error = BrowserComputerError.notReady
                for attempt in 0..<8 {
                    do {
                        return try await Task.detached(priority: .utility) {
                            try await service.reconnectEndpoint(computerID: id)
                        }.value
                    }
                    catch {
                        last = error
                        if case BrowserComputerError.tokenAuthorizationRequired = error { throw error }
                        if case BrowserComputerError.tokenAuthorizationDenied = error { throw error }
                        if case BrowserComputerError.keychainTimedOut = error { throw error }
                    }
                    if attempt < 7 { try await Task.sleep(nanoseconds: 500_000_000) }
                }
                throw last
            },
            stop: { id in try await Task.detached(priority: .utility) { try service.stop(computerID: id) }.value })
    }
}

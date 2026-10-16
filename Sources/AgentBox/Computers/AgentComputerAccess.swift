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

/// A reviewed native CLI gets one local capability for one assigned computer.
/// No container token is placed in CLI argv, environment, context, or responses.
@MainActor final class AgentComputerAccess {
    static let shared = AgentComputerAccess()
    private final class Entry {
        let launch: MaterializedAgentLaunch
        let sessionID: UUID
        let context: ComputerPolicyContext
        let endpoint: BrowserRuntimeEndpoint
        let bridge: ComputerControlBridge<BrowserRuntimeClient>
        let directory: URL
        var server: LocalMCPServer?
        var active = false
        var busy = false
        var pausedForHuman = false
        var requestID: UUID?
        init(launch: MaterializedAgentLaunch, sessionID: UUID, context: ComputerPolicyContext,
             endpoint: BrowserRuntimeEndpoint, bridge: ComputerControlBridge<BrowserRuntimeClient>, directory: URL) {
            self.launch = launch; self.sessionID = sessionID; self.context = context
            self.endpoint = endpoint; self.bridge = bridge; self.directory = directory
        }
    }
    private var entries: [UUID: Entry] = [:]
    private var observer: AnyCancellable?
    private init() {
        observer = WorkspaceServices.terminalRuntime.$processStates.sink { [weak self] states in
            guard let self else { return }
            for (id, entry) in self.entries where entry.active {
                switch states[id] {
                case .running?, .starting?: break
                default: self.stop(terminalID: id)
                }
            }
        }
    }

    func register(launch: MaterializedAgentLaunch, sessionID: UUID,
                  policyContext: ComputerPolicyContext, endpoint: BrowserRuntimeEndpoint) async throws {
        guard let config = launch.computerMCP, let terminal = launch.terminal,
              terminal.id == policyContext.terminalID, sessionID == policyContext.sessionID,
              config.computerID == endpoint.computerID, entries[terminal.id] == nil else {
            throw AgentLaunchError.invalidBinding
        }
        try launch.validateContextFile()
        let policy = try ComputerPolicyStore().load().effective(for: policyContext)
        guard policy.creation != .disabled else { throw ComputerPolicyError.creationDisabled }
        guard policy.networkAllowed else { throw BrowserComputerError.networkDisabled }
        _ = try await BrowserRuntimeClient(endpoint: endpoint).health()
        // Another launch may have registered while health was in flight.
        guard entries[terminal.id] == nil else { throw AgentLaunchError.invalidBinding }
        let directory = URL(fileURLWithPath: config.socketPath).deletingLastPathComponent()
        // Never delete or reuse an unknown stale socket directory after a crash.
        guard mkdir(directory.path, 0o700) == 0 else {
            throw LibraryError.invalid("O canal deste lançamento já existe. Prepare um novo lançamento do agente.")
        }
        let bridge = await DesktopBrokerService.bridge(endpoint: endpoint, broker: try DesktopBrokerService.result.get())
        let entry = Entry(launch: launch, sessionID: sessionID, context: policyContext,
                          endpoint: endpoint, bridge: bridge, directory: directory)
        do {
            let capability = try String(contentsOfFile: config.capabilityPath, encoding: .utf8)
            let protocolServer = ComputerMCPProtocol { [weak self] name, data in
                guard let self else { throw ComputerControlBridgeError.noTicket }
                return try await self.call(terminalID: terminal.id, planID: launch.planID, name: name, data: data)
            }
            entry.server = try LocalMCPServer(socketPath: config.socketPath, capability: capability) { data in
                try await protocolServer.respond(data)
            }
            entries[terminal.id] = entry
        } catch {
            rmdir(directory.path)
            throw error
        }
    }

    func activate(terminalID: UUID) {
        guard let entry = entries[terminalID], WorkspaceServices.terminalRuntime.isRunning(entry.launch) else {
            stop(terminalID: terminalID); return
        }
        entry.active = true
    }

    func stop(terminalID: UUID) {
        guard let entry = entries.removeValue(forKey: terminalID) else { return }
        entry.active = false
        entry.server?.stop()
        rmdir(entry.directory.path)
        Task {
            // Let an accepted write finish before revoking; the server is already closed.
            // A takeover may be in flight too. Retrying must never revoke a newer human grant.
            for _ in 0..<600 {
                if !entry.busy {
                    guard let ticket = await entry.bridge.ticket(),
                          ticket.grant.actor == .agent(runID: entry.launch.planID) else { return }
                    do { try await entry.bridge.releaseAgent(ticket); return }
                    catch ControlBrokerError.transitionInProgress { }
                    catch { return }
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func shutdown() { for id in Array(entries.keys) { stop(terminalID: id) } }

    /// Only an explicit successful human release unpauses a request for intervention.
    func humanReleased(computerID: UUID) {
        for entry in entries.values where entry.endpoint.computerID == computerID {
            entry.pausedForHuman = false
            if let id = entry.requestID {
                try? HumanRequestCenter.shared.acknowledge(id)
                try? HumanRequestCenter.shared.resolve(id)
                entry.requestID = nil
            }
        }
    }

    private func call(terminalID: UUID, planID: UUID, name: String, data: Data) async throws -> ComputerMCPResult {
        guard let entry = entries[terminalID], entry.launch.planID == planID, entry.active,
              WorkspaceServices.terminalRuntime.isRunning(entry.launch), !entry.busy else {
            throw ComputerControlBridgeError.noTicket
        }
        entry.busy = true
        defer { entry.busy = false }
        let arguments = try ComputerMCPToolArguments.validate(name: name, data: data)
        let policy = try ComputerPolicyStore().load().effective(for: entry.context)
        guard policy.creation != .disabled else { throw ComputerPolicyError.creationDisabled }
        guard policy.networkAllowed else { throw BrowserComputerError.networkDisabled }
        let generation = await entry.bridge.currentGeneration()
        let client = try BrowserRuntimeClient(endpoint: entry.endpoint).refreshed(generation: generation)
        switch arguments {
        case .status:
            let health = try await client.health()
            return .text("mode=\(health.mode.rawValue); control=\(health.activeLease?.actorID ?? "idle"); awaiting_user=\(entry.pausedForHuman)")
        case .screenshot:
            return .jpeg(try await client.browserOrDesktopFrame())
        case .page:
            let page = try await client.page()
            guard entry.active else { throw ComputerControlBridgeError.noTicket }
            return try Self.jsonText([
                "url": page.url, "title": page.title, "text": page.text,
                "links": page.links.map { ["url": $0.url, "label": $0.label] },
                "truncated": page.truncated
            ])
        case .requestHelp:
            entry.pausedForHuman = true
            if let ticket = await entry.bridge.ticket(), ticket.grant.actor == .agent(runID: planID) {
                try await entry.bridge.releaseAgent(ticket)
            }
            if entry.requestID == nil {
                let request = HumanRequest(target: .init(sessionID: entry.sessionID, terminalID: terminalID,
                    runID: planID, computerID: entry.endpoint.computerID), kind: .other,
                    summary: "O agente pediu que você assuma este computador. Consulte o terminal para os detalhes.")
                try HumanRequestCenter.shared.ingest(request)
                entry.requestID = request.id
            }
            return .text("User notified. Computer writes are paused until the user takes and releases control.")
        default: break
        }
        guard !entry.pausedForHuman, entry.active,
              WorkspaceServices.terminalRuntime.isRunning(entry.launch) else { throw ComputerControlBridgeError.noTicket }
        let ticket = try await entry.bridge.assumeAgent(runID: planID)
        guard entry.active else { try? await entry.bridge.releaseAgent(ticket); throw ComputerControlBridgeError.noTicket }
        switch arguments {
        case .mode(let mode):
            guard policy.modePreference != .alwaysGraphical || mode == .desktop else { throw ComputerPolicyError.graphicalUnavailable }
            let result = try await entry.bridge.changeMode(mode, ticket: ticket)
            guard entry.active else { throw ComputerControlBridgeError.noTicket }
            return .text("mode=\(result.mode.rawValue); generation=\(result.generation)")
        case .navigate(let url):
            _ = try await entry.bridge.navigate(to: url, ticket: ticket)
            guard entry.active else { throw ComputerControlBridgeError.noTicket }
            return .text("Navigation completed. Use computer_page for text and links, or computer_screenshot to inspect visually.")
        case .httpRequest(let url, let method):
            let response = try await entry.bridge.httpRequest(to: url, method: method, ticket: ticket)
            guard entry.active else { throw ComputerControlBridgeError.noTicket }
            var result: [String: Any] = ["status": response.status, "content_type": response.contentType]
            if let text = String(data: response.body, encoding: .utf8) {
                result["text"] = text
            } else {
                result["body_base64"] = response.bodyBase64
            }
            return try Self.jsonText(result)
        case .input(let action):
            try await entry.bridge.input(action, ticket: ticket)
            guard entry.active else { throw ComputerControlBridgeError.noTicket }
            return .text("Input accepted.")
        default: throw ComputerControlBridgeError.writeDenied
        }
    }

    private static func jsonText(_ value: [String: Any]) throws -> ComputerMCPResult {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else { throw BrowserRuntimeError.invalidResponse }
        return .text(text)
    }
}

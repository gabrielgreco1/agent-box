import AgentBoxCore
import Foundation
import SwiftUI

/// App-facing state for browser computers. Endpoints and bearer tokens are memory-only.
@MainActor
final class BrowserComputerStore: ObservableObject {
    private static var updatingComputerIDs: Set<UUID> = []
    private static var updatingTerminalIDs: Set<UUID> = []
    private static var endpointEpochs: [UUID: UInt64] = [:]
    @Published private(set) var computers: [BrowserManagedComputer] = []
    @Published private(set) var endpoints: [UUID: BrowserRuntimeEndpoint] = [:]
    @Published private(set) var busyComputerIDs: Set<UUID> = []
    @Published private(set) var scrapingAssignments: [UUID: ScrapingBoxAssignment] = [:]
    @Published private(set) var imageUpdateStatuses: [UUID: BrowserComputerImageUpdateStatus] = [:]
    @Published private(set) var pendingImageUpdate: PendingBrowserImageUpdate?
    @Published private(set) var imageUpdateRecoveryBlocked = false
    @Published private(set) var imageUpdateAuthorizationRequired: Set<UUID> = []
    @Published private(set) var errorText: String?
    @Published private(set) var tokenAuthorizationRequired: Set<UUID> = []

    private let service: BrowserComputerService<DockerProcessRunner, KeychainBrowserComputerTokenStore>
    private var reconnectTasks: [UUID: Task<BrowserRuntimeEndpoint, Error>] = [:]

    init(runner: DockerProcessRunner = DockerProcessRunner(),
         policyStore: ComputerPolicyStore = ComputerPolicyStore()) {
        service = BrowserComputerService(runner: runner, tokens: KeychainBrowserComputerTokenStore(),
                                         policyStore: policyStore)
    }

    func computer(for terminalID: UUID) -> BrowserManagedComputer? {
        computer(for: .terminal(terminalID))
    }

    func computer(for owner: BrowserComputerOwner) -> BrowserManagedComputer? {
        computers.first(where: { $0.owner == owner })
    }

    func scrapingAssignment(for computerID: UUID) -> ScrapingBoxAssignment? {
        scrapingAssignments[computerID]
    }

    func refresh() async {
        let service = service
        do {
            pendingImageUpdate = try await Task.detached(priority: .utility) {
                try service.pendingImageUpdate()
            }.value
            imageUpdateRecoveryBlocked = false
        } catch {
            pendingImageUpdate = nil
            imageUpdateRecoveryBlocked = true
            errorText = error.localizedDescription
        }
        do {
            let found = try await Task.detached(priority: .utility) { try service.list() }.value
            let recoveryBlocksProbe = pendingImageUpdate != nil || imageUpdateRecoveryBlocked
            let imageResults = await Task.detached(priority: .utility) {
                var statuses: [UUID: BrowserComputerImageUpdateStatus] = [:]
                var firstError: String?
                for computer in found where !computer.running && !recoveryBlocksProbe {
                    do { statuses[computer.id] = try service.imageUpdateStatus(computerID: computer.id) }
                    catch { if firstError == nil { firstError = error.localizedDescription } }
                }
                return (statuses, firstError)
            }.value
            computers = found
            scrapingAssignments = try ScrapingBoxAssignmentStore().load()
            endpoints = endpoints.filter { id, _ in found.contains(where: { $0.id == id && $0.running }) }
            imageUpdateStatuses = imageResults.0
            if !imageUpdateRecoveryBlocked { errorText = imageResults.1 }
        } catch { errorText = error.localizedDescription }
    }

    @discardableResult
    func createAndStart(terminalID: UUID, context: ComputerPolicyContext) async throws -> BrowserManagedComputer {
        try ensureAvailable(terminalID: terminalID)
        busyComputerIDs.insert(terminalID)
        defer { busyComputerIDs.remove(terminalID) }
        do {
            let defaultAgent = try prepareDefaultAgent()
            let service = service
            let computer = try await Task.detached(priority: .utility) {
                try service.createAndStart(for: terminalID, context: context)
            }.value
            try saveAssignment(for: computer, defaultAgent: defaultAgent)
            await refresh()
            try await connectReady(computerID: computer.id)
            return computer
        } catch {
            await refresh()
            errorText = error.localizedDescription
            throw error
        }
    }

    /// A native child is an observed run sharing its parent's PTY. Its box has
    /// a separate owner; no saved scraping agent or launch binding is created.
    @discardableResult
    func createAndStart(owner: BrowserComputerOwner, context: ComputerPolicyContext) async throws -> BrowserManagedComputer {
        guard case .nativeChild(let parentTerminalID, let runID) = owner,
              context.terminalID == parentTerminalID else {
            throw LibraryError.invalid("O dono do computador não corresponde ao terminal pai.")
        }
        try requireCurrentNativeChild(owner)
        try WorkspaceServices.terminalRuntime.requireChildScrapingContext(for: parentTerminalID)
        try ensureAvailable(computerID: runID)
        busyComputerIDs.insert(runID)
        defer { busyComputerIDs.remove(runID) }
        var startedComputerID: UUID?
        do {
            // Recheck immediately before scheduling Docker work; a historical
            // child must never acquire a newly launched box.
            try requireCurrentNativeChild(owner)
            let service = service
            let computer = try await Task.detached(priority: .utility) {
                try service.createAndStart(for: owner, context: context)
            }.value
            guard computer.owner == owner else { throw BrowserComputerError.unmanagedContainer }
            startedComputerID = computer.id
            try requireCurrentNativeChild(owner)
            await refresh()
            try await connectReady(computerID: computer.id)
            try requireCurrentNativeChild(owner)
            return computer
        } catch {
            var reportedError = error
            if !isCurrentNativeChild(owner) {
                let service = service
                let computerID: UUID?
                if let startedComputerID {
                    computerID = startedComputerID
                } else {
                    computerID = try? await Task.detached(priority: .utility) {
                        try service.computer(for: owner)?.id
                    }.value
                }
                if let computerID {
                    let stopped = await stopAndVerify(computerID: computerID)
                    reportedError = LibraryError.invalid(stopped
                        ? "O subagente deixou de estar ativo. O computador foi preservado e parado."
                        : "O subagente deixou de estar ativo. Confira e pare o computador antes de continuar.")
                }
            }
            await refresh()
            errorText = reportedError.localizedDescription
            throw reportedError
        }
    }

    func assignDefault(to computer: BrowserManagedComputer) throws {
        guard computer.owner == .terminal(computer.terminalID) else {
            throw LibraryError.invalid("Subagentes nativos não usam o lançamento salvo do terminal pai.")
        }
        try saveAssignment(for: computer, defaultAgent: prepareDefaultAgent())
        errorText = nil
    }

    private func prepareDefaultAgent() throws -> (agentID: UUID, skillID: UUID) {
        let library = LibraryStore()
        guard let agentID = library.createScrapingAgent(),
              let agent = library.document.agents.first(where: { $0.id == agentID }),
              let skillID = agent.skillIDs.first(where: { id in
                  library.document.skills.contains(where: { $0.id == id && $0.name == "webscraping-expert" })
              }) else {
            throw LibraryError.invalid(library.error ?? "Não foi possível preparar o agente de scraping padrão.")
        }
        return (agentID, skillID)
    }

    private func saveAssignment(for computer: BrowserManagedComputer,
                                defaultAgent: (agentID: UUID, skillID: UUID)) throws {
        let assignment = ScrapingBoxAssignment(computerID: computer.id, terminalID: computer.terminalID,
            defaultAgentDefinitionID: defaultAgent.agentID, skillID: defaultAgent.skillID)
        let assignmentStore = ScrapingBoxAssignmentStore()
        var next = try assignmentStore.load()
        next[computer.id] = assignment
        try assignmentStore.save(next)
        scrapingAssignments = next
    }

    @discardableResult
    func start(computerID: UUID, owner: BrowserComputerOwner,
               context: ComputerPolicyContext) async throws -> BrowserManagedComputer {
        try ensureAvailable(computerID: computerID)
        guard let current = computers.first(where: { $0.id == computerID }),
              current.owner == owner, current.terminalID == context.terminalID else {
            throw BrowserComputerError.missingComputer
        }
        if current.agentRunID != nil { try requireCurrentNativeChild(current.owner) }
        busyComputerIDs.insert(computerID)
        defer { busyComputerIDs.remove(computerID) }
        do {
            let service = service
            let computer = try await Task.detached(priority: .utility) {
                try service.start(computerID: computerID, context: context)
            }.value
            guard computer.owner == current.owner else { throw BrowserComputerError.unmanagedContainer }
            if current.agentRunID != nil { try requireCurrentNativeChild(current.owner) }
            await refresh()
            try await connectReady(computerID: computerID)
            if current.agentRunID != nil { try requireCurrentNativeChild(current.owner) }
            return computer
        } catch {
            var reportedError = error
            if current.agentRunID != nil && !isCurrentNativeChild(current.owner) {
                let stopped = await stopAndVerify(computerID: computerID)
                reportedError = LibraryError.invalid(stopped
                    ? "O subagente deixou de estar ativo. O computador foi preservado e parado."
                    : "O subagente deixou de estar ativo. Confira e pare o computador antes de continuar.")
            }
            await refresh()
            errorText = reportedError.localizedDescription
            throw reportedError
        }
    }

    func stop(computerID: UUID, owner: BrowserComputerOwner) async throws {
        // A pending update journal can describe a canonical box that was started
        // outside this process. Stopping that owned box must remain possible so
        // explicit recovery can proceed.
        guard let current = computers.first(where: { $0.id == computerID && $0.owner == owner }) else {
            throw BrowserComputerError.missingComputer
        }
        guard !busyComputerIDs.contains(computerID),
              !busyComputerIDs.contains(current.terminalID),
              !Self.updatingComputerIDs.contains(computerID),
              !Self.updatingTerminalIDs.contains(current.terminalID) else {
            throw LibraryError.invalid("Este computador já está em outra operação.")
        }
        busyComputerIDs.insert(computerID)
        defer { busyComputerIDs.remove(computerID) }
        invalidateEndpoint(computerID)
        do {
            let service = service
            try await Task.detached(priority: .utility) { try service.stop(computerID: computerID) }.value
            await refresh()
        } catch { errorText = error.localizedDescription; throw error }
    }

    @discardableResult
    func updateStoppedImage(computerID: UUID, owner: BrowserComputerOwner,
                            context: ComputerPolicyContext,
                            interactiveAuthorization: Bool = false) async throws -> BrowserManagedComputer {
        try ensureAvailable(computerID: computerID)
        guard let current = computers.first(where: { $0.id == computerID }),
              current.owner == owner, current.terminalID == context.terminalID,
              !current.running else {
            throw LibraryError.invalid("Pare o computador antes de atualizar sua imagem.")
        }
        let maintenance = try WorkspaceServices.terminalRuntime.beginComputerMaintenance(terminalID: current.terminalID)
        defer { WorkspaceServices.terminalRuntime.endComputerMaintenance(terminalID: current.terminalID, ticket: maintenance) }
        busyComputerIDs.insert(computerID)
        Self.updatingComputerIDs.insert(computerID)
        Self.updatingTerminalIDs.insert(current.terminalID)
        defer {
            Self.updatingComputerIDs.remove(computerID)
            Self.updatingTerminalIDs.remove(current.terminalID)
            busyComputerIDs.remove(computerID)
        }
        invalidateEndpoint(computerID)
        AgentComputerAccess.shared.stop(terminalID: current.terminalID)
        do {
            let service = service
            let updated = try await Task.detached(priority: .utility) {
                try service.updateStoppedImage(computerID: computerID, context: context,
                                               interactiveAuthorization: interactiveAuthorization)
            }.value
            guard updated.id == current.id, updated.terminalID == current.terminalID,
                  updated.volumeName == current.volumeName, !updated.running else {
                throw BrowserComputerError.invalidDockerResponse
            }
            try await DesktopBrokerService.invalidateStoppedComputer(computerID: computerID)
            await refresh()
            guard computers.contains(where: { $0 == updated }) else { throw BrowserComputerError.notReady }
            imageUpdateAuthorizationRequired.remove(computerID)
            return updated
        } catch {
            await refresh()
            switch error {
            case BrowserComputerError.tokenAuthorizationRequired,
                 BrowserComputerError.tokenAuthorizationDenied,
                 BrowserComputerError.keychainTimedOut:
                imageUpdateAuthorizationRequired.insert(computerID)
            default:
                imageUpdateAuthorizationRequired.remove(computerID)
            }
            errorText = error.localizedDescription
            throw error
        }
    }

    func recoverStoppedImageUpdate() async throws {
        guard let pending = pendingImageUpdate else {
            throw BrowserComputerError.updateRecoveryRequired
        }
        try ensureAvailableForRecovery(pending)
        let maintenance = try WorkspaceServices.terminalRuntime.beginComputerMaintenance(terminalID: pending.terminalID)
        defer { WorkspaceServices.terminalRuntime.endComputerMaintenance(terminalID: pending.terminalID, ticket: maintenance) }
        busyComputerIDs.insert(pending.computerID)
        Self.updatingComputerIDs.insert(pending.computerID)
        Self.updatingTerminalIDs.insert(pending.terminalID)
        defer {
            Self.updatingComputerIDs.remove(pending.computerID)
            Self.updatingTerminalIDs.remove(pending.terminalID)
            busyComputerIDs.remove(pending.computerID)
        }
        invalidateEndpoint(pending.computerID)
        AgentComputerAccess.shared.stop(terminalID: pending.terminalID)
        do {
            let service = service
            try await Task.detached(priority: .utility) {
                try service.recoverStoppedImageUpdate()
            }.value
            try await DesktopBrokerService.invalidateStoppedComputer(computerID: pending.computerID)
            await refresh()
            guard pendingImageUpdate == nil, !imageUpdateRecoveryBlocked else {
                throw BrowserComputerError.updateRecoveryRequired
            }
        } catch {
            await refresh()
            errorText = error.localizedDescription
            throw error
        }
    }

    func reconnect(computerID: UUID) async throws -> BrowserRuntimeEndpoint {
        try await reconnect(computerID: computerID, interactiveAuthorization: false)
    }

    func authorizeReconnect(computerID: UUID) async throws -> BrowserRuntimeEndpoint {
        guard !Self.updatingComputerIDs.contains(computerID) else {
            throw LibraryError.invalid("A atualização deste computador está em andamento.")
        }
        if let pending = reconnectTasks[computerID] { _ = try? await pending.value }
        reconnectTasks.removeValue(forKey: computerID)
        return try await reconnect(computerID: computerID, interactiveAuthorization: true)
    }

    private func reconnect(computerID: UUID, interactiveAuthorization: Bool) async throws -> BrowserRuntimeEndpoint {
        guard pendingImageUpdate == nil, !imageUpdateRecoveryBlocked,
              !Self.updatingComputerIDs.contains(computerID) else {
            throw LibraryError.invalid("A atualização deste computador está em andamento.")
        }
        let epoch = Self.endpointEpochs[computerID, default: 0]
        let task: Task<BrowserRuntimeEndpoint, Error>
        if let pending = reconnectTasks[computerID] {
            task = pending
        } else {
            let service = service
            task = Task.detached(priority: .utility) {
                try await service.reconnectEndpoint(computerID: computerID,
                                                    interactiveAuthorization: interactiveAuthorization)
            }
            reconnectTasks[computerID] = task
        }
        do {
            let endpoint = try await task.value
            guard Self.endpointEpochs[computerID, default: 0] == epoch,
                  !Self.updatingComputerIDs.contains(computerID) else { throw BrowserComputerError.notReady }
            reconnectTasks.removeValue(forKey: computerID)
            endpoints[computerID] = endpoint
            tokenAuthorizationRequired.remove(computerID)
            errorText = nil
            return endpoint
        } catch {
            guard Self.endpointEpochs[computerID, default: 0] == epoch else {
                throw BrowserComputerError.notReady
            }
            reconnectTasks.removeValue(forKey: computerID)
            endpoints.removeValue(forKey: computerID)
            switch error {
            case BrowserComputerError.tokenAuthorizationRequired, BrowserComputerError.keychainTimedOut:
                tokenAuthorizationRequired.insert(computerID)
            default: break
            }
            errorText = error.localizedDescription
            throw error
        }
    }

    private func ensureAvailable(terminalID: UUID) throws {
        guard pendingImageUpdate == nil, !imageUpdateRecoveryBlocked,
              !busyComputerIDs.contains(terminalID), !Self.updatingTerminalIDs.contains(terminalID),
              !computers.contains(where: { $0.terminalID == terminalID &&
                  (busyComputerIDs.contains($0.id) || Self.updatingComputerIDs.contains($0.id)) }) else {
            throw LibraryError.invalid("Este computador já está em outra operação.")
        }
    }

    private func ensureAvailable(computerID: UUID) throws {
        guard pendingImageUpdate == nil, !imageUpdateRecoveryBlocked,
              !busyComputerIDs.contains(computerID), !Self.updatingComputerIDs.contains(computerID),
              !computers.contains(where: { $0.id == computerID && busyComputerIDs.contains($0.terminalID) }) else {
            throw LibraryError.invalid("Este computador já está em outra operação.")
        }
    }

    private func ensureAvailableForRecovery(_ pending: PendingBrowserImageUpdate) throws {
        guard !busyComputerIDs.contains(pending.computerID),
              !Self.updatingComputerIDs.contains(pending.computerID),
              !Self.updatingTerminalIDs.contains(pending.terminalID) else {
            throw LibraryError.invalid("Este computador já está em outra operação.")
        }
    }

    private func isCurrentNativeChild(_ owner: BrowserComputerOwner) -> Bool {
        guard case .nativeChild(let parentTerminalID, let runID) = owner else { return false }
        return NativeAgentMonitor.shared.isCurrentNativeChild(runID: runID,
            parentTerminalID: parentTerminalID, runtime: WorkspaceServices.terminalRuntime)
    }

    private func requireCurrentNativeChild(_ owner: BrowserComputerOwner) throws {
        guard isCurrentNativeChild(owner) else {
            throw LibraryError.invalid("Este subagente nativo não está mais ativo no terminal pai.")
        }
    }

    private func stopAndVerify(computerID: UUID) async -> Bool {
        let service = service
        do {
            return try await Task.detached(priority: .utility) {
                try service.stop(computerID: computerID)
                return try service.list().first(where: { $0.id == computerID })?.running == false
            }.value
        } catch { return false }
    }

    private func invalidateEndpoint(_ computerID: UUID) {
        Self.endpointEpochs[computerID, default: 0] &+= 1
        reconnectTasks.removeValue(forKey: computerID)?.cancel()
        endpoints.removeValue(forKey: computerID)
        tokenAuthorizationRequired.remove(computerID)
    }

    private func connectReady(computerID: UUID) async throws {
        var lastError: Error = BrowserComputerError.notReady
        for attempt in 0..<8 {
            do { _ = try await reconnect(computerID: computerID); return }
            catch {
                lastError = error
                if case BrowserComputerError.tokenAuthorizationRequired = error { throw error }
                if case BrowserComputerError.tokenAuthorizationDenied = error { throw error }
                if case BrowserComputerError.keychainTimedOut = error { throw error }
            }
            if attempt < 7 { try await Task.sleep(nanoseconds: 500_000_000) }
        }
        throw lastError
    }
}

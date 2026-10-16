import Foundation

public protocol ComputerControlTransport {
    var computerID: UUID { get }
    var generation: UInt64 { get }
    func health() async throws -> BrowserRuntimeHealth
    func grant(actorID: String, epoch: UInt64, paths: Set<ControlWritePath>) async throws -> BrowserRuntimeGrantedLease
    func revoke(actorID: String, epoch: UInt64) async throws -> BrowserRuntimeRevocationAck
    func navigate(to url: URL, lease: BrowserRuntimeGrantedLease) async throws -> URL
    func input(_ action: BrowserDesktopInput, lease: BrowserRuntimeGrantedLease) async throws -> BrowserDesktopInputResult
    func changeMode(_ mode: BrowserRuntimeMode, lease: BrowserRuntimeGrantedLease) async throws -> BrowserRuntimeHealth
    func refreshed(generation: UInt64) throws -> Self
}

public extension ComputerControlTransport {
    func navigate(to url: URL, lease: BrowserRuntimeGrantedLease) async throws -> URL {
        throw ComputerControlBridgeError.unsupportedNavigation
    }
}

extension BrowserRuntimeClient: ComputerControlTransport {
    public var computerID: UUID { endpoint.computerID }
    public var generation: UInt64 { endpoint.generation }
    public func refreshed(generation: UInt64) throws -> BrowserRuntimeClient {
        let next = try BrowserRuntimeEndpoint(baseURL: endpoint.baseURL, apiToken: endpoint.apiToken,
                                              computerID: endpoint.computerID, generation: generation)
        return BrowserRuntimeClient(endpoint: next, session: session)
    }
}

public enum ComputerControlBridgeError: Error, Equatable {
    case staleGeneration
    case noTicket
    case wrongGrant
    case writeDenied
    case runtimeGrantMismatch
    case revokeTimedOut
    case unsupportedNavigation
}

/// The public ticket has no credential and is deliberately not Codable.
public struct ComputerControlTicket: Equatable, Sendable {
    public let id: UUID
    public let grant: ControlGrant
    public let generation: UInt64
}

/// Serializes host-side takeover. A runtime token lives only inside this actor.
/// The broker and the container must both admit every controlled write.
public actor ComputerControlBridge<Transport: ComputerControlTransport> {
    public let computerID: UUID
    private let broker: ControlBroker
    private var transport: Transport
    private let revokeTimeout: TimeInterval
    private var activeTicket: ComputerControlTicket?
    private var activeLease: BrowserRuntimeGrantedLease?
    private var leaseOperationInProgress = false

    public init(broker: ControlBroker, transport: Transport, revokeTimeout: TimeInterval = 5) {
        self.broker = broker; self.transport = transport
        self.computerID = transport.computerID
        self.revokeTimeout = revokeTimeout
    }

    public func ticket() -> ComputerControlTicket? { activeTicket }
    public func currentGeneration() -> UInt64 { transport.generation }

    /// Explicit human action: revoke current writer, wait for exact ACK, then grant human.
    @discardableResult
    public func assumeHuman() async throws -> ComputerControlTicket {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        let health = try await verifiedHealth()
        if let ticket = activeTicket, ticket.grant.actor == .human,
           let live = health.activeLease, live.actorID == ticket.grant.actorID,
           live.epoch == ticket.grant.epoch {
            return ticket
        }
        if activeTicket == nil, let existing = await broker.currentGrant(computerID: computerID),
           existing.actor == .human {
            // An app/bridge restart cannot recover the old ephemeral token.
            try await broker.disconnect(computerID: computerID)
        }
        if await broker.currentGrant(computerID: computerID) == nil {
            // If an unknown lease survived a reconnect, revoke it on the runtime first.
            if let lease = health.activeLease {
                do { try await revokeRuntime(actorID: lease.actorID, epoch: lease.epoch) }
                catch { try? await broker.disconnect(computerID: computerID); throw error }
            }
            try? await broker.disconnect(computerID: computerID)
            let clean = try await verifiedHealth()
            guard clean.activeLease == nil else { throw ControlBrokerError.activeRuntimeLease }
            try await broker.reconcile(computerID: computerID, activeRuntimeLease: nil)
        } else if let current = await broker.currentGrant(computerID: computerID) {
            guard let live = health.activeLease, live.actorID == current.actorID,
                  live.epoch == current.epoch else {
                try await suspend(); throw ComputerControlBridgeError.wrongGrant
            }
        }
        let transition = try await broker.requestHuman(computerID: computerID)
        return try await complete(transition)
    }

    /// An agent may acquire an idle box or resume its own live lease. It never
    /// revokes a human, another run, or a lease whose token this bridge lost.
    @discardableResult
    public func assumeAgent(runID: UUID,
                            paths: Set<ControlWritePath> = [.navigate, .input, .mode]) async throws -> ComputerControlTicket {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        let health = try await verifiedHealth()
        let actor = ControlActor.agent(runID: runID)
        if let live = health.activeLease {
            guard let ticket = activeTicket, let lease = activeLease,
                  ticket.grant.actor == actor, ticket.grant.paths == paths,
                  ticket.generation == transport.generation,
                  await broker.currentGrant(computerID: computerID) == ticket.grant,
                  live.actorID == ticket.grant.actorID, live.epoch == ticket.grant.epoch,
                  lease.actorID == live.actorID, lease.epoch == live.epoch else {
                throw ControlBrokerError.activeRuntimeLease
            }
            return ticket
        }
        // Only an observed idle runtime can be reconciled. This clears a stale
        // broker grant without taking over any live control token.
        try await broker.disconnect(computerID: computerID)
        activeTicket = nil; activeLease = nil
        guard try await verifiedHealth().activeLease == nil else {
            throw ControlBrokerError.activeRuntimeLease
        }
        try await broker.reconcile(computerID: computerID, activeRuntimeLease: nil)
        let transition = try await broker.requestAgent(computerID: computerID, runID: runID, paths: paths)
        guard case .granted = transition else { throw ControlBrokerError.activeRuntimeLease }
        return try await complete(transition)
    }

    /// Release revokes the human lease and leaves the box without a writer.
    public func releaseHuman(_ ticket: ComputerControlTicket) async throws {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        guard ticket.grant.actor == .human else { throw ComputerControlBridgeError.wrongGrant }
        let lease = try await checkedLease(ticket)
        do {
            try await revokeRuntime(actorID: lease.actorID, epoch: lease.epoch)
            activeTicket = nil; activeLease = nil
            try await broker.disconnect(computerID: computerID)
            let health = try await verifiedHealth()
            try await broker.reconcile(computerID: computerID,
                                       activeRuntimeLease: health.activeLease.map { ControlRevocation(computerID: computerID, actorID: $0.actorID, epoch: $0.epoch) })
        } catch {
            try? await suspend()
            throw error
        }
    }

    /// Release only this run's own lease; a stale agent ticket cannot release a human.
    public func releaseAgent(_ ticket: ComputerControlTicket) async throws {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        guard ticket.grant.actor.kind == .agent else { throw ComputerControlBridgeError.wrongGrant }
        let lease = try await checkedLease(ticket)
        do {
            try await revokeRuntime(actorID: lease.actorID, epoch: lease.epoch)
            activeTicket = nil; activeLease = nil
            try await broker.disconnect(computerID: computerID)
            let health = try await verifiedHealth()
            try await broker.reconcile(computerID: computerID,
                                       activeRuntimeLease: health.activeLease.map { ControlRevocation(computerID: computerID, actorID: $0.actorID, epoch: $0.epoch) })
        } catch {
            try? await suspend()
            throw error
        }
    }

    /// A dropped stream/connection invalidates host input immediately and best-effort revokes runtime input.
    public func streamDisconnected() async {
        let lease = activeLease
        try? await suspend()
        if let lease { try? await revokeRuntime(actorID: lease.actorID, epoch: lease.epoch) }
    }

    public func input(_ action: BrowserDesktopInput, ticket: ComputerControlTicket) async throws {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        let lease = try await checkedLease(ticket, path: .input)
        do { _ = try await transport.input(action, lease: lease) }
        catch { await streamDisconnected(); throw error }
    }

    public func navigate(to url: URL, ticket: ComputerControlTicket) async throws -> URL {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        let lease = try await checkedLease(ticket, path: .navigate)
        do { return try await transport.navigate(to: url, lease: lease) }
        catch { await streamDisconnected(); throw error }
    }

    public func changeMode(_ mode: BrowserRuntimeMode, ticket: ComputerControlTicket) async throws -> BrowserRuntimeHealth {
        guard !leaseOperationInProgress else { throw ControlBrokerError.transitionInProgress }
        leaseOperationInProgress = true
        defer { leaseOperationInProgress = false }
        let lease = try await checkedLease(ticket, path: .mode)
        do {
            let health = try await transport.changeMode(mode, lease: lease)
            guard health.computerID == computerID, health.generation >= transport.generation else {
                throw ComputerControlBridgeError.staleGeneration
            }
            transport = try transport.refreshed(generation: health.generation)
            activeTicket = ComputerControlTicket(id: ticket.id, grant: ticket.grant, generation: health.generation)
            return health
        } catch { await streamDisconnected(); throw error }
    }

    private func checkedLease(_ ticket: ComputerControlTicket, path: ControlWritePath? = nil) async throws -> BrowserRuntimeGrantedLease {
        guard activeTicket?.id == ticket.id, activeTicket?.grant == ticket.grant,
              ticket.generation == transport.generation, let lease = activeLease else {
            throw ComputerControlBridgeError.noTicket
        }
        let authorized: Bool
        if let path {
            authorized = await broker.checkWrite(actor: ticket.grant.actor, computer: computerID,
                                                 epoch: ticket.grant.epoch, path: path)
        } else {
            authorized = await broker.currentGrant(computerID: computerID) == ticket.grant
        }
        guard authorized else {
            throw ComputerControlBridgeError.writeDenied
        }
        return lease
    }

    private func complete(_ transition: ControlTransition) async throws -> ComputerControlTicket {
        let grant: ControlGrant
        switch transition {
        case .granted(let direct): grant = direct
        case .revoking(let notice):
            do {
                try await revokeRuntime(actorID: notice.actorID, epoch: notice.epoch)
                guard case .granted(let confirmed) = try await broker.acknowledgeRevocation(notice) else {
                    throw ComputerControlBridgeError.wrongGrant
                }
                grant = confirmed
            } catch {
                try? await broker.expireRevocation(computerID: computerID)
                try? await suspend()
                throw error
            }
        }
        do {
            let lease = try await transport.grant(actorID: grant.actorID, epoch: grant.epoch, paths: grant.paths)
            guard lease.actorID == grant.actorID, lease.epoch == grant.epoch,
                  Set(lease.paths) == grant.paths, !lease.controlToken.isEmpty else {
                throw ComputerControlBridgeError.runtimeGrantMismatch
            }
            let ticket = ComputerControlTicket(id: UUID(), grant: grant, generation: transport.generation)
            activeLease = lease; activeTicket = ticket
            return ticket
        } catch { try? await suspend(); throw error }
    }

    private func verifiedHealth() async throws -> BrowserRuntimeHealth {
        do {
            let health = try await transport.health()
            guard health.computerID == computerID, health.generation == transport.generation else {
                throw ComputerControlBridgeError.staleGeneration
            }
            return health
        } catch { try? await suspend(); throw error }
    }

    private func revokeRuntime(actorID: String, epoch: UInt64) async throws {
        let transport = transport
        let seconds = revokeTimeout
        do {
            let ack = try await withThrowingTaskGroup(of: BrowserRuntimeRevocationAck.self) { group in
                group.addTask { try await transport.revoke(actorID: actorID, epoch: epoch) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(max(0.001, seconds) * 1_000_000_000))
                    throw ComputerControlBridgeError.revokeTimedOut
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
            guard ack.acknowledged, ack.revokedActorID == actorID, ack.revokedEpoch == epoch else {
                throw ComputerControlBridgeError.wrongGrant
            }
        } catch { throw error }
    }

    private func suspend() async throws {
        activeTicket = nil; activeLease = nil
        try await broker.disconnect(computerID: computerID)
    }
}

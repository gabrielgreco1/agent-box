import Foundation

/// These are the runtime's write routes. Screenshots and frame streams have no write grant.
public enum ControlWritePath: String, Codable, CaseIterable, Hashable, Sendable {
    case httpRequest = "http_request"
    case navigate, input, mode
}

public struct ControlActor: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case human, agent, nativeChild }
    public let kind: Kind
    public let runID: UUID?
    public let nativeChildID: String?

    public static let human = Self(kind: .human, runID: nil, nativeChildID: nil)
    public static func agent(runID: UUID) -> Self { Self(kind: .agent, runID: runID, nativeChildID: nil) }
    public static func child(parentRunID: UUID, nativeID: String) -> Self {
        Self(kind: .nativeChild, runID: parentRunID, nativeChildID: nativeID)
    }

    /// Opaque stable identity sent to the computer runtime. It is not an auth token.
    public var wireID: String {
        switch kind {
        case .human: return "human"
        case .agent: return "agent:\(runID?.uuidString ?? "invalid")"
        case .nativeChild: return "child:\(runID?.uuidString ?? "invalid"):\(nativeChildID ?? "invalid")"
        }
    }
}

public struct ControlGrant: Codable, Equatable, Sendable {
    public let computerID: UUID
    public let actor: ControlActor
    public let epoch: UInt64
    public let paths: Set<ControlWritePath>
    public let delegatedFrom: ControlActor?
    public let delegatedParentPaths: Set<ControlWritePath>?

    public var actorID: String { actor.wireID }
}

public struct ControlRevocation: Codable, Equatable, Sendable {
    public let computerID: UUID
    public let actorID: String
    public let epoch: UInt64
}

public enum ControlTransition: Equatable, Sendable {
    case granted(ControlGrant)
    case revoking(ControlRevocation)
}

public enum ControlBrokerError: Error, Equatable {
    case notReconciled
    case activeRuntimeLease
    case transitionInProgress
    case invalidActor
    case noGrant
    case invalidAcknowledgment
    case epochExhausted
}

/// One writer lease per computer. External routes must verify actor, epoch, path and
/// the runtime's ephemeral token as well; this in-process broker is not a host security boundary.
public actor ControlBroker {
    private enum Phase: String, Codable { case suspended, ready, revoking, maintenance }
    private struct Pending: Codable {
        let revocation: ControlRevocation
        let target: ControlActor
        let paths: Set<ControlWritePath>
        let delegatedFrom: ControlActor?
        let delegatedParentPaths: Set<ControlWritePath>?
    }
    private struct Box: Codable {
        var phase: Phase = .suspended
        var nextEpoch: UInt64 = 1
        var grant: ControlGrant?
        var pending: Pending?
        var lastAcknowledged: ControlRevocation?
        var maintenanceID: UUID?
    }
    private struct Store: Codable {
        var schemaVersion = 1
        var boxes: [UUID: Box] = [:]
    }

    public let url: URL
    private var store: Store

    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("ControlBroker.json")) throws {
        self.url = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: self.url.path) {
            let loaded = try JSONDecoder().decode(Store.self, from: Data(contentsOf: self.url))
            guard loaded.schemaVersion == 1 else { throw ControlBrokerError.notReconciled }
            // App restart loses runtime tokens. Nothing is writable until live reconciliation.
            var stopped = loaded
            for id in stopped.boxes.keys {
                stopped.boxes[id]?.phase = .suspended
                stopped.boxes[id]?.grant = nil
                stopped.boxes[id]?.pending = nil
                stopped.boxes[id]?.maintenanceID = nil
            }
            self.store = stopped
        } else {
            self.store = Store()
        }
    }

    public func currentGrant(computerID: UUID) -> ControlGrant? {
        let box = store.boxes[computerID]
        return box?.phase == .ready ? box?.grant : nil
    }

    /// Caller must inspect the live runtime after connection. A stale lease must be
    /// revoked there before this method is called with `nil`.
    public func reconcile(computerID: UUID, activeRuntimeLease: ControlRevocation?) throws {
        guard activeRuntimeLease == nil else { throw ControlBrokerError.activeRuntimeLease }
        var next = store
        var box = next.boxes[computerID] ?? Box()
        guard box.phase == .suspended else { throw ControlBrokerError.transitionInProgress }
        box.phase = .ready; box.grant = nil; box.pending = nil
        next.boxes[computerID] = box
        try persist(next); store = next
    }

    /// A disconnected runtime cannot accept broker writes. Reconcile before any new grant.
    public func disconnect(computerID: UUID) throws {
        var next = store
        var box = next.boxes[computerID] ?? Box()
        guard box.phase != .maintenance else { throw ControlBrokerError.transitionInProgress }
        box.phase = .suspended; box.grant = nil; box.pending = nil
        next.boxes[computerID] = box
        try persist(next); store = next
    }

    /// Reserve an idle box for a host operation such as stopping its container.
    /// No other bridge can reconcile or grant it until the exact token ends.
    public func beginIdleMaintenance(computerID: UUID) throws -> UUID {
        var next = store
        var box = next.boxes[computerID] ?? Box()
        guard box.phase == .ready || box.phase == .suspended else {
            throw ControlBrokerError.transitionInProgress
        }
        guard box.grant == nil, box.pending == nil else {
            throw ControlBrokerError.activeRuntimeLease
        }
        let id = UUID()
        box.phase = .maintenance; box.maintenanceID = id
        next.boxes[computerID] = box
        try persist(next); store = next
        return id
    }

    /// End a reservation suspended. A future writer must inspect runtime
    /// health and reconcile again before it can receive a fresh token.
    public func endIdleMaintenance(computerID: UUID, reservationID: UUID) throws {
        var next = store
        guard var box = next.boxes[computerID], box.phase == .maintenance,
              box.maintenanceID == reservationID else {
            throw ControlBrokerError.invalidAcknowledgment
        }
        box.phase = .suspended; box.maintenanceID = nil
        next.boxes[computerID] = box
        try persist(next); store = next
    }

    @discardableResult
    public func requestHuman(computerID: UUID,
                             paths: Set<ControlWritePath> = Set(ControlWritePath.allCases)) throws -> ControlTransition {
        try request(computerID: computerID, target: .human, paths: paths, delegatedFrom: nil, delegatedParentPaths: nil)
    }

    @discardableResult
    public func requestAgent(computerID: UUID, runID: UUID,
                             paths: Set<ControlWritePath> = Set(ControlWritePath.allCases)) throws -> ControlTransition {
        try request(computerID: computerID, target: .agent(runID: runID), paths: paths, delegatedFrom: nil, delegatedParentPaths: nil)
    }

    /// Native child identity must already be verified by an event adapter/registry.
    @discardableResult
    public func requestChild(computerID: UUID, parentRunID: UUID, nativeChildID: String,
                             paths: Set<ControlWritePath>) throws -> ControlTransition {
        guard !nativeChildID.isEmpty, let parent = store.boxes[computerID]?.grant,
              parent.actor == .agent(runID: parentRunID), paths.isSubset(of: parent.paths) else {
            throw ControlBrokerError.invalidActor
        }
        return try request(computerID: computerID,
                           target: .child(parentRunID: parentRunID, nativeID: nativeChildID),
                           paths: paths, delegatedFrom: parent.actor, delegatedParentPaths: parent.paths)
    }

    /// A host-verified native child can control its own box without a parent
    /// lease on that box. The caller supplies the parent's allowed capabilities;
    /// this broker does not authenticate the native child or its box ownership.
    @discardableResult
    public func requestIndependentChild(computerID: UUID, parentRunID: UUID, nativeChildID: String,
                                        paths: Set<ControlWritePath>,
                                        allowedParentPaths: Set<ControlWritePath>) throws -> ControlTransition {
        guard !nativeChildID.isEmpty, !paths.isEmpty,
              paths.isSubset(of: allowedParentPaths) else { throw ControlBrokerError.invalidActor }
        let child = ControlActor.child(parentRunID: parentRunID, nativeID: nativeChildID)
        if let current = store.boxes[computerID]?.grant {
            guard current.actor == child, current.delegatedFrom == nil,
                  current.delegatedParentPaths == nil, current.paths == paths else {
                throw ControlBrokerError.activeRuntimeLease
            }
        }
        // `request` is only called for an idle box or an exact independent-child
        // retry. It must never initiate revocation of another controller.
        return try request(computerID: computerID, target: child, paths: paths,
                           delegatedFrom: nil, delegatedParentPaths: nil)
    }

    /// Takes control back from a child only after the child runtime lease is revoked and ACKed.
    @discardableResult
    public func revokeChild(computerID: UUID) throws -> ControlTransition {
        guard let current = store.boxes[computerID]?.grant,
              current.actor.kind == .nativeChild,
              let parent = current.delegatedFrom else { throw ControlBrokerError.invalidActor }
        return try request(computerID: computerID, target: parent,
                           paths: current.delegatedParentPaths ?? current.paths,
                           delegatedFrom: nil, delegatedParentPaths: nil)
    }

    @discardableResult
    public func acknowledgeRevocation(_ acknowledgment: ControlRevocation) throws -> ControlTransition {
        var next = store
        guard var box = next.boxes[acknowledgment.computerID] else { throw ControlBrokerError.invalidAcknowledgment }
        if box.phase == .ready, box.lastAcknowledged == acknowledgment, let grant = box.grant {
            return .granted(grant) // Duplicate ACK is idempotent.
        }
        guard box.phase == .revoking, let pending = box.pending,
              pending.revocation == acknowledgment else { throw ControlBrokerError.invalidAcknowledgment }
        let grant = try issueGrant(computerID: acknowledgment.computerID, actor: pending.target,
                                   paths: pending.paths, delegatedFrom: pending.delegatedFrom,
                                   delegatedParentPaths: pending.delegatedParentPaths, box: &box)
        box.phase = .ready; box.pending = nil; box.lastAcknowledged = acknowledgment
        next.boxes[acknowledgment.computerID] = box
        try persist(next); store = next
        return .granted(grant)
    }

    /// A missing ACK never becomes a human or agent grant. Timeout forces reconciliation.
    public func expireRevocation(computerID: UUID) throws {
        guard store.boxes[computerID]?.phase == .revoking else { return }
        try disconnect(computerID: computerID)
    }

    public func checkWrite(actor: ControlActor, computer: UUID, epoch: UInt64,
                           path: ControlWritePath) -> Bool {
        guard let box = store.boxes[computer], box.phase == .ready,
              let grant = box.grant else { return false }
        return grant.actor == actor && grant.epoch == epoch && grant.paths.contains(path)
    }

    private func request(computerID: UUID, target: ControlActor, paths: Set<ControlWritePath>,
                         delegatedFrom: ControlActor?, delegatedParentPaths: Set<ControlWritePath>?) throws -> ControlTransition {
        guard !paths.isEmpty, target.kind == .human || target.runID != nil else {
            throw ControlBrokerError.invalidActor
        }
        var next = store
        guard var box = next.boxes[computerID], box.phase != .suspended else {
            throw ControlBrokerError.notReconciled
        }
        guard box.phase == .ready else { throw ControlBrokerError.transitionInProgress }
        if let current = box.grant {
            if current.actor == target && current.paths == paths { return .granted(current) }
            let notice = ControlRevocation(computerID: computerID, actorID: current.actorID, epoch: current.epoch)
            box.phase = .revoking
            box.grant = nil // Deny old epoch immediately in the broker.
            box.pending = Pending(revocation: notice, target: target, paths: paths,
                                  delegatedFrom: delegatedFrom, delegatedParentPaths: delegatedParentPaths)
            next.boxes[computerID] = box
            try persist(next); store = next
            return .revoking(notice)
        }
        let grant = try issueGrant(computerID: computerID, actor: target,
                                   paths: paths, delegatedFrom: delegatedFrom,
                                   delegatedParentPaths: delegatedParentPaths, box: &box)
        next.boxes[computerID] = box
        try persist(next); store = next
        return .granted(grant)
    }

    private func issueGrant(computerID: UUID, actor: ControlActor, paths: Set<ControlWritePath>,
                            delegatedFrom: ControlActor?, delegatedParentPaths: Set<ControlWritePath>?,
                            box: inout Box) throws -> ControlGrant {
        guard box.nextEpoch < UInt64.max else { throw ControlBrokerError.epochExhausted }
        let grant = ControlGrant(computerID: computerID, actor: actor, epoch: box.nextEpoch,
                                 paths: paths, delegatedFrom: delegatedFrom,
                                 delegatedParentPaths: delegatedParentPaths)
        box.nextEpoch += 1; box.grant = grant
        return grant
    }

    private func persist(_ next: Store) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

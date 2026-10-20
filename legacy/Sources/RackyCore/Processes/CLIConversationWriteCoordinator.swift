import Foundation

public struct CLIConversationWriteTicket: Equatable, Sendable {
    public let identity: CLIConversationIdentity
    public let reservationID: UUID

    fileprivate init(identity: CLIConversationIdentity, reservationID: UUID) {
        self.identity = identity
        self.reservationID = reservationID
    }
}

public enum CLIConversationWriteError: Error, Equatable, LocalizedError {
    case activeExternalConversation
    case externalClosureUnconfirmed
    case alreadyReserved

    public var errorDescription: String? {
        switch self {
        case .activeExternalConversation:
            "Esta conversa ainda aparece ativa na CLI. Encerre o outro processo antes de retomá-la."
        case .externalClosureUnconfirmed:
            "Confirme que a conversa externa foi encerrada antes de abrir outra sessão de escrita."
        case .alreadyReserved:
            "Esta conversa já está aberta em outro terminal do Racky."
        }
    }
}

/// App-wide in-memory writer admission. It prevents duplicate writers inside one
/// Racky process but cannot inspect or lock an external CLI's own sessions.
/// The caller must refresh external activity immediately before reservation.
public final class CLIConversationWriteCoordinator: @unchecked Sendable {
    public static let shared = CLIConversationWriteCoordinator()

    private let lock = NSLock()
    private var reservations: [CLIConversationIdentity: UUID] = [:]

    public init() {}

    public func reserve(candidate: CLIConversationCandidate,
                        externalClosedAcknowledged: Bool = false) throws -> CLIConversationWriteTicket {
        lock.lock()
        defer { lock.unlock() }
        if reservations[candidate.identity] != nil { throw CLIConversationWriteError.alreadyReserved }
        if candidate.originIsExternal && candidate.activity == .active {
            throw CLIConversationWriteError.activeExternalConversation
        }
        if candidate.originIsExternal && !externalClosedAcknowledged {
            throw CLIConversationWriteError.externalClosureUnconfirmed
        }
        let ticket = CLIConversationWriteTicket(identity: candidate.identity, reservationID: UUID())
        reservations[candidate.identity] = ticket.reservationID
        return ticket
    }

    /// Only the holder of the exact ticket can release its reservation. A stale
    /// process-exit callback cannot remove a newer terminal's reservation.
    @discardableResult
    public func release(ticket: CLIConversationWriteTicket) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard reservations[ticket.identity] == ticket.reservationID else { return false }
        reservations.removeValue(forKey: ticket.identity)
        return true
    }

    public func isReserved(identity: CLIConversationIdentity) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return reservations[identity] != nil
    }
}

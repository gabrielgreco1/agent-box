import Foundation

/// A reviewed destination. The container keeps its immutable terminal ownership.
/// This describes attachment, not an agent control grant or proof of browsing.
public struct ScrapingLaunchTarget: Equatable, Sendable {
    public let assignment: ScrapingBoxAssignment
    public let sessionID: UUID
    public let terminal: TerminalRecord

    public init(assignment: ScrapingBoxAssignment, sessionID: UUID, terminal: TerminalRecord) {
        self.assignment = assignment
        self.sessionID = sessionID
        self.terminal = terminal
    }

    public func validate(currentTerminal: TerminalRecord?, currentAssignment: ScrapingBoxAssignment?,
                         agentID: UUID, skillIDs: [UUID]) throws {
        guard currentTerminal == terminal, currentAssignment == assignment,
              terminal.id == assignment.terminalID,
              agentID == assignment.defaultAgentDefinitionID,
              skillIDs.contains(assignment.skillID) else {
            throw LibraryError.invalid("O terminal, a box ou a skill de scraping mudou. Abra novamente a revisão a partir do computador.")
        }
    }

    /// Build a candidate without mutating the workspace if any precondition fails.
    public func replacingTerminal(in workspace: WorkspaceSnapshot, with replacement: TerminalRecord) throws -> WorkspaceSnapshot {
        guard replacement.id == terminal.id, replacement.cwd == terminal.cwd,
              replacement.agentDefinitionID == assignment.defaultAgentDefinitionID,
              let sessionIndex = workspace.sessions.firstIndex(where: { $0.id == sessionID }),
              let terminalIndex = workspace.sessions[sessionIndex].terminals.firstIndex(where: { $0.id == terminal.id }),
              workspace.sessions[sessionIndex].terminals[terminalIndex] == terminal else {
            throw LibraryError.invalid("O destino do lançamento mudou. Nenhum terminal foi substituído.")
        }
        var next = workspace
        var updated = replacement
        updated.title = terminal.title
        updated.createdAt = terminal.createdAt
        next.sessions[sessionIndex].terminals[terminalIndex] = updated
        next.selectedSessionID = sessionID
        next.updateLayout(for: sessionID) { $0.show(terminal.id) }
        return next
    }
}

import XCTest
@testable import AgentBoxCore

final class ScrapingLaunchTargetTests: XCTestCase {
    func testReplacementKeepsDestinationIdentityAndOtherWorkspaceState() throws {
        let agentID = UUID()
        let terminal = TerminalRecord(title: "Scraping box", provider: .shell, cwd: "/tmp",
                                      createdAt: Date(timeIntervalSince1970: 100))
        let otherTerminal = TerminalRecord(title: "Other", provider: .codex, cwd: "/tmp")
        let otherSessionTerminal = TerminalRecord(title: "Separate", provider: .shell, cwd: "/tmp")
        let session = WorkspaceSession(title: "Scraping", terminals: [terminal, otherTerminal])
        let otherSession = WorkspaceSession(title: "Separate", terminals: [otherSessionTerminal])
        var layout = WorkspaceLayout(sessionID: session.id, root: .terminal(otherTerminal.id),
                                     focusedTerminalID: otherTerminal.id)
        layout.split(terminal.id, beside: otherTerminal.id, axis: .horizontal)
        layout.show(otherTerminal.id)
        let otherLayout = WorkspaceLayout(sessionID: otherSession.id, root: .terminal(otherSessionTerminal.id),
                                          focusedTerminalID: otherSessionTerminal.id)
        let original = WorkspaceSnapshot(sessions: [session, otherSession], layouts: [layout, otherLayout],
                                         selectedSessionID: otherSession.id, sidebarWidth: 370,
                                         sidebarCollapsed: true)
        let assignment = ScrapingBoxAssignment(computerID: UUID(), terminalID: terminal.id,
                                               defaultAgentDefinitionID: agentID, skillID: UUID())
        let target = ScrapingLaunchTarget(assignment: assignment, sessionID: session.id, terminal: terminal)
        let replacement = TerminalRecord(id: terminal.id, title: "New launch title", provider: .claude,
                                         cwd: terminal.cwd, arguments: ["--append-system-prompt-file", "/tmp/new-context.md"],
                                         createdAt: Date(timeIntervalSince1970: 200), agentDefinitionID: agentID)

        let updated = try target.replacingTerminal(in: original, with: replacement)
        XCTAssertEqual(updated.sessions[0].terminals[0].id, terminal.id)
        XCTAssertEqual(updated.sessions[0].terminals[0].title, terminal.title)
        XCTAssertEqual(updated.sessions[0].terminals[0].createdAt, terminal.createdAt)
        XCTAssertEqual(updated.sessions[0].terminals[0].provider, .claude)
        XCTAssertEqual(updated.sessions[0].terminals[0].arguments, replacement.arguments)
        XCTAssertEqual(updated.sessions[0].terminals[0].agentDefinitionID, agentID)
        XCTAssertEqual(updated.sessions[0].terminals[1], otherTerminal)
        XCTAssertEqual(updated.sessions[1], otherSession)
        XCTAssertEqual(updated.layouts[1], otherLayout)
        XCTAssertEqual(Set(updated.layouts[0].visibleTerminalIDs), Set([terminal.id, otherTerminal.id]))
        XCTAssertEqual(updated.layouts[0].focusedTerminalID, terminal.id)
        XCTAssertEqual(updated.selectedSessionID, session.id)
        XCTAssertEqual(updated.sidebarWidth, original.sidebarWidth)
        XCTAssertEqual(updated.sidebarCollapsed, original.sidebarCollapsed)
        XCTAssertEqual(original.sessions[0].terminals[0], terminal)
        XCTAssertEqual(original.layouts[0], layout)
        XCTAssertEqual(original.selectedSessionID, otherSession.id)
    }

    func testReplacementRejectsMissingOrChangedDestinationAndInvalidReplacement() throws {
        let agentID = UUID()
        let terminal = TerminalRecord(title: "Scraping box", provider: .shell, cwd: "/tmp")
        let session = WorkspaceSession(title: "Scraping", terminals: [terminal])
        let workspace = WorkspaceSnapshot(sessions: [session])
        let assignment = ScrapingBoxAssignment(computerID: UUID(), terminalID: terminal.id,
                                               defaultAgentDefinitionID: agentID, skillID: UUID())
        let target = ScrapingLaunchTarget(assignment: assignment, sessionID: session.id, terminal: terminal)
        let valid = TerminalRecord(id: terminal.id, title: "Claude", provider: .claude,
                                   cwd: terminal.cwd, agentDefinitionID: agentID)

        var missing = workspace
        missing.sessions[0].terminals = []
        XCTAssertThrowsError(try target.replacingTerminal(in: missing, with: valid))
        var changed = workspace
        changed.sessions[0].terminals[0].title = "Changed after review"
        XCTAssertThrowsError(try target.replacingTerminal(in: changed, with: valid))
        XCTAssertThrowsError(try target.replacingTerminal(in: workspace,
            with: TerminalRecord(id: UUID(), title: valid.title, provider: valid.provider,
                                 cwd: valid.cwd, agentDefinitionID: agentID)))
        XCTAssertThrowsError(try target.replacingTerminal(in: workspace,
            with: TerminalRecord(id: terminal.id, title: valid.title, provider: valid.provider,
                                 cwd: "/different", agentDefinitionID: agentID)))
        XCTAssertThrowsError(try target.replacingTerminal(in: workspace,
            with: TerminalRecord(id: terminal.id, title: valid.title, provider: valid.provider,
                                 cwd: valid.cwd, agentDefinitionID: UUID())))
        XCTAssertEqual(workspace.sessions[0].terminals, [terminal])
    }

    func testValidateRequiresExactReviewedAssignmentTerminalAgentAndSkill() throws {
        let agentID = UUID()
        let skillID = UUID()
        let terminal = TerminalRecord(title: "Scraping box", provider: .shell, cwd: "/tmp")
        let assignment = ScrapingBoxAssignment(computerID: UUID(), terminalID: terminal.id,
                                               defaultAgentDefinitionID: agentID, skillID: skillID)
        let target = ScrapingLaunchTarget(assignment: assignment, sessionID: UUID(), terminal: terminal)

        XCTAssertNoThrow(try target.validate(currentTerminal: terminal, currentAssignment: assignment,
                                             agentID: agentID, skillIDs: [UUID(), skillID]))
        XCTAssertThrowsError(try target.validate(currentTerminal: nil, currentAssignment: assignment,
                                                  agentID: agentID, skillIDs: [skillID]))
        var changedTerminal = terminal
        changedTerminal.title = "Changed"
        XCTAssertThrowsError(try target.validate(currentTerminal: changedTerminal, currentAssignment: assignment,
                                                  agentID: agentID, skillIDs: [skillID]))
        XCTAssertThrowsError(try target.validate(currentTerminal: terminal, currentAssignment: nil,
                                                  agentID: agentID, skillIDs: [skillID]))
        let changedAssignment = ScrapingBoxAssignment(computerID: assignment.computerID,
                                                       terminalID: assignment.terminalID,
                                                       defaultAgentDefinitionID: assignment.defaultAgentDefinitionID,
                                                       skillID: UUID(), createdAt: assignment.createdAt)
        XCTAssertThrowsError(try target.validate(currentTerminal: terminal, currentAssignment: changedAssignment,
                                                  agentID: agentID, skillIDs: [skillID]))
        XCTAssertThrowsError(try target.validate(currentTerminal: terminal, currentAssignment: assignment,
                                                  agentID: UUID(), skillIDs: [skillID]))
        XCTAssertThrowsError(try target.validate(currentTerminal: terminal, currentAssignment: assignment,
                                                  agentID: agentID, skillIDs: [UUID()]))
        let mismatchedAssignment = ScrapingBoxAssignment(computerID: assignment.computerID,
                                                          terminalID: UUID(), defaultAgentDefinitionID: agentID,
                                                          skillID: skillID, createdAt: assignment.createdAt)
        let mismatchedTarget = ScrapingLaunchTarget(assignment: mismatchedAssignment, sessionID: UUID(),
                                                   terminal: terminal)
        XCTAssertThrowsError(try mismatchedTarget.validate(currentTerminal: terminal,
                                                            currentAssignment: mismatchedAssignment,
                                                            agentID: agentID, skillIDs: [skillID]))
    }
}

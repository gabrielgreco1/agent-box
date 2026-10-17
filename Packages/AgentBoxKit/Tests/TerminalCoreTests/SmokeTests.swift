import Testing
@testable import AgentBoxTerminalCore

@Suite struct TerminalCoreTestsSmoke {
    @Test func moduleLinks() {
        #expect(AgentBoxTerminalCoreModule.name == "AgentBoxTerminalCore")
    }
}

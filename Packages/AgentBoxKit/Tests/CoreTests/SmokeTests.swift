import Testing
@testable import AgentBoxCore

@Suite struct CoreTestsSmoke {
    @Test func moduleLinks() {
        #expect(AgentBoxCoreModule.name == "AgentBoxCore")
    }
}

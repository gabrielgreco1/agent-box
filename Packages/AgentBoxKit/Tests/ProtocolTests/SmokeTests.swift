import Testing
@testable import AgentBoxProtocol

@Suite struct ProtocolTestsSmoke {
    @Test func moduleLinks() {
        #expect(AgentBoxProtocolModule.name == "AgentBoxProtocol")
    }
}

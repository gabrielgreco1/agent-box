import Testing
@testable import AgentBoxStore

@Suite struct StoreTestsSmoke {
    @Test func moduleLinks() {
        #expect(AgentBoxStoreModule.name == "AgentBoxStore")
    }
}

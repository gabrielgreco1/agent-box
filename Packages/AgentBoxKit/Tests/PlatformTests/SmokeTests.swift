import Testing
@testable import AgentBoxPlatform

@Suite struct PlatformTestsSmoke {
    @Test func moduleLinks() {
        #expect(AgentBoxPlatformModule.name == "AgentBoxPlatform")
    }
}

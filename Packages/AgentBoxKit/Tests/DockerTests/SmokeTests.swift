import Testing
@testable import AgentBoxDocker

@Suite struct DockerTestsSmoke {
    @Test func moduleLinks() {
        #expect(AgentBoxDockerModule.name == "AgentBoxDocker")
    }
}

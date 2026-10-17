import Testing
@testable import AgentBoxPlatform
@testable import AgentBoxProtocol
@testable import AgentBoxTerminalCore

@Suite struct DaemonSmoke {
    @Test func daemonDependenciesLink() {
        #expect(AgentBoxProtocolModule.name == "AgentBoxProtocol")
        #expect(AgentBoxPlatformModule.name == "AgentBoxPlatform")
        #expect(AgentBoxTerminalCoreModule.name == "AgentBoxTerminalCore")
    }
}

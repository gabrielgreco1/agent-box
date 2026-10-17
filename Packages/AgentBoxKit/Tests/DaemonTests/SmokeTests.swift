import Testing
@testable import AgentBoxPlatform
@testable import AgentBoxProtocol
@testable import AgentBoxTerminalCore

@Suite(.tags(.integration), .serialized, .timeLimit(.minutes(1))) struct DaemonSmoke {
    @Test func daemonDependenciesLink() {
        #expect(AgentBoxProtocolModule.name == "AgentBoxProtocol")
        #expect(AgentBoxPlatformModule.name == "AgentBoxPlatform")
        #expect(AgentBoxTerminalCoreModule.name == "AgentBoxTerminalCore")
    }
}

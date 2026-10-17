import Testing
@testable import AgentBoxPlatform

@Suite struct LogFacadeTests {
    @Test func subsystemsMatchCanonicalIdentifiers() {
        #expect(LogFacade.Subsystem.app.rawValue == "app.agentbox")
        #expect(LogFacade.Subsystem.ptyd.rawValue == "app.agentbox.ptyd")
        #expect(LogFacade.Subsystem.cli.rawValue == "app.agentbox.cli")
    }

    @Test func facadeKeepsCategory() {
        let log = LogFacade(.app, category: "lifecycle")
        #expect(log.category == "lifecycle")
        log.info("smoke")
    }
}

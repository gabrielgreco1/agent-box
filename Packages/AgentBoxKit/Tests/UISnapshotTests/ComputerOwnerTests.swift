import Testing

@testable import AgentBoxUI

/// `agentbox.owner` dos containers: o app do dono segue com `agent-box`; um `AGENTBOX_HOME` isolado (testes, e2e) nunca o compartilha.
@MainActor
@Suite struct ComputerOwnerTests {
    @Test func productionKeepsTheDefaultOwner() {
        #expect(AppEnvironment.computerOwner([:]) == "agent-box")
        #expect(AppEnvironment.computerOwner(["AGENTBOX_HOME": ""]) == "agent-box")
    }

    @Test func isolatedHomeGetsItsOwnStableOwner() {
        let a = AppEnvironment.computerOwner(["AGENTBOX_HOME": "/tmp/abe2e-a"])
        let b = AppEnvironment.computerOwner(["AGENTBOX_HOME": "/tmp/abe2e-b"])
        #expect(a.hasPrefix("agent-box-") && a != "agent-box")
        #expect(a != b)
        #expect(a == AppEnvironment.computerOwner(["AGENTBOX_HOME": "/tmp/abe2e-a"]))
    }
}

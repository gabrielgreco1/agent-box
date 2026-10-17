import Testing
@testable import AgentBoxDesignSystem
@testable import AgentBoxUI

@Suite(.offscreenAppKit) struct UISnapshotSmoke {
    @Test func uiModulesLink() {
        #expect(AgentBoxUIModule.name == "AgentBoxUI")
        #expect(AgentBoxDesignSystemModule.name == "AgentBoxDesignSystem")
    }
}

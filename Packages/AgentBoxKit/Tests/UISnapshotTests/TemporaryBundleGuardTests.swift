import Foundation
import Testing

@testable import AgentBoxUI

/// F33: uma build de teste em `/private/tmp` virou o daemon oficial do launchd do dono. Build temporária nunca registra.
struct TemporaryBundleGuardTests {
    @Test func temporaryBundlesNeverRegisterTheLaunchAgent() {
        #expect(AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/private/tmp/claude-501/abview2/build/AgentBox/Agent Box.app")))
        #expect(AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/tmp/x/Agent Box.app")))
        #expect(AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Agent Box.app")))
        #expect(!AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/Applications/Agent Box.app")))
        #expect(!AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/Users/someone/orca/workspaces/agent-box/otter/build/AgentBox/Agent Box.app")))
    }
}

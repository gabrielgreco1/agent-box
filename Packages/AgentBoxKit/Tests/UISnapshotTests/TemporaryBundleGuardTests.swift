import Foundation
import Testing

@testable import AgentBoxUI

/// F33: uma build de teste em `/private/tmp` virou o daemon oficial do launchd do dono. Build temporária nunca registra.
struct TemporaryBundleGuardTests {
    @Test func temporaryBundlesNeverRegisterTheLaunchAgent() {
        #expect(AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/private/tmp/claude-501/abview2/build/AgentBox/Racky.app")))
        #expect(AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/tmp/x/Racky.app")))
        #expect(AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Racky.app")))
        #expect(!AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/Applications/Racky.app")))
        #expect(!AppEnvironment.isTemporaryBundle(URL(fileURLWithPath: "/Users/someone/orca/workspaces/agent-box/otter/build/AgentBox/Racky.app")))
    }

    /// Só a cópia instalada registra: build de worktree, DerivedData e `build/` usam o daemon filho.
    @Test func onlyInstalledBundlesRegisterTheLaunchAgent() {
        let home = "/Users/someone"
        #expect(AppEnvironment.isInstalledBundle(URL(fileURLWithPath: "/Applications/Racky.app"), home: home))
        #expect(AppEnvironment.isInstalledBundle(URL(fileURLWithPath: "/Users/someone/Applications/Racky.app"), home: home))
        #expect(!AppEnvironment.isInstalledBundle(URL(fileURLWithPath: "/Users/someone/orca/workspaces/agent-box/otter/build/AgentBox/Racky.app"), home: home))
        #expect(!AppEnvironment.isInstalledBundle(
            URL(fileURLWithPath: "/Users/someone/Library/Developer/Xcode/DerivedData/AgentBox-x/Build/Products/Debug/Racky.app"), home: home))
        #expect(!AppEnvironment.isInstalledBundle(URL(fileURLWithPath: "/Applications/Dev/Racky.app"), home: home))
    }
}

import Foundation
import Testing

@testable import RackyStore

@Suite struct LegacyDefaultsMigrationTests {
    private func suite() -> (UserDefaults, String) {
        let name = "racky.test.defaults.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func copiesOldValuesWithoutOverwritingNewOnesAndRunsOnce() {
        let (legacy, legacyName) = suite()
        let (target, targetName) = suite()
        defer { legacy.removePersistentDomain(forName: legacyName); target.removePersistentDomain(forName: targetName) }
        legacy.set("frame-a", forKey: "NSWindow Frame workspace")
        legacy.set("old", forKey: "shared")
        target.set("new", forKey: "shared")

        let copied = LegacyDefaultsMigration.migrate(legacyDomain: legacyName, legacy: legacy, targetDomain: targetName, target: target)
        #expect(copied == 1)
        #expect(target.string(forKey: "NSWindow Frame workspace") == "frame-a")
        #expect(target.string(forKey: "shared") == "new")
        #expect(legacy.string(forKey: "NSWindow Frame workspace") == "frame-a", "o domínio antigo nunca é alterado")

        legacy.set("late", forKey: "added-later")
        #expect(LegacyDefaultsMigration.migrate(legacyDomain: legacyName, legacy: legacy, targetDomain: targetName, target: target) == 0)
        #expect(target.string(forKey: "added-later") == nil)
    }
}

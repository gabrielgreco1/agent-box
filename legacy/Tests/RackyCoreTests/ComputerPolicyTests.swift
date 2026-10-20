import XCTest
@testable import RackyCore

final class ComputerPolicyTests:XCTestCase {
    func testChildCannotExpandAncestorAndUnrelatedScopeIsIgnored() throws {
        let session=UUID(), terminal=UUID(), agent=UUID()
        let policy=ComputerPolicy(creation:.automatic,limits:.init(cpus:4,memoryMiB:4096,maxComputers:4),overrides:[
            .init(scope:.session,scopeID:session.uuidString,creation:.manual,limits:.init(cpus:2,memoryMiB:2048,maxComputers:2),networkAllowed:false),
            .init(scope:.terminal,scopeID:terminal.uuidString,creation:.automatic,limits:.init(cpus:8,memoryMiB:8192,maxComputers:8),networkAllowed:true),
            .init(scope:.agent,scopeID:agent.uuidString,modePreference:.alwaysGraphical),
            .init(scope:.project,scopeID:"unrelated",creation:.disabled)
        ])
        let effective=try policy.effective(for:.init(terminalID:terminal,sessionID:session,agentID:agent))
        XCTAssertEqual(effective.creation,.manual)
        XCTAssertEqual(effective.limits,.init(cpus:2,memoryMiB:2048,maxComputers:2))
        XCTAssertFalse(effective.networkAllowed)
        XCTAssertEqual(effective.modePreference,.alwaysGraphical)
        XCTAssertEqual(effective.sources.count,4)
    }
    func testDisabledGlobalCannotBeExpanded() throws {
        let terminal=UUID()
        let policy=ComputerPolicy(overrides:[.init(scope:.terminal,scopeID:terminal.uuidString,creation:.automatic)])
        XCTAssertEqual(try policy.effective(for:.init(terminalID:terminal)).creation,.disabled)
    }
    func testInvalidSavePreservesPreviousAndV1MigrationBacksUp() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent("policy.json"), store=ComputerPolicyStore(fileURL:directory.appendingPathComponent("policy.json"))
        let legacy=Data(#"{"schemaVersion":1,"creation":"manual","modePreference":"adaptive"}"#.utf8)
        try legacy.write(to:url)
        let migrated=try store.load()
        XCTAssertEqual(migrated.schemaVersion,2)
        XCTAssertEqual(migrated.creation,.manual)
        try store.save(migrated)
        XCTAssertEqual(try Data(contentsOf:url.appendingPathExtension("v1.backup")),legacy)
        let saved=try Data(contentsOf:url)
        var invalid=migrated; invalid.limits.cpus = .nan
        XCTAssertThrowsError(try store.save(invalid))
        XCTAssertEqual(try Data(contentsOf:url),saved)
    }
    func testScopesAreValidatedAndGraphicalCannotFallBack() throws {
        XCTAssertThrowsError(try ComputerPolicy(overrides:[.init(scope:.terminal,scopeID:"not-id")]).validate())
        let id=UUID()
        let policy=ComputerPolicy(creation:.manual,modePreference:.alwaysGraphical,overrides:[.init(scope:.terminal,scopeID:id.uuidString,modePreference:.adaptive)])
        XCTAssertEqual(try policy.effective(for:.init(terminalID:id)).modePreference,.alwaysGraphical)
    }
}

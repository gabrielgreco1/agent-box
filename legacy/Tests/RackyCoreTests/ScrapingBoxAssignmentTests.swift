import XCTest
@testable import RackyCore

final class ScrapingBoxAssignmentTests: XCTestCase {
    func testAssignmentPersistsItsComputerTerminalAndDefaultAgent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrapingBoxAssignmentStore(url: root.appendingPathComponent("assignments.json"))
        let item = ScrapingBoxAssignment(computerID: UUID(), terminalID: UUID(),
                                        defaultAgentDefinitionID: UUID(), skillID: UUID())
        try store.save([item.computerID: item])
        XCTAssertEqual(try store.load()[item.computerID], item)
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testAssignmentStoreRejectsMismatchedKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScrapingBoxAssignmentStore(url: root.appendingPathComponent("assignments.json"))
        let item = ScrapingBoxAssignment(computerID: UUID(), terminalID: UUID(),
                                        defaultAgentDefinitionID: UUID(), skillID: UUID())
        XCTAssertThrowsError(try store.save([UUID(): item]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }
}

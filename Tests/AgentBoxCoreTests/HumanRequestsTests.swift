import XCTest
@testable import AgentBoxCore

final class HumanRequestsTests: XCTestCase {
    private func request(id: UUID = UUID(), session: UUID = UUID(), terminal: UUID = UUID(),
                         computer: UUID = UUID()) -> HumanRequest {
        HumanRequest(id: id, target: HumanRequestTarget(sessionID: session, terminalID: terminal,
                                                        runID: UUID(), computerID: computer),
                     kind: .login, summary: "Confirme o login no navegador")
    }

    func testReconnectionDoesNotDuplicateRequestOrNotification() throws {
        var snapshot = HumanRequestSnapshot()
        let first = request()
        XCTAssertTrue(try snapshot.record(first))
        XCTAssertFalse(try snapshot.record(first))
        XCTAssertTrue(try snapshot.claimNotification(first.id))
        XCTAssertFalse(try snapshot.claimNotification(first.id))
        XCTAssertEqual(snapshot.pendingCount(sessionID: first.target.sessionID), 1)
        XCTAssertEqual(snapshot.pendingCount(terminalID: UUID()), 0)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HumanRequestRepository(url: directory.appendingPathComponent("requests.json"))
        try repository.save(snapshot)
        var restored = try repository.load()
        XCTAssertFalse(try restored.record(first))
        XCTAssertFalse(try restored.claimNotification(first.id))
    }

    func testIdentityConflictAndResolution() throws {
        var snapshot = HumanRequestSnapshot()
        let id = UUID(), session = UUID(), terminal = UUID()
        let first = request(id: id, session: session, terminal: terminal)
        try snapshot.record(first)
        XCTAssertThrowsError(try snapshot.record(request(id: id, session: session, terminal: terminal,
                                                         computer: UUID())))
        XCTAssertThrowsError(try snapshot.resolve(id))
        try snapshot.acknowledge(id)
        try snapshot.resolve(id)
        XCTAssertEqual(snapshot.pendingCount(sessionID: session), 0)
        XCTAssertEqual(snapshot.requests[0].state, .resolved)
    }

    func testCorruptOrUnknownSchemaIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("requests.json")
        let original = try JSONEncoder().encode(HumanRequestSnapshot(schemaVersion: 99))
        try original.write(to: file)
        XCTAssertThrowsError(try HumanRequestRepository(url: file).load())
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}

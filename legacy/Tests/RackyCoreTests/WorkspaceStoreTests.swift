import Foundation
import XCTest
@testable import RackyCore

final class WorkspaceStoreTests: XCTestCase {
    func testSessionAndTerminalRenamePreserveIdentityAndRestoreIdleMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = WorkspaceRepository(url: directory.appendingPathComponent("workspace.json"))
        let terminal = TerminalRecord(title: "Initial", provider: .codex, cwd: directory.path)
        var session = WorkspaceSession(title: "Research", terminals: [terminal])
        var snapshot = WorkspaceSnapshot(sessions: [session], layouts: [WorkspaceLayout(sessionID: session.id, root: .terminal(terminal.id), focusedTerminalID: terminal.id)], selectedSessionID: session.id, sidebarWidth: 382, sidebarCollapsed: true)
        try repository.save(snapshot)

        session.title = "Renamed session"
        session.terminals[0].title = "Renamed terminal"
        snapshot.sessions[0] = session
        try repository.save(snapshot)
        let restored = try repository.load()

        XCTAssertEqual(restored.sessions[0].id, session.id)
        XCTAssertEqual(restored.sessions[0].terminals[0].id, terminal.id)
        XCTAssertEqual(restored.sessions[0].title, "Renamed session")
        XCTAssertEqual(restored.sessions[0].terminals[0].title, "Renamed terminal")
        XCTAssertEqual(restored.layouts[0].visibleTerminalIDs, [terminal.id])
        XCTAssertEqual(restored.sidebarWidth, 382)
        XCTAssertTrue(restored.sidebarCollapsed)
    }

    func testSplitTreeKeepsUniquePanesAndSurvivesRemoval() {
        let ids = (0..<5).map { _ in UUID() }
        var layout = WorkspaceLayout(sessionID: UUID(), root: .terminal(ids[0]), focusedTerminalID: ids[0])
        layout.split(ids[1], beside: ids[0], axis: .horizontal)
        layout.split(ids[2], beside: ids[1], axis: .vertical)
        layout.split(ids[3], beside: ids[0], axis: .horizontal)
        layout.split(ids[4], beside: ids[2], axis: .vertical)
        layout.split(UUID(), beside: ids[0], axis: .horizontal)
        XCTAssertEqual(layout.visibleTerminalIDs.count, 5)
        XCTAssertEqual(Set(layout.visibleTerminalIDs).count, 5)
        layout.closePane(ids[1])
        XCTAssertEqual(Set(layout.visibleTerminalIDs), Set([ids[0], ids[2], ids[3], ids[4]]))
        layout.show(ids[1])
        XCTAssertEqual(layout.visibleTerminalIDs.count, 4)
        XCTAssertTrue(layout.visibleTerminalIDs.contains(ids[1]))
    }

    func testDirectoryWithSpacesAndMissingPath() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let spaced = base.appendingPathComponent("Project with spaces", isDirectory: true)
        try FileManager.default.createDirectory(at: spaced, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        XCTAssertEqual(try WorkspaceDirectory.resolve(spaced.path + "/../Project with spaces"), spaced.path)
        XCTAssertThrowsError(try WorkspaceDirectory.resolve(spaced.appendingPathComponent("missing").path))
        XCTAssertThrowsError(try WorkspaceDirectory.resolve(""))
    }

    func testCorruptFileDoesNotGetTreatedAsEmptyWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workspace.json")
        try Data("{broken".utf8).write(to: url)
        XCTAssertThrowsError(try WorkspaceRepository(url: url).load())
        XCTAssertEqual(try Data(contentsOf: url), Data("{broken".utf8))
    }
}

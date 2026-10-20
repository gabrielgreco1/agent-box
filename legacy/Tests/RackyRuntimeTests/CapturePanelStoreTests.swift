import RackyCore
import Foundation
import XCTest
@testable import Racky

final class CapturePanelStoreTests: XCTestCase {
    @MainActor
    func testOfflineRefreshShowsStoredEvidenceWithoutOpeningRuntime() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let configuration = CaptureConfiguration(enabled: true, hosts: ["example.com"])
        let batch = fixture.batch(enabled: true, event: fixture.event(url: "https://example.com/private?secret=x"))
        _ = try await fixture.captures.append(batch: batch, identity: fixture.identity,
                                              configuration: configuration)
        let store = fixture.store(running: false, endpoint: { XCTFail("Offline refresh contacted the runtime"); throw CaptureError.invalidWireData })

        await store.refresh()

        XCTAssertEqual(store.events.count, 1)
        XCTAssertEqual(store.events.first?.url, "https://example.com")
        XCTAssertFalse(store.captureEnabled)
        XCTAssertTrue(store.runtimeStateKnown)
        XCTAssertNil(store.errorText)
    }

    @MainActor
    func testOfflineDeleteDoesNotDiscardLocalCaptures() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let configuration = CaptureConfiguration(enabled: true, hosts: ["example.com"])
        _ = try await fixture.captures.append(batch: fixture.batch(enabled: true,
            event: fixture.event(url: "https://example.com/one")),
            identity: fixture.identity, configuration: configuration)
        let store = fixture.store(running: false, endpoint: { throw CaptureError.invalidWireData })

        await store.deleteCaptures()

        let remaining = try await fixture.captures.records(computerID: fixture.computerID)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotNil(store.errorText)
    }
}

@MainActor private final class Fixture {
    let root: URL
    let computerID = UUID()
    let terminalID = UUID()
    let sessionID = UUID()
    let captures: CaptureStore
    let datasets: DatasetStore

    var identity: CaptureIdentity {
        CaptureIdentity(sessionID: sessionID, terminalID: terminalID, computerID: computerID)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("capture-panel-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        captures = try CaptureStore(directory: root.appendingPathComponent("Captures"))
        datasets = try DatasetStore(directory: root.appendingPathComponent("Datasets"))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func event(url: String) -> CaptureEvent {
        CaptureEvent(sequence: 1, requestID: "req-1", source: "browser", method: "GET",
                     url: url, status: 200, timestamp: "2026-10-16T12:00:00Z")
    }

    func batch(enabled: Bool, event: CaptureEvent) -> CaptureBatch {
        CaptureBatch(schemaVersion: 1, captureID: UUID(), coverageVersion: "racky-capture/1",
                     computerID: computerID.uuidString.lowercased(), enabled: enabled,
                     coverage: ["browser_context_requests"], gaps: [], events: [event],
                     nextCursor: 1, dropped: 0)
    }

    func store(running: Bool,
               endpoint: @escaping @MainActor () async throws -> BrowserRuntimeEndpoint) -> CapturePanelStore {
        let computerID = computerID
        let terminalID = terminalID
        return CapturePanelStore(computerID: computerID, owner: .terminal(terminalID),
            context: ComputerPolicyContext(terminalID: terminalID, sessionID: sessionID),
            captureStore: captures, datasetStore: datasets,
            configurationDirectory: root.appendingPathComponent("Preferences"),
            ownershipProvider: {
                BrowserManagedComputer(id: computerID, terminalID: terminalID,
                    containerID: String(repeating: "a", count: 64), name: "racky-test",
                    volumeName: "racky-test-volume", running: running)
            }, endpointProvider: endpoint)
    }
}

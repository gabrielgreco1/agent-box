import Foundation
import XCTest
@testable import RackyCore

final class CaptureStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("capture-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return directory
    }

    private func fixture(computerID: UUID, captureID: UUID = UUID()) -> CaptureBatch {
        CaptureBatch(schemaVersion: 1, captureID: captureID, coverageVersion: "browser-v1",
            computerID: computerID.uuidString, enabled: true, coverage: ["browser.response"], gaps: ["service_worker"],
            events: [CaptureEvent(sequence: 1, requestID: "req-1", source: "browser", method: "GET",
                url: "https://example.com/api/items?access_token=never-save#fragment", status: 200,
                mime: "application/json", timestamp: "2026-10-16T12:00:00Z", durationMS: 12.5,
                bodyJSON: ["name": .string("Example"), "formula": .string("=HYPERLINK(\"x\")"),
                           "secret_token": .string("never-save")], bodySHA256: String(repeating: "a", count: 64))],
            nextCursor: 1, dropped: 0)
    }

    func testWireRoundTripSanitizationDedupAndIndependentDeletion() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let computerID = UUID()
        let identity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), ownerRunID: UUID(), computerID: computerID)
        let configuration = try CaptureConfiguration(enabled: true, hosts: ["example.com"],
            pathPrefixes: ["/api"], includeJSON: true, jsonFields: ["name", "formula"],
            maxBodyBytes: 65_536, maxEvents: 10, retentionSeconds: 3_600).validated()
        let batch = fixture(computerID: computerID)
        let wire = try JSONEncoder().encode(batch)
        let decoded = try JSONDecoder().decode(CaptureBatch.self, from: wire)
        XCTAssertEqual(decoded, batch)
        let capture = try CaptureStore(directory: root.appendingPathComponent("Captures"))
        let first = try await capture.append(batch: decoded, identity: identity, configuration: configuration)
        XCTAssertEqual(first.inserted, 1)
        let second = try await capture.append(batch: decoded, identity: identity, configuration: configuration)
        XCTAssertEqual(second.duplicates, 1)
        let records = try await capture.records(computerID: computerID)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].duplicateCount, 1) // polling the same cursor is idempotent
        XCTAssertEqual(records[0].captureID, batch.captureID)
        XCTAssertEqual(records[0].event.url, "https://example.com/api")
        XCTAssertEqual(records[0].event.bodyJSON?.count, 2)
        XCTAssertNil(records[0].event.bodyJSON?["secret_token"])
        XCTAssertFalse(String(data: try JSONEncoder().encode(records), encoding: .utf8)!.contains("never-save"))
        let status = try await capture.status(computerID: computerID)
        XCTAssertEqual(status.coverage, ["browser.response"])
        XCTAssertEqual(status.gaps, ["service_worker"])
        XCTAssertEqual(status.retainedEvents, 1)

        let results = try DatasetStore(directory: root.appendingPathComponent("Results"))
        let dataset = try await results.create(name: "Items", columns: ["name", "formula", "missing"], from: records)
        let unrelatedComputer = UUID()
        let unrelatedIdentity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), computerID: unrelatedComputer)
        _ = try await capture.append(batch: fixture(computerID: unrelatedComputer), identity: unrelatedIdentity,
            configuration: configuration)
        let unrelatedRecords = try await capture.records(computerID: unrelatedComputer)
        _ = try await results.create(name: "Other box", columns: ["name"], from: unrelatedRecords)
        let visibleResults = try await results.list(computerID: computerID)
        XCTAssertEqual(visibleResults.map(\.id), [dataset.id])
        XCTAssertEqual(dataset.rows[0].missingReasons["missing"], "field_unavailable")
        XCTAssertEqual(dataset.rows[0].values["missing"], .null)
        let exported = try await results.export(datasetID: dataset.id, format: .csv, to: root)
        let csv = try String(contentsOf: exported.dataURL, encoding: .utf8)
        XCTAssertTrue(csv.contains("'=HYPERLINK"))
        XCTAssertTrue(csv.contains("field_unavailable"))
        let manifest = try JSONDecoder.withISO8601.decode(DatasetExportManifest.self,
            from: Data(contentsOf: exported.manifestURL))
        XCTAssertEqual(manifest.dataSHA256, exported.sha256)
        XCTAssertEqual(manifest.evidenceSHA256, [records[0].evidenceSHA256])
        try await capture.deleteCaptures(computerID: computerID)
        let remainingCaptures = try await capture.records(computerID: computerID)
        XCTAssertTrue(remainingCaptures.isEmpty)
        let retainedDataset = try await results.load(datasetID: dataset.id)
        XCTAssertEqual(retainedDataset.rows.count, 1)
    }

    func testDisabledCaptureAndMismatchedIdentityDoNotPersist() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let computerID = UUID()
        let identity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), computerID: computerID)
        let store = try CaptureStore(directory: root.appendingPathComponent("Captures"))
        let disabled = try await store.append(batch: fixture(computerID: computerID), identity: identity,
            configuration: CaptureConfiguration())
        XCTAssertEqual(disabled.inserted, 0)
        let saved = try await store.records(computerID: computerID)
        XCTAssertTrue(saved.isEmpty)
        do {
            _ = try await store.append(batch: fixture(computerID: UUID()), identity: identity,
                configuration: CaptureConfiguration(enabled: true, hosts: ["example.com"], pathPrefixes: ["/api"]))
            XCTFail("Mismatched computer identity was accepted")
        } catch { XCTAssertEqual(error as? CaptureError, .invalidWireData) }
    }

    func testSequenceRestartInNewCaptureEpochDoesNotDeduplicateEvidence() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let computerID = UUID()
        let identity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), computerID: computerID)
        let store = try CaptureStore(directory: root.appendingPathComponent("Captures"))
        let config = CaptureConfiguration(enabled: true, hosts: ["example.com"], pathPrefixes: ["/api"])
        let first = fixture(computerID: computerID)
        let next = fixture(computerID: computerID)
        XCTAssertNotEqual(first.captureID, next.captureID)
        _ = try await store.append(batch: CaptureBatch(schemaVersion: 1, captureID: first.captureID,
            coverageVersion: first.coverageVersion, computerID: first.computerID, enabled: true,
            coverage: first.coverage, gaps: first.gaps, events: first.events, nextCursor: 1, dropped: 2),
            identity: identity, configuration: config)
        _ = try await store.append(batch: CaptureBatch(schemaVersion: 1, captureID: next.captureID,
            coverageVersion: next.coverageVersion, computerID: next.computerID, enabled: true,
            coverage: next.coverage, gaps: next.gaps, events: next.events, nextCursor: 1, dropped: 3),
            identity: identity, configuration: config)
        let records = try await store.records(computerID: computerID)
        XCTAssertEqual(records.count, 2)
        XCTAssertNotEqual(records[0].evidenceSHA256, records[1].evidenceSHA256)
        let status = try await store.status(computerID: computerID)
        XCTAssertEqual(status.reportedDropped, 5)
    }

    func testMetadataWithNilBodyWorksAtOneByteCapAndExpiresOnRead() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let clock = TestCaptureClock(Date(timeIntervalSince1970: 1_800_000_000))
        let computerID = UUID()
        let identity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), computerID: computerID)
        let store = try CaptureStore(directory: root.appendingPathComponent("Captures"), now: { clock.read() })
        let config = CaptureConfiguration(enabled: true, hosts: ["example.com"], pathPrefixes: ["/api"],
            maxBodyBytes: 1, maxEvents: 10, retentionSeconds: 60)
        let first = try await store.append(batch: fixture(computerID: computerID), identity: identity,
            configuration: config)
        XCTAssertEqual(first.inserted, 1)
        clock.advance(by: 61)
        let after = try await store.records(computerID: computerID)
        XCTAssertTrue(after.isEmpty)
        let status = try await store.status(computerID: computerID)
        XCTAssertEqual(status.retainedEvents, 0)
    }

    func testLargeArchiveEvictsOldestAndCountsLocalDrops() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let computerID = UUID()
        let identity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), computerID: computerID)
        let fields = (0..<32).map { "field\($0)" }
        let body = Dictionary(uniqueKeysWithValues: fields.map { ($0, CaptureScalar.string(String(repeating: "x", count: 450))) })
        let events = (0..<1_000).map { index in
            CaptureEvent(sequence: index, requestID: "request-\(index)", source: "browser", method: "GET",
                url: "https://example.com/api/items", timestamp: "2026-10-16T12:00:00.123+00:00",
                bodyJSON: body)
        }
        let batch = CaptureBatch(schemaVersion: 1, captureID: UUID(), coverageVersion: "browser-v1",
            computerID: computerID.uuidString, enabled: true, coverage: [], gaps: [],
            events: events, nextCursor: 1_000, dropped: 0)
        let store = try CaptureStore(directory: root.appendingPathComponent("Captures"))
        let config = CaptureConfiguration(enabled: true, hosts: ["example.com"], pathPrefixes: ["/api"],
            includeJSON: true, jsonFields: fields, maxBodyBytes: 65_536, maxEvents: 1_000)
        let result = try await store.append(batch: batch, identity: identity, configuration: config)
        XCTAssertGreaterThan(result.localDropped, 0)
        let records = try await store.records(computerID: computerID)
        XCTAssertEqual(records.last?.event.sequence, 999)
        XCTAssertLessThan(records.count, 1_000)
        let status = try await store.status(computerID: computerID)
        XCTAssertEqual(status.localDropped, result.localDropped)
    }

    func testDatasetRejectsReservedAndCollidingCSVColumns() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let computerID = UUID()
        let identity = CaptureIdentity(sessionID: UUID(), terminalID: UUID(), computerID: computerID)
        let capture = try CaptureStore(directory: root.appendingPathComponent("Captures"))
        let config = CaptureConfiguration(enabled: true, hosts: ["example.com"], pathPrefixes: ["/api"])
        _ = try await capture.append(batch: fixture(computerID: computerID), identity: identity,
            configuration: config)
        let records = try await capture.records(computerID: computerID)
        let results = try DatasetStore(directory: root.appendingPathComponent("Results"))
        do {
            _ = try await results.create(name: "Bad", columns: ["capture_id"], from: records)
            XCTFail("Reserved column accepted")
        } catch { XCTAssertEqual(error as? CaptureError, .invalidColumn) }
        do {
            _ = try await results.create(name: "Bad", columns: ["field", "field__missing_reason"], from: records)
            XCTFail("Generated missing-reason column collided")
        } catch { XCTAssertEqual(error as? CaptureError, .invalidColumn) }
    }

    func testSymlinkAndCorruptArchiveFailClosed() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Captures")
        let store = try CaptureStore(directory: directory)
        let computerID = UUID()
        let file = directory.appendingPathComponent("capture-\(computerID.uuidString.lowercased()).json")
        try "not JSON".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        do {
            _ = try await store.records(computerID: computerID)
            XCTFail("Corrupt archive was treated as empty")
        } catch { XCTAssertEqual(error as? CaptureError, .corruptStore) }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root.appendingPathComponent("target"))
        do {
            _ = try await store.records(computerID: computerID)
            XCTFail("Symlink was followed")
        } catch { XCTAssertEqual(error as? CaptureError, .unsafePath) }
    }
}

private final class TestCaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(_ instant: Date) { self.instant = instant }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
    func advance(by seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; instant.addTimeInterval(seconds) }
}

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

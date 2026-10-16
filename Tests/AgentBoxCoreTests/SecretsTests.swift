import XCTest
@testable import AgentBoxCore

private enum FakeSecretStoreError: Error { case forcedFailure }
private final class FakeSecretStore: SecretValueStoring {
    var values: [UUID: String] = [:]
    func put(id: UUID, value: String) throws {
        if value == "FAIL" { throw FakeSecretStoreError.forcedFailure }
        values[id] = value
    }
    func read(id: UUID) throws -> String {
        guard let value = values[id] else { throw SecretError.missingSecret }
        return value
    }
    func delete(id: UUID) throws { values.removeValue(forKey: id) }
}

final class SecretsTests: XCTestCase {
    private func repository() -> SecretRepository {
        SecretRepository(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("agentbox-secret-test-\(UUID().uuidString)")
            .appendingPathComponent("references.json"))
    }

    func testEnvParserNeverExpandsAndReportsDuplicates() throws {
        let parsed = try EnvFileParser.parse("# comment\nexport API_KEY='$(touch never)'\r\nDOLLAR=`whoami`$HOME\nAPI_KEY=second\n")
        XCTAssertEqual(parsed.entries.map(\.name), ["API_KEY", "DOLLAR", "API_KEY"])
        XCTAssertEqual(parsed.entries[0].value, "$(touch never)")
        XCTAssertEqual(parsed.entries[1].value, "`whoami`$HOME")
        XCTAssertEqual(parsed.duplicateNames, ["API_KEY"])
        XCTAssertThrowsError(try EnvFileParser.parse("BAD LINE"))
        XCTAssertThrowsError(try EnvFileParser.parse("KEY=\"unsupported\\q\""))
    }

    func testValueNeverEntersMetadataAndGrantMustMatchExactly() throws {
        let backend = FakeSecretStore(), repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.url.deletingLastPathComponent()) }
        let vault = SecretVault(backend: backend, repository: repo)
        let reference = try vault.add(name: "API_KEY", value: "very-secret-value")
        let metadata = try String(contentsOf: repo.url)
        XCTAssertFalse(metadata.contains("very-secret-value"))
        XCTAssertTrue(metadata.contains("API_KEY"))
        let scopeID = UUID()
        let request = SecretAccessRequest(secretID: reference.id, scope: .agentRun, scopeID: scopeID,
                                          use: .tool, destination: "search.example")
        XCTAssertThrowsError(try vault.resolve(request))
        let grant = try vault.grant(secretID: reference.id, scope: .agentRun, scopeID: scopeID,
                                    use: .tool, destination: "search.example", delegable: false)
        XCTAssertEqual(try vault.resolve(request), "very-secret-value")
        let otherRun = SecretAccessRequest(secretID: reference.id, scope: .agentRun, scopeID: UUID(),
                                           use: .tool, destination: "search.example")
        let otherUse = SecretAccessRequest(secretID: reference.id, scope: .agentRun, scopeID: scopeID,
                                           use: .environment, destination: "search.example")
        let otherDestination = SecretAccessRequest(secretID: reference.id, scope: .agentRun, scopeID: scopeID,
                                                   use: .tool, destination: "other.tool")
        XCTAssertThrowsError(try vault.resolve(otherRun))
        XCTAssertThrowsError(try vault.resolve(otherUse))
        XCTAssertThrowsError(try vault.resolve(otherDestination))
        try vault.revoke(grantID: grant.id)
        XCTAssertThrowsError(try vault.resolve(request))
        XCTAssertEqual(try repo.load().grants.first?.revision, 2)
        XCTAssertNotNil(backend.values[reference.id]) // revocation cannot retract an already delivered value
    }

    func testExpiredGrantAndDelegableFlagDoNotGrantChildImplicitly() throws {
        let backend = FakeSecretStore(), repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.url.deletingLastPathComponent()) }
        let vault = SecretVault(backend: backend, repository: repo)
        let reference = try vault.add(name: "TOKEN", value: "hidden")
        let projectID = UUID(), future = Date(timeIntervalSince1970: 4_000_000_000)
        _ = try vault.grant(secretID: reference.id, scope: .project, scopeID: projectID,
                            use: .environment, destination: "worker", delegable: true, expiresAt: future,
                            now: Date(timeIntervalSince1970: 100))
        let parent = SecretAccessRequest(secretID: reference.id, scope: .project, scopeID: projectID,
                                         use: .environment, destination: "worker")
        XCTAssertEqual(try vault.resolve(parent, at: Date(timeIntervalSince1970: 200)), "hidden")
        XCTAssertThrowsError(try vault.resolve(parent, at: future))
        let child = SecretAccessRequest(secretID: reference.id, scope: .agentRun, scopeID: UUID(),
                                        use: .environment, destination: "worker")
        XCTAssertThrowsError(try vault.resolve(child, at: Date(timeIntervalSince1970: 200)))
    }

    func testEnvImportStoresMaskedMetadataAndValuesInBackend() throws {
        let backend = FakeSecretStore(), repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.url.deletingLastPathComponent()) }
        let vault = SecretVault(backend: backend, repository: repo)
        let parsed = try EnvFileParser.parse("ALPHA='literal $HOME'\nBETA=second\n")
        let references = try vault.importEnv(parsed, sourceLabel: ".env")
        XCTAssertEqual(references.map(\.name), ["ALPHA", "BETA"])
        XCTAssertEqual(backend.values[references[0].id], "literal $HOME")
        XCTAssertEqual(backend.values[references[1].id], "second")
        let metadata = try String(contentsOf: repo.url)
        XCTAssertFalse(metadata.contains("literal $HOME"))
        XCTAssertFalse(metadata.contains("second"))
        XCTAssertEqual(try repo.load().references.count, 2)
    }

    func testEnvBatchRollsBackOnBackendFailure() throws {
        let backend = FakeSecretStore(), repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.url.deletingLastPathComponent()) }
        let vault = SecretVault(backend: backend, repository: repo)
        let parsed = try EnvFileParser.parse("FIRST=okay\nSECOND=FAIL\n")
        XCTAssertThrowsError(try vault.importEnv(parsed, sourceLabel: ".env"))
        XCTAssertTrue(backend.values.isEmpty)
        XCTAssertTrue(try repo.load().references.isEmpty)
    }

    func testDuplicateEnvNamesCannotReplaceStoredValue() throws {
        let backend = FakeSecretStore(), repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.url.deletingLastPathComponent()) }
        let vault = SecretVault(backend: backend, repository: repo)
        _ = try vault.add(name: "A", value: "original")
        let parsed = try EnvFileParser.parse("A=new\n")
        XCTAssertThrowsError(try vault.importEnv(parsed, sourceLabel: ".env"))
        XCTAssertEqual(try repo.load().references.count, 1)
        XCTAssertEqual(backend.values.count, 1)
    }
}

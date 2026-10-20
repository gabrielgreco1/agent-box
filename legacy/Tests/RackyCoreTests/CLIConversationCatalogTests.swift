import Foundation
import XCTest
@testable import RackyCore

final class CLIConversationCatalogTests: XCTestCase {
    private let claudeID = "550e8400-e29b-41d4-a716-446655440000"

    func testClaudeListingCopiesOnlyIdentityAndProjectMetadata() throws {
        let listing = """
        [
          {"sessionId":"550E8400-E29B-41D4-A716-446655440000","cwd":"/tmp","name":"private name","prompt":"secret prompt","token":"secret token"},
          {"sessionId":"550e8400-e29b-41d4-a716-446655440000","cwd":"/tmp"},
          {"sessionId":"invalid","cwd":"/tmp"},
          {"sessionId":"d02f3de7-2b56-4ff1-a42a-a0413f767c90","cwd":"relative/path"}
        ]
        """
        let candidates = try CLIConversationCatalog.parseClaudeAgentsJSON(Data(listing.utf8))
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].identity.nativeSessionID, claudeID)
        XCTAssertEqual(candidates[0].identity.provider, .claude)
        XCTAssertEqual(candidates[0].source, .claudeAgentsCLI)
        XCTAssertEqual(candidates[0].projectPath, "/tmp")
        XCTAssertEqual(candidates[0].activity, .active)
        XCTAssertTrue(candidates[0].originIsExternal)
        XCTAssertFalse(String(reflecting: candidates[0]).contains("secret"))
        XCTAssertThrowsError(try CLIConversationCatalog.parseClaudeAgentsJSON(Data(repeating: 120, count: 1_048_577)))
    }

    func testOnlyVerifiedClaudeDiscoveryAndExactResumeArguments() throws {
        XCTAssertEqual(try CLIConversationCatalog.discoveryArguments(for: .claude), ["agents", "--json"])
        XCTAssertThrowsError(try CLIConversationCatalog.discoveryArguments(for: .codex))
        XCTAssertThrowsError(try CLIConversationCatalog.discoveryArguments(for: .opencode))

        let cases: [(CLIProvider, String, [String])] = [
            (.claude, claudeID, ["--resume", claudeID]),
            (.codex, claudeID, ["resume", claudeID]),
            (.opencode, "ses_abcdefgh1234", ["--session", "ses_abcdefgh1234"]),
        ]
        for (provider, nativeID, arguments) in cases {
            let candidate = try CLIConversationCatalog.explicitIdentity(provider: provider,
                sessionID: nativeID, projectPath: "/tmp")
            let command = try CLIConversationCatalog.resumeCommand(for: candidate, executablePath: "/bin/sh")
            XCTAssertEqual(command.identity, candidate.identity)
            XCTAssertEqual(command.arguments, arguments)
            XCTAssertEqual(command.workingDirectory, "/tmp")
            XCTAssertTrue(command.requiresExclusiveWriterAdmission)
        }
        XCTAssertThrowsError(try CLIConversationCatalog.explicitIdentity(provider: .codex,
            sessionID: "a name with spaces", projectPath: "/tmp"))
        XCTAssertThrowsError(try CLIConversationCatalog.explicitIdentity(provider: .opencode,
            sessionID: "ses_../../other", projectPath: "/tmp"))
        XCTAssertThrowsError(try CLIConversationCatalog.explicitIdentity(provider: .claude,
            sessionID: claudeID, projectPath: "relative"))
    }

    func testFakeReadOnlyClaudeDiscoveryRunsOnlyFixedArguments() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-claude")
        let script = """
        #!/bin/sh
        [ "$#" -eq 2 ] && [ "$1" = agents ] && [ "$2" = --json ] || exit 9
        printf '%s\\n' '[{"sessionId":"550e8400-e29b-41d4-a716-446655440000","cwd":"/tmp"}]'
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let candidates = try CLIConversationCatalog.discoverActiveClaude(executablePath: executable.path,
            workingDirectory: directory.path)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].identity.nativeSessionID, claudeID)
    }

    func testWriterReservationRejectsActiveExternalAndStaleRelease() throws {
        let coordinator = CLIConversationWriteCoordinator()
        let active = try CLIConversationCandidate(identity: CLIConversationIdentity(provider: .claude,
            nativeSessionID: claudeID), source: .claudeAgentsCLI, projectPath: "/tmp", activity: .active)
        XCTAssertThrowsError(try coordinator.reserve(candidate: active, externalClosedAcknowledged: true)) { error in
            XCTAssertEqual(error as? CLIConversationWriteError, .activeExternalConversation)
        }
        let explicit = try CLIConversationCatalog.explicitIdentity(provider: .claude,
            sessionID: claudeID, projectPath: "/tmp")
        XCTAssertThrowsError(try coordinator.reserve(candidate: explicit)) { error in
            XCTAssertEqual(error as? CLIConversationWriteError, .externalClosureUnconfirmed)
        }
        let first = try coordinator.reserve(candidate: explicit, externalClosedAcknowledged: true)
        XCTAssertTrue(coordinator.isReserved(identity: explicit.identity))
        XCTAssertThrowsError(try coordinator.reserve(candidate: explicit, externalClosedAcknowledged: true)) { error in
            XCTAssertEqual(error as? CLIConversationWriteError, .alreadyReserved)
        }
        XCTAssertTrue(coordinator.release(ticket: first))
        let second = try coordinator.reserve(candidate: explicit, externalClosedAcknowledged: true)
        XCTAssertFalse(coordinator.release(ticket: first))
        XCTAssertTrue(coordinator.isReserved(identity: explicit.identity))
        XCTAssertTrue(coordinator.release(ticket: second))
        XCTAssertFalse(coordinator.isReserved(identity: explicit.identity))
    }
}

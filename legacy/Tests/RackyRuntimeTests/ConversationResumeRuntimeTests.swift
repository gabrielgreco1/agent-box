import Foundation
import XCTest
import RackyCore
@testable import Racky

final class ConversationResumeRuntimeTests: XCTestCase {
    @MainActor
    func testResumeUsesNativeArgvAndHoldsWriterUntilPTYExit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("resume-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("claude")
        try "#!/bin/sh\nif [ \"$1\" = agents ]; then printf '[]'; exit 0; fi\nprintf 'RESUME_ARGS:%s:%s\\n' \"$1\" \"$2\"\nexec sleep 30\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let monitor = NativeAgentMonitor(registry: try AgentRunRegistry(url: root.appendingPathComponent("runs.json")))
        let manager = TerminalRuntimeManager(resolver: CLIExecutableResolver(overrides: [.claude: executable.path]),
                                             nativeAgentMonitor: monitor)
        defer { manager.shutdown() }
        let candidate = try CLIConversationCatalog.explicitIdentity(provider: .claude,
            sessionID: UUID().uuidString, projectPath: root.path)
        let command = try CLIConversationCatalog.resumeCommand(for: candidate, executablePath: executable.path)
        let first = TerminalRecord(title: "Resume", provider: .claude, cwd: root.path,
            arguments: command.arguments, nativeConversation: candidate.identity)
        let second = TerminalRecord(title: "Duplicate", provider: .claude, cwd: root.path,
            arguments: command.arguments, nativeConversation: candidate.identity)
        // A restored terminal must never silently re-open the conversation.
        manager.start(first)
        guard case .failed = manager.state(for: first.id) else { return XCTFail("Resume requires admission") }
        try await manager.startResuming(first, candidate: candidate, externalClosedAcknowledged: true)
        let sawArguments = await waitUntil {
            guard let renderer = manager.renderer(for: first.id) else { return false }
            return String(decoding: renderer.getTerminal().getBufferAsData(), as: UTF8.self)
                .contains("RESUME_ARGS:--resume:\(candidate.identity.nativeSessionID)")
        }
        XCTAssertTrue(sawArguments)
        do {
            try await manager.startResuming(second, candidate: candidate, externalClosedAcknowledged: true)
            XCTFail("The same conversation cannot have two app writers")
        } catch CLIConversationWriteError.alreadyReserved {}
        manager.stop(first.id)
        let exited = await waitUntil { if case .exited = manager.state(for: first.id) { return true }; return false }
        XCTAssertTrue(exited)
        try await manager.startResuming(second, candidate: candidate, externalClosedAcknowledged: true)
        guard case .running = manager.state(for: second.id) else { return XCTFail("Exit should release the writer") }
        manager.stop(second.id)
        let secondExited = await waitUntil { if case .exited = manager.state(for: second.id) { return true }; return false }
        XCTAssertTrue(secondExited)
        XCTAssertFalse(CLIConversationWriteCoordinator.shared.isReserved(identity: candidate.identity))
        let encoded = try JSONEncoder().encode(first)
        XCTAssertEqual(try JSONDecoder().decode(TerminalRecord.self, from: encoded).nativeConversation, candidate.identity)
        // Quit during the metadata query must not start a new process afterward.
        try "#!/bin/sh\nif [ \"$1\" = agents ]; then sleep 0.3; printf '[]'; exit 0; fi\nexec sleep 30\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        let pending = Task { @MainActor in
            try await manager.startResuming(first, candidate: candidate, externalClosedAcknowledged: true)
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        manager.shutdown()
        do { try await pending.value; XCTFail("Quit must invalidate pending resume") }
        catch is LibraryError {}
        XCTAssertFalse(CLIConversationWriteCoordinator.shared.isReserved(identity: candidate.identity))
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return condition()
    }
}

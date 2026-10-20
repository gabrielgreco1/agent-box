import XCTest
@testable import RackyCore

final class AgentRegistryTests: XCTestCase {
    func testVerifiedCallerRejectsStaleChildWrongSessionAndFinishedParent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let terminalID = UUID()
        let parent = try await registry.recordTerminalStart(terminalID: terminalID,
                                                             provider: .claude, processID: 42)
        let session = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SessionStart","session_id":"session-A"}"#.utf8), source: .claude)
        _ = try await registry.recordHookEvent(session, parentRunID: parent.id)
        let started = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SubagentStart","session_id":"session-A","agent_id":"child-A","agent_type":"Explore"}"#.utf8), source: .claude)
        let childRecord = try await registry.recordHookEvent(started, parentRunID: parent.id)
        let child = try XCTUnwrap(childRecord)
        let verifiedParent = await registry.verifiedCaller(parentRunID: parent.id,
            terminalID: terminalID, sessionID: "session-A", agentID: nil)
        let verifiedChild = await registry.verifiedCaller(parentRunID: parent.id,
            terminalID: terminalID, sessionID: "session-A", agentID: "child-A")
        XCTAssertEqual(verifiedParent?.id, parent.id)
        XCTAssertEqual(verifiedChild?.id, child.id)
        let wrongSession = await registry.verifiedCaller(parentRunID: parent.id,
            terminalID: terminalID, sessionID: "session-B", agentID: "child-A")
        let wrongTerminal = await registry.verifiedCaller(parentRunID: parent.id,
            terminalID: UUID(), sessionID: "session-A", agentID: "child-A")
        XCTAssertNil(wrongSession)
        XCTAssertNil(wrongTerminal)
        let stopped = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SubagentStop","session_id":"session-A","agent_id":"child-A","agent_type":"Explore"}"#.utf8), source: .claude)
        _ = try await registry.recordHookEvent(stopped, parentRunID: parent.id)
        let staleChild = await registry.verifiedCaller(parentRunID: parent.id,
            terminalID: terminalID, sessionID: "session-A", agentID: "child-A")
        XCTAssertNil(staleChild)
        try await registry.finishTerminalRun(parent.id)
        let staleParent = await registry.verifiedCaller(parentRunID: parent.id,
            terminalID: terminalID, sessionID: "session-A", agentID: nil)
        XCTAssertNil(staleParent)
    }

    func testConcurrentInboxDrainsKeepCursorOrderedAndChildStopped() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = UUID()
        let hook = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        let config = try ClaudeHookInboxConfiguration.create(runID: runID,
            directory: root.appendingPathComponent("inbox"), hookScriptURL: hook)
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        _ = try await registry.recordTerminalStart(terminalID: UUID(), provider: .claude,
                                                   processID: 42, runID: runID)
        try Self.emit(#"{"hook_event_name":"SessionStart","session_id":"session-A"}"#,
                      hook: hook, environment: config.environment)
        try Self.emit(#"{"hook_event_name":"SubagentStart","session_id":"session-A","agent_id":"child-A","agent_type":"Explore"}"#,
                      hook: hook, environment: config.environment)
        try Self.emit(#"{"hook_event_name":"SubagentStop","session_id":"session-A","agent_id":"child-A","agent_type":"Explore"}"#,
                      hook: hook, environment: config.environment)
        let reader = ClaudeHookInbox(configuration: config, registry: registry)
        let total = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<32 { group.addTask { try await reader.drain() } }
            var accepted = 0
            for try await count in group { accepted += count }
            return accepted
        }
        XCTAssertEqual(total, 3, "Each signed line must be admitted once despite concurrent drain callers")
        let subsequent = try await reader.drain()
        XCTAssertEqual(subsequent, 0)
        let runs = await registry.allRuns()
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first(where: { $0.nativeAgentID == "child-A" })?.status, .finished)
    }

    func testOptInClaudeHookInboxAcceptsOnlyAuthenticatedRunEvents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = UUID()
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let hook = repository.appendingPathComponent("runtime/hooks/claude_event.py")
        let config = try ClaudeHookInboxConfiguration.create(runID: runID,
            directory: root.appendingPathComponent("inbox"), hookScriptURL: hook)
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let parent = try await registry.recordTerminalStart(terminalID: UUID(), provider: .claude,
                                                            processID: 42, runID: runID)
        XCTAssertEqual(parent.id, runID)
        let reader = ClaudeHookInbox(configuration: config, registry: registry)
        try Self.emit(#"{"hook_event_name":"SessionStart","session_id":"session-A","cwd":"private"}"#,
                      hook: hook, environment: config.environment)
        try Self.emit(#"{"hook_event_name":"SubagentStart","session_id":"session-A","agent_id":"child-A","agent_type":"Explore","prompt":"private"}"#,
                      hook: hook, environment: config.environment)
        let firstDrain = try await reader.drain()
        XCTAssertEqual(firstDrain, 2)
        let runs = await registry.allRuns()
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[1].nativeAgentID, "child-A")
        XCTAssertNil(runs[1].processID)
        let inboxText = try String(contentsOf: config.inboxURL, encoding: .utf8)
        XCTAssertFalse(inboxText.contains("private"))
        let emptyDrain = try await reader.drain()
        XCTAssertEqual(emptyDrain, 0)

        try Self.emit(#"{"hook_event_name":"SubagentStop","session_id":"session-A","agent_id":"unseen","agent_type":"Explore"}"#,
                      hook: hook, environment: config.environment)
        let orphanDrain = try await reader.drain()
        XCTAssertEqual(orphanDrain, 1)
        let afterOrphan = await registry.allRuns()
        XCTAssertEqual(afterOrphan.count, 2)

        var forged = Data(#"{"run_id":"forged","session_id":"session-A","hook_event_name":"SubagentStart","agent_id":"evil","agent_type":"Explore","signature":"00"}"#.utf8)
        forged.append(0x0A)
        let handle = try FileHandle(forWritingTo: config.inboxURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: forged)
        try handle.close()
        do {
            _ = try await reader.drain()
            XCTFail("Foreign run identity must be rejected")
        } catch ClaudeHookInboxError.wrongRun {}
    }

    private static func emit(_ payload: String, hook: URL, environment: [String: String]) throws {
        let process = Process()
        process.executableURL = hook
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testDocumentedHookFixtureCorrelatesNativeChildAndPersists() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("runs.json")
        let registry = try AgentRunRegistry(url: url)
        let terminalID = UUID()
        let parent = try await registry.recordTerminalStart(terminalID: terminalID, provider: .claude, processID: 1234)
        let session = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SessionStart","session_id":"sess-1"}"#.utf8), source: .claude)
        _ = try await registry.recordHookEvent(session, parentRunID: parent.id)
        let started = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SubagentStart","session_id":"sess-1","agent_id":"agent-1","agent_type":"Explore"}"#.utf8), source: .claude)
        let createdChild = try await registry.recordHookEvent(started, parentRunID: parent.id)
        let child = try XCTUnwrap(createdChild)
        XCTAssertEqual(child.parentTerminalID, terminalID)
        XCTAssertEqual(child.parentRunID, parent.id)
        XCTAssertNil(child.processID)
        XCTAssertEqual(child.nativeAgentType, "Explore")
        let repeated = try await registry.recordHookEvent(started, parentRunID: parent.id)
        XCTAssertEqual(repeated?.id, child.id)
        let stopped = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SubagentStop","session_id":"sess-1","agent_id":"agent-1","agent_type":"Explore","last_assistant_message":"ignored"}"#.utf8), source: .claude)
        let finishedChild = try await registry.recordHookEvent(stopped, parentRunID: parent.id)
        XCTAssertEqual(finishedChild?.status, .finished)
        try await registry.finishTerminalRun(parent.id)
        let restored = try AgentRunRegistry(url: url)
        let runs = await restored.allRuns()
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.first(where: { $0.id == parent.id })?.status, .finished)
        XCTAssertEqual(runs.first(where: { $0.id == child.id })?.status, .finished)
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testUncorrelatedAndTextEventsNeverBecomeChildren() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let parent = try await registry.recordTerminalStart(terminalID: UUID(), provider: .codex, processID: 1234)
        let child = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SubagentStart","session_id":"sess-1","agent_id":"agent-1","agent_type":"worker"}"#.utf8), source: .codex)
        do {
            _ = try await registry.recordHookEvent(child, parentRunID: parent.id)
            XCTFail("Child must require an observed parent session")
        } catch AgentRegistryError.sessionMismatch {}
        XCTAssertThrowsError(try NativeAgentHookEvent.parse(Data("subagent agent-1 started".utf8), source: .codex))
        let runs = await registry.allRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertFalse(AgentIdentityCapability.current(for: .codex).liveSubagentCapture)
        XCTAssertTrue(AgentIdentityCapability.current(for: .codex).documentedSubagentHooks)
    }
}

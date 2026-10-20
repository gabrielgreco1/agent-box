import RackyCore
import CryptoKit
import Foundation
import XCTest
@testable import Racky

final class NativeAgentMonitorTests: XCTestCase {
    @MainActor
    func testParentSessionCheckDrainsAuthenticatedStartAndRejectsMismatch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-route-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let runID = UUID(), terminalID = UUID()
        let hook = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        let configuration = try ClaudeHookInboxConfiguration.create(runID: runID,
            directory: root.appendingPathComponent("hook"), hookScriptURL: hook)
        let monitor = NativeAgentMonitor(registry: registry, pollIntervalNanoseconds: 10_000_000_000)
        monitor.didStart(terminalID: terminalID, provider: .claude, processID: 42,
                         runID: runID, hook: configuration)
        try appendHook("SessionStart", agentID: "", agentType: "", configuration: configuration)
        let admitted = await monitor.verifiedParentSession(terminalID: terminalID,
                                                            runID: runID, sessionID: "new-session")
        let mismatched = await monitor.verifiedParentSession(terminalID: terminalID,
                                                              runID: runID, sessionID: "wrong-session")
        let wrongRun = await monitor.verifiedParentSession(terminalID: terminalID,
                                                            runID: UUID(), sessionID: "new-session")
        XCTAssertTrue(admitted)
        XCTAssertFalse(mismatched)
        XCTAssertFalse(wrongRun)
        XCTAssertEqual(monitor.runs.first(where: { $0.id == runID })?.nativeSessionID, "new-session")
        monitor.didExit(terminalID: terminalID, runID: runID)
    }

    @MainActor
    func testVerifiedCallerRequiresExactActiveNativeChildAndObservedParent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-route-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let runID = UUID(), terminalID = UUID()
        let hook = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        let configuration = try ClaudeHookInboxConfiguration.create(runID: runID,
            directory: root.appendingPathComponent("hook"), hookScriptURL: hook)
        let monitor = NativeAgentMonitor(registry: registry, pollIntervalNanoseconds: 10_000_000_000)
        monitor.didStart(terminalID: terminalID, provider: .claude, processID: 42,
                         runID: runID, hook: configuration)
        try appendHook("SessionStart", agentID: "", agentType: "", configuration: configuration)
        try appendHook("SubagentStart", agentID: "native-child", agentType: "Explore", configuration: configuration)
        let child = try await monitor.verifiedCaller(terminalID: terminalID, runID: runID,
                                                     sessionID: "new-session", agentID: "native-child")
        XCTAssertEqual(child.kind, .nativeSubagent)
        XCTAssertEqual(child.parentRunID, runID)
        let parent = try await monitor.verifiedCaller(terminalID: terminalID, runID: runID,
                                                      sessionID: "new-session", agentID: nil)
        XCTAssertEqual(parent.id, runID)
        await XCTAssertThrowsErrorAsync {
            _ = try await monitor.verifiedCaller(terminalID: terminalID, runID: runID,
                                                 sessionID: "wrong-session", agentID: "native-child")
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await monitor.verifiedCaller(terminalID: terminalID, runID: runID,
                                                 sessionID: "new-session", agentID: "another-child")
        }
        try appendHook("SubagentStop", agentID: "native-child", agentType: "Explore", configuration: configuration)
        await XCTAssertThrowsErrorAsync {
            _ = try await monitor.verifiedCaller(terminalID: terminalID, runID: runID,
                                                 sessionID: "new-session", agentID: "native-child")
        }
        monitor.didExit(terminalID: terminalID, runID: runID)
        await XCTAssertThrowsErrorAsync {
            _ = try await monitor.verifiedCaller(terminalID: terminalID, runID: runID,
                                                 sessionID: "new-session", agentID: nil)
        }
    }

    @MainActor
    func testExitDrainsAuthenticatedHooksBeforeClosingParent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let runID = UUID(), terminalID = UUID()
        let hook = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        let configuration = try ClaudeHookInboxConfiguration.create(runID: runID,
            directory: root.appendingPathComponent("hook"), hookScriptURL: hook)
        let monitor = NativeAgentMonitor(registry: registry, pollIntervalNanoseconds: 10_000_000_000)
        monitor.didStart(terminalID: terminalID, provider: .claude, processID: 42,
                         runID: runID, hook: configuration)
        let admitted = await waitUntil { monitor.runs.contains { $0.id == runID && $0.status == .running } }
        XCTAssertTrue(admitted)

        try appendHook("SessionStart", agentID: "", agentType: "", configuration: configuration)
        try appendHook("SubagentStart", agentID: "native-child", agentType: "Explore", configuration: configuration)
        try appendHook("SubagentStop", agentID: "native-child", agentType: "Explore", configuration: configuration)
        monitor.didExit(terminalID: terminalID, runID: runID)
        let drained = await waitUntil {
            monitor.runs.contains { $0.id == runID && $0.status == .finished } &&
            monitor.runs.contains { $0.parentRunID == runID && $0.nativeAgentID == "native-child" }
        }
        XCTAssertTrue(drained, "The final drain must admit an authenticated child before parent closure")
        XCTAssertNil(monitor.errorText)
        let child = try XCTUnwrap(monitor.runs.first { $0.parentRunID == runID })
        XCTAssertEqual(child.status, .finished, "The final drain must process child stop before closing parent")
    }

    @MainActor
    func testPreviousAppParentIsReconciledWithoutFinishingNativeChild() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        let parent = try await registry.recordTerminalStart(terminalID: UUID(), provider: .claude, processID: 42)
        let session = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SessionStart","session_id":"old"}"#.utf8), source: .claude)
        _ = try await registry.recordHookEvent(session, parentRunID: parent.id)
        let child = try NativeAgentHookEvent.parse(Data(#"{"hook_event_name":"SubagentStart","session_id":"old","agent_id":"child","agent_type":"Explore"}"#.utf8), source: .claude)
        _ = try await registry.recordHookEvent(child, parentRunID: parent.id)

        let monitor = NativeAgentMonitor(registry: registry)
        let reconciled = await waitUntil {
            monitor.runs.first { $0.id == parent.id }?.status == .finished
        }
        XCTAssertTrue(reconciled)
        XCTAssertEqual(monitor.runs.first { $0.parentRunID == parent.id }?.status, .running)
    }

    private func appendHook(_ event: String, agentID: String, agentType: String,
                            configuration: ClaudeHookInboxConfiguration) throws {
        let token = try XCTUnwrap(configuration.environment["RACKY_HOOK_TOKEN"])
        var key = Data()
        for offset in stride(from: 0, to: token.count, by: 2) {
            let start = token.index(token.startIndex, offsetBy: offset)
            let end = token.index(start, offsetBy: 2)
            key.append(try XCTUnwrap(UInt8(token[start..<end], radix: 16)))
        }
        let fields = [configuration.runID.uuidString, "new-session", event, agentID, agentType]
        let signed = Data((fields.joined(separator: "\n") + "\n").utf8)
        let signature = Data(HMAC<SHA256>.authenticationCode(for: signed, using: SymmetricKey(data: key)))
            .map { String(format: "%02x", $0) }.joined()
        let envelope = ["run_id": fields[0], "session_id": fields[1], "hook_event_name": event,
                        "agent_id": agentID, "agent_type": agentType, "signature": signature]
        var line = try JSONSerialization.data(withJSONObject: envelope)
        line.append(10)
        let file = try FileHandle(forWritingTo: configuration.inboxURL)
        try file.seekToEnd()
        try file.write(contentsOf: line)
        try file.close()
    }

    @MainActor
    private func XCTAssertThrowsErrorAsync(_ operation: @MainActor () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Unverified caller must be rejected")
        } catch NativeAgentMonitorError.unverifiedCaller {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}

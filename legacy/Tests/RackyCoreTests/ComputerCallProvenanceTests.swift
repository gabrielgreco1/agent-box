import CryptoKit
import Foundation
import XCTest
@testable import RackyCore

final class ComputerCallProvenanceTests: XCTestCase {
    private let token = String(repeating: "ab", count: 32)
    private let tool = "mcp__racky__computer_input"
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    func testParentAndChildIdentityAndSignedArguments() async throws {
        let run = UUID()
        let verifier = try makeVerifier(run)
        let parent = try signedCall(run: run, agent: "", toolUse: "tool-parent",
                                    args: ["kind": "text", "text": "hello"])
        let verifiedParent = try await verifier.verify(toolName: tool, argumentsData: parent,
                                                        expectedSessionID: "session-A")
        XCTAssertNil(verifiedParent.agentID)
        XCTAssertEqual(verifiedParent.runID, run)
        XCTAssertEqual(verifiedParent.toolUseID, "tool-parent")
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: verifiedParent.argumentsData) as? [String: String])
        XCTAssertEqual(decoded, ["kind": "text", "text": "hello"])
        XCTAssertNil(decoded["route_token"])

        let child = try signedCall(run: run, agent: "child-1", toolUse: "tool-child",
                                   nonce: String(repeating: "c", count: 32), args: [:])
        let verifiedChild = try await verifier.verify(toolName: tool, argumentsData: child)
        XCTAssertEqual(verifiedChild.agentID, "child-1")
        XCTAssertEqual(verifiedChild.sessionID, "session-A")
    }

    func testRejectsReplayAndMismatchWithoutConsumingTheGoodCall() async throws {
        let run = UUID()
        let verifier = try makeVerifier(run)
        let good = try signedCall(run: run, agent: "child-1", toolUse: "tool-1",
                                  args: ["kind": "key", "key": "Return"])
        try await rejects(verifier, toolName: "mcp__racky__computer_mode", data: good)
        try await rejects(verifier, toolName: tool, data: good, session: "different-session")
        var tampered = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        tampered["key"] = "Escape"
        try await rejects(verifier, toolName: tool, data: try JSONSerialization.data(withJSONObject: tampered))
        _ = try await verifier.verify(toolName: tool, argumentsData: good)
        try await rejects(verifier, toolName: tool, data: good)
    }

    func testRejectsWrongRunMissingTokenExpiredAndFutureAssertions() async throws {
        let run = UUID()
        let verifier = try makeVerifier(run)
        try await rejects(verifier, toolName: tool, data: Data("{}".utf8))
        try await rejects(verifier, toolName: tool,
                          data: try signedCall(run: UUID(), agent: "", toolUse: "wrong-run", args: [:]))
        try await rejects(verifier, toolName: tool,
                          data: try signedCall(run: run, agent: "", toolUse: "expired", args: [:],
                                               issuedAt: Int(instant.timeIntervalSince1970) - 901))
        try await rejects(verifier, toolName: tool,
                          data: try signedCall(run: run, agent: "", toolUse: "future", args: [:],
                                               issuedAt: Int(instant.timeIntervalSince1970) + 31))
    }

    func testPythonHookTokenVerifiesInSwift() async throws {
        let run = UUID()
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        let event: [String: Any] = ["hook_event_name": "PreToolUse", "session_id": "session-A",
            "agent_id": "child-native", "tool_use_id": "tool-native", "tool_name": tool,
            "tool_input": ["kind": "text", "text": "😀 hello", "route_token": "spoofed"]]
        let process = Process()
        process.executableURL = script
        process.environment = ProcessInfo.processInfo.environment.merging([
            "RACKY_HOOK_RUN_ID": run.uuidString, "RACKY_HOOK_TOKEN": token
        ]) { _, replacement in replacement }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: event))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any])
        let specific = try XCTUnwrap(response["hookSpecificOutput"] as? [String: Any])
        XCTAssertNil(specific["permissionDecision"])
        let arguments = try XCTUnwrap(specific["updatedInput"] as? [String: Any])
        let verifier = try ComputerCallProvenanceVerifier(runID: run, tokenHex: token)
        let verified = try await verifier.verify(toolName: tool,
            argumentsData: JSONSerialization.data(withJSONObject: arguments), expectedSessionID: "session-A")
        XCTAssertEqual(verified.agentID, "child-native")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: verified.argumentsData) as? [String: String])
        XCTAssertEqual(original, ["kind": "text", "text": "😀 hello"])
    }

    private func makeVerifier(_ run: UUID) throws -> ComputerCallProvenanceVerifier {
        let clock = instant
        return try ComputerCallProvenanceVerifier(runID: run, tokenHex: token, now: { clock })
    }

    private func rejects(_ verifier: ComputerCallProvenanceVerifier, toolName: String,
                         data: Data, session: String? = nil) async throws {
        do {
            _ = try await verifier.verify(toolName: toolName, argumentsData: data, expectedSessionID: session)
            XCTFail("Expected invalid provenance")
        } catch ComputerCallProvenanceError.invalid { }
    }

    private func signedCall(run: UUID, agent: String, toolUse: String,
                            nonce: String = String(repeating: "b", count: 32),
                            args: [String: Any], issuedAt: Int? = nil) throws -> Data {
        let envelope: [String: Any] = ["v": 1, "run_id": run.uuidString, "session_id": "session-A",
            "agent_id": agent, "tool_use_id": toolUse, "tool_name": tool,
            "issued_at": issuedAt ?? Int(instant.timeIntervalSince1970), "nonce": nonce,
            "arguments": args]
        let payload = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        let bytes = Data(stride(from: 0, to: token.count, by: 2).map { index -> UInt8 in
            let start = token.index(token.startIndex, offsetBy: index)
            let end = token.index(start, offsetBy: 2)
            return UInt8(token[start..<end], radix: 16)!
        })
        let signature = HMAC<SHA256>.authenticationCode(for: payload, using: SymmetricKey(data: bytes))
            .map { String(format: "%02x", $0) }.joined()
        var outer = args
        outer["route_token"] = payload.base64EncodedString() + "." + signature
        return try JSONSerialization.data(withJSONObject: outer)
    }
}

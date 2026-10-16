import Foundation
import XCTest
@testable import AgentBox
@testable import AgentBoxCore

final class AgentComputerAccessRoutingTests: XCTestCase {
    @MainActor
    func testNativeChildCannotInheritParentComputerRoute() throws {
        let run = UUID()
        let child = VerifiedComputerCall(runID: run, sessionID: "native-session",
            agentID: "child-1", toolUseID: "tool-1", argumentsData: Data("{}".utf8))
        XCTAssertThrowsError(try AgentComputerAccess.requireParentRoute(child, currentRunID: run)) {
            XCTAssertEqual($0 as? ComputerCallProvenanceError, .childRoutingPending)
        }
        let parent = VerifiedComputerCall(runID: run, sessionID: "native-session",
            agentID: nil, toolUseID: "tool-2", argumentsData: Data("{}".utf8))
        XCTAssertNoThrow(try AgentComputerAccess.requireParentRoute(parent, currentRunID: run))
        XCTAssertThrowsError(try AgentComputerAccess.requireParentRoute(parent, currentRunID: UUID())) {
            XCTAssertEqual($0 as? ComputerCallProvenanceError, .invalid)
        }
    }

    func testMCPReportsChildRoutingErrorWithoutPrivateArguments() async throws {
        let protocolServer = ComputerMCPProtocol { _, _ in
            throw ComputerCallProvenanceError.childRoutingPending
        }
        _ = try await protocolServer.respond(try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize"
        ]))
        let request: [String: Any] = ["jsonrpc": "2.0", "id": 2,
            "method": "tools/call", "params": ["name": "computer_status",
            "arguments": ["route_token": "private-token-do-not-print"]]]
        let data = try await protocolServer.respond(JSONSerialization.data(withJSONObject: request))
        let reply = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertTrue((content.first?["text"] as? String ?? "").contains("separate box"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-token-do-not-print"))
    }
}

import Foundation
import XCTest
@testable import AgentBoxCore

final class ComputerMCPProtocolTests: XCTestCase {
    func testInitializeNegotiatesVersionAndListsOnlyDeclaredTools() async throws {
        let endpoint = ComputerMCPProtocol { _, _ in .text("unused") }
        let initialized = try await response(endpoint, method: "initialize", id: 1,
                                             params: ["protocolVersion": "2025-06-18"])
        let result = try XCTUnwrap(initialized["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        let server = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(server["name"] as? String, "agentbox")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])

        let listed = try await response(endpoint, method: "tools/list", id: "list")
        let toolsResult = try XCTUnwrap(listed["result"] as? [String: Any])
        let tools = try XCTUnwrap(toolsResult["tools"] as? [[String: Any]])
        XCTAssertEqual(Set(tools.compactMap { $0["name"] as? String }), Set([
            "computer_status", "computer_screenshot", "computer_mode", "computer_navigate",
            "computer_input", "computer_request_help"
        ]))
        for tool in tools {
            let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
            XCTAssertEqual(schema["type"] as? String, "object")
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        }
    }

    func testNotificationsReturnNoResponseAndUnknownMethodsAreRejected() async throws {
        let endpoint = ComputerMCPProtocol { _, _ in .text("unused") }
        let notification = try request(method: "notifications/initialized", id: nil)
        let beforeInitialization = try await endpoint.respond(notification)
        XCTAssertTrue(beforeInitialization.isEmpty)
        _ = try await response(endpoint, method: "initialize", id: 1)
        let afterInitialization = try await endpoint.respond(notification)
        XCTAssertTrue(afterInitialization.isEmpty)

        let unknown = try await response(endpoint, method: "unknown/method", id: 2)
        let error = try XCTUnwrap(unknown["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32601)
        XCTAssertNil(unknown["result"])
        let unknownTool = try await response(endpoint, method: "tools/call", id: 3,
                                             params: ["name": "computer_shell", "arguments": [:]])
        let toolError = try XCTUnwrap(unknownTool["error"] as? [String: Any])
        XCTAssertEqual(toolError["code"] as? Int, -32602)
    }

    func testToolFailureReturnsSafeErrorWithoutHandlerDetails() async throws {
        let secret = "internal token abc123 and private runtime path"
        let endpoint = ComputerMCPProtocol { _, _ in
            throw NSError(domain: secret, code: 17, userInfo: [NSLocalizedDescriptionKey: secret])
        }
        _ = try await response(endpoint, method: "initialize", id: 1)
        let reply = try await response(endpoint, method: "tools/call", id: 2,
                                       params: ["name": "computer_status", "arguments": [:]])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertFalse((content.first?["text"] as? String ?? "").contains(secret))
        XCTAssertFalse(String(data: try JSONSerialization.data(withJSONObject: reply), encoding: .utf8)!.contains(secret))
    }

    func testJPEGToolResultUsesMCPImageContent() async throws {
        let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
        let endpoint = ComputerMCPProtocol { name, _ in
            XCTAssertEqual(name, "computer_screenshot")
            return .jpeg(jpeg)
        }
        _ = try await response(endpoint, method: "initialize", id: 1)
        let reply = try await response(endpoint, method: "tools/call", id: 2,
                                       params: ["name": "computer_screenshot", "arguments": [:]])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "image")
        XCTAssertEqual(content[0]["mimeType"] as? String, "image/jpeg")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(content[0]["data"] as? String)), jpeg)
    }

    func testToolCallsBeforeInitializeAreDeniedWithoutInvokingHandler() async throws {
        let calls = MCPCallCount()
        let endpoint = ComputerMCPProtocol { _, _ in
            await calls.record()
            return .text("should not execute")
        }
        let reply = try await response(endpoint, method: "tools/call", id: 1,
                                       params: ["name": "computer_status", "arguments": [:]])
        let error = try XCTUnwrap(reply["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32002)
        let count = await calls.count
        XCTAssertEqual(count, 0)
    }

    private func response(_ endpoint: ComputerMCPProtocol, method: String, id: Any,
                          params: [String: Any]? = nil) async throws -> [String: Any] {
        let data = try await endpoint.respond(request(method: method, id: id, params: params))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func request(method: String, id: Any?, params: [String: Any]? = nil) throws -> Data {
        var message: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { message["id"] = id }
        if let params { message["params"] = params }
        return try JSONSerialization.data(withJSONObject: message)
    }
}

private actor MCPCallCount {
    private(set) var count = 0
    func record() { count += 1 }
}

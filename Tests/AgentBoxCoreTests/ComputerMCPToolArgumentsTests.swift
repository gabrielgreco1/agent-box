import Foundation
import XCTest
@testable import AgentBoxCore

final class ComputerMCPToolArgumentsTests: XCTestCase {
    func testValidToolsDecodeToTypedArguments() throws {
        guard case .status = try decode("computer_status", [:]) else { return XCTFail("Expected status") }
        guard case .screenshot = try decode("computer_screenshot", [:]) else { return XCTFail("Expected screenshot") }
        guard case .mode(.desktop) = try decode("computer_mode", ["mode": "desktop"]) else {
            return XCTFail("Expected desktop mode")
        }
        guard case .navigate(let url) = try decode("computer_navigate", ["url": "https://example.com/path?q=1"]) else {
            return XCTFail("Expected navigation")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com/path?q=1")
        try assertInput(["kind": "move", "x": 1279, "y": 799], expected: ["kind": "move", "x": 1279, "y": 799])
        try assertInput(["kind": "click", "button": 3], expected: ["kind": "click", "button": 3])
        try assertInput(["kind": "key", "key": "Return"], expected: ["kind": "key", "key": "Return"])
        try assertInput(["kind": "text", "text": "Hello"], expected: ["kind": "text", "text": "Hello"])
        try assertInput(["kind": "scroll", "direction": "down", "clicks": 20],
                        expected: ["kind": "scroll", "direction": "down", "clicks": 20])
        guard case .requestHelp = try decode("computer_request_help", ["reason": "Please help with login"]) else {
            return XCTFail("Expected help request")
        }
    }

    func testRejectsUnknownKeysAndMalformedValues() throws {
        let cases: [(String, [String: Any])] = [
            ("computer_status", ["extra": true]),
            ("computer_screenshot", ["mode": "desktop"]),
            ("computer_mode", ["mode": "desktop", "extra": 1]),
            ("computer_mode", ["mode": "invalid"]),
            ("computer_navigate", ["url": "file:///etc/passwd"]),
            ("computer_navigate", ["url": "https://user:password@example.com/"]),
            ("computer_navigate", ["url": "https://example.com", "extra": "ignored"]),
            ("computer_input", ["kind": "move", "x": 1, "y": 2, "button": 1]),
            ("computer_input", ["kind": "click", "button": 1, "x": 2]),
            ("computer_input", ["kind": "move", "x": -1, "y": 0]),
            ("computer_input", ["kind": "move", "x": 1280, "y": 0]),
            ("computer_input", ["kind": "move", "x": 0, "y": 800]),
            ("computer_input", ["kind": "click", "button": 4]),
            ("computer_input", ["kind": "key", "key": ""]),
            ("computer_input", ["kind": "text", "text": String(repeating: "x", count: 4097)]),
            ("computer_input", ["kind": "scroll", "direction": "diagonal", "clicks": 1]),
            ("computer_input", ["kind": "scroll", "direction": "up", "clicks": 0]),
            ("computer_request_help", ["reason": "   "]),
            ("computer_request_help", ["reason": String(repeating: "x", count: 501)]),
            ("computer_request_help", ["reason": "help", "secret": "not accepted"]),
            ("unknown_tool", [:])
        ]
        for (name, arguments) in cases {
            XCTAssertThrowsError(try decode(name, arguments), "Accepted invalid arguments for \(name): \(arguments)")
        }
        XCTAssertThrowsError(try ComputerMCPToolArguments.validate(name: "computer_status", data: Data("[]".utf8)))
        XCTAssertThrowsError(try ComputerMCPToolArguments.validate(name: "computer_status", data: Data("not JSON".utf8)))
    }

    func testRejectsBooleansAndNonIntegerNumbersInIntegerFields() throws {
        let invalidValues: [Any] = [true, false, 1.5, Int64.max]
        for invalid in invalidValues {
            XCTAssertThrowsError(try decode("computer_input", ["kind": "move", "x": invalid, "y": 1]))
            XCTAssertThrowsError(try decode("computer_input", ["kind": "click", "button": invalid]))
            XCTAssertThrowsError(try decode("computer_input", ["kind": "scroll", "direction": "up", "clicks": invalid]))
        }
    }

    private func decode(_ name: String, _ arguments: [String: Any]) throws -> ComputerMCPToolArguments {
        let data = try JSONSerialization.data(withJSONObject: arguments)
        return try ComputerMCPToolArguments.validate(name: name, data: data)
    }

    private func assertInput(_ arguments: [String: Any], expected: [String: Any]) throws {
        guard case .input(let input) = try decode("computer_input", arguments) else {
            return XCTFail("Expected desktop input")
        }
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
        XCTAssertEqual(encoded as NSDictionary, expected as NSDictionary)
    }
}

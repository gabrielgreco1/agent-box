import Foundation
import Darwin
import XCTest
@testable import AgentBoxCore

final class LocalMCPChannelTests: XCTestCase {
    func testHelperExitsWhenInFlightSocketFailsWhileStdinRemainsOpen() throws {
        let (directory, socketPath) = try socketFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capability = "failure-fixture-capability"
        let capabilityFile = directory.appendingPathComponent("capability")
        try Data("\(capability)\n".utf8).write(to: capabilityFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: capabilityFile.path)
        let callEntered = DispatchSemaphore(value: 0)
        let server = try LocalMCPServer(socketPath: socketPath, capability: capability) { message in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
            switch object["method"] as? String {
            case "initialize":
                return Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}"#.utf8)
            case "notifications/initialized": return Data()
            case "tools/call":
                callEntered.signal()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return Data(#"{"jsonrpc":"2.0","id":2,"result":{}}"#.utf8)
            default: throw LocalMCPError.malformedMessage
            }
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = try helperExecutable()
        process.arguments = ["--socket", socketPath, "--capability-file", capabilityFile.path]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + .seconds(2)) != .success {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + .seconds(2))
                }
            }
        }
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"computer_status","arguments":{}}}"#
        ]
        try input.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
        XCTAssertEqual(callEntered.wait(timeout: .now() + .seconds(5)), .success,
                       "The tool call must reach a concurrent socket worker")
        guard process.isRunning else { return }
        // Shut down the accepted socket but deliberately keep helper stdin
        // open. The helper must close stdout instead of waiting for another line.
        server.stop()
        XCTAssertEqual(finished.wait(timeout: .now() + .seconds(3)), .success,
                       "A failed worker must terminate without waiting for stdin EOF")
        guard !process.isRunning else { return }
        XCTAssertEqual(process.terminationStatus, 3)
        XCTAssertTrue(errors.fileHandleForReading.readDataToEndOfFile().isEmpty)
        let lines = try XCTUnwrap(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
            .split(separator: "\n")
        XCTAssertEqual(lines.compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["id"] as? Int
        }, [1], "The failed call must not receive an invented response")
    }

    func testPackagedHelperForwardsEightConcurrentCallsWithExactResponseIDs() throws {
        let (directory, socketPath) = try socketFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capability = "concurrent-fixture-capability"
        let capabilityFile = directory.appendingPathComponent("capability")
        try Data("\(capability)\n".utf8).write(to: capabilityFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: capabilityFile.path)
        let counter = ForwardingCounter()
        let server = try LocalMCPServer(socketPath: socketPath, capability: capability) { message in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
            let method = try XCTUnwrap(object["method"] as? String)
            if method == "initialize" {
                counter.markInitialize()
                return Data(#"{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18"}}"#.utf8)
            }
            if method == "notifications/initialized" {
                counter.markNotification()
                return Data()
            }
            let id = try XCTUnwrap(object["id"] as? Int)
            counter.enter()
            try await Task.sleep(nanoseconds: id == 2 ? 300_000_000 : 70_000_000)
            counter.leave()
            return try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": id, "result": ["seen": id]])
        }
        defer { server.stop() }
        let process = Process()
        process.executableURL = try helperExecutable()
        process.arguments = ["--socket", socketPath, "--capability-file", capabilityFile.path]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + .seconds(2)) != .success {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + .seconds(2))
                }
            }
        }
        var requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        ]
        requests += (2...17).map { id in
            "{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"tools/call\",\"params\":{}}"
        }
        try input.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        XCTAssertEqual(finished.wait(timeout: .now() + .seconds(15)), .success,
                       "Concurrent helper did not drain all requests on EOF")
        guard !process.isRunning else { return }
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(errors.fileHandleForReading.readDataToEndOfFile().isEmpty)
        let lines = try XCTUnwrap(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 17)
        let responses = try lines.map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(responses.first?["id"] as? Int, 1, "Initialize must complete before tool responses")
        let toolResponses = responses.dropFirst()
        XCTAssertEqual(Set(toolResponses.compactMap { $0["id"] as? Int }), Set(2...17))
        for response in toolResponses {
            let id = try XCTUnwrap(response["id"] as? Int)
            XCTAssertEqual((response["result"] as? [String: Any])?["seen"] as? Int, id)
        }
        let observed = counter.snapshot()
        XCTAssertTrue(observed.initializeBeforeNotification)
        XCTAssertFalse(observed.toolBeforeNotification)
        XCTAssertGreaterThan(observed.peak, 1, "Fixture must observe actual concurrent forwarding")
        XCTAssertLessThanOrEqual(observed.peak, 8)
    }

    func testPackagedStdioHelperForwardsMCPAndExitsOnEOF() throws {
        let (directory, socketPath) = try socketFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capability = "integration-capability"
        let capabilityFile = directory.appendingPathComponent("capability")
        try Data("\(capability)\n".utf8).write(to: capabilityFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: capabilityFile.path)

        let endpoint = ComputerMCPProtocol { name, arguments in
            guard name == "computer_status",
                  let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any],
                  object.isEmpty else { throw LocalMCPError.malformedMessage }
            return .text("fake computer is ready")
        }
        let server = try LocalMCPServer(socketPath: socketPath, capability: capability) { message in
            try await endpoint.respond(message)
        }
        defer { server.stop() }

        let process = Process()
        process.executableURL = try helperExecutable()
        process.arguments = ["--socket", socketPath, "--capability-file", capabilityFile.path]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                if finished.wait(timeout: .now() + .seconds(2)) != .success {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + .seconds(2))
                }
            }
        }

        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"computer_status","arguments":{}}}"#
        ]
        try input.fileHandleForWriting.write(contentsOf: Data((requests.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        XCTAssertEqual(finished.wait(timeout: .now() + .seconds(15)), .success,
                       "AgentBoxMCP did not exit after stdin EOF")
        guard !process.isRunning else { return }
        XCTAssertEqual(process.terminationStatus, 0)
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        XCTAssertTrue(stderr.isEmpty, "AgentBoxMCP emitted unexpected stderr")
        let lines = try XCTUnwrap(String(data: stdout, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.last, "")
        XCTAssertEqual(lines.count, 4, "Expected exactly three JSON-RPC responses and no notification output")
        guard lines.count == 4 else { return }
        let responses = try lines.dropLast().map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
        XCTAssertEqual(responses.first?["id"] as? Int, 1)
        XCTAssertEqual(Set(responses.compactMap { $0["id"] as? Int }), Set([1, 2, 3]))
        XCTAssertEqual((responses[0]["result"] as? [String: Any])?["protocolVersion"] as? String, "2025-06-18")
        let listResponse = try XCTUnwrap(responses.first { $0["id"] as? Int == 2 })
        let callResponse = try XCTUnwrap(responses.first { $0["id"] as? Int == 3 })
        let tools = try XCTUnwrap((listResponse["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertTrue(tools.contains { $0["name"] as? String == "computer_status" })
        let result = try XCTUnwrap(callResponse["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "fake computer is ready")
    }

    func testAuthenticatedRoundTripNotificationAndWrongCapability() throws {
        let (directory, path) = try socketFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try LocalMCPServer(socketPath: path, capability: "secret-capability") { message in
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: message) as? [String: Any])
            if object["id"] == nil { return Data() }
            return Data(#"{"jsonrpc":"2.0","id":7,"result":{"ok":true}}"#.utf8)
        }
        defer { server.stop() }
        let request = Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/list"}"#.utf8)
        let response = try LocalMCPClient.send(message: request, socketPath: path, capability: "secret-capability")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        XCTAssertNotNil(json["result"])
        let chunkedRequest = Data("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"text\":\"\(String(repeating: "x", count: 32_000))\"}}".utf8)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with:
            LocalMCPClient.send(message: chunkedRequest, socketPath: path, capability: "secret-capability")))
        let notification = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        XCTAssertTrue(try LocalMCPClient.send(message: notification, socketPath: path,
                                                capability: "secret-capability").isEmpty)
        let denied = try LocalMCPClient.send(message: request, socketPath: path, capability: "wrong")
        let error = try XCTUnwrap((JSONSerialization.jsonObject(with: denied) as? [String: Any])?["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32001)
    }

    func testSocketPermissionsLimitsAndStop() throws {
        let (directory, path) = try socketFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try LocalMCPServer(socketPath: path, capability: "cap") { _ in
            Data(repeating: 32, count: 12 * 1_048_576 + 1)
        }
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        let request = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call"}"#.utf8)
        let oversizedResponse = try LocalMCPClient.send(message: request, socketPath: path, capability: "cap")
        let response = try XCTUnwrap(JSONSerialization.jsonObject(with: oversizedResponse) as? [String: Any])
        XCTAssertNotNil(response["error"])
        let oversizedRequest = Data("{\"data\":\"\(String(repeating: "a", count: 65_536))\"}".utf8)
        XCTAssertThrowsError(try LocalMCPClient.send(message: oversizedRequest, socketPath: path, capability: "cap")) {
            XCTAssertEqual($0 as? LocalMCPError, .messageTooLarge)
        }
        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertThrowsError(try LocalMCPClient.send(message: request, socketPath: path, capability: "cap"))
        let replacement = try LocalMCPServer(socketPath: path, capability: "next-cap") { _ in
            Data(#"{"jsonrpc":"2.0","id":1,"result":{"restarted":true}}"#.utf8)
        }
        defer { replacement.stop() }
        server.stop()
        let restarted = try LocalMCPClient.send(message: request, socketPath: path, capability: "next-cap")
        XCTAssertEqual(((try JSONSerialization.jsonObject(with: restarted) as? [String: Any])?["result"] as? [String: Any])?["restarted"] as? Bool, true)
    }

    func testExistingPathAndInsecureDirectoryAreRejected() throws {
        let (directory, path) = try socketFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: "/tmp")
        XCTAssertThrowsError(try LocalMCPServer(socketPath: path, capability: "cap") { _ in Data() }) {
            XCTAssertEqual($0 as? LocalMCPError, .socketExists)
        }
        try FileManager.default.removeItem(atPath: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try LocalMCPServer(socketPath: path, capability: "cap") { _ in Data() }) {
            XCTAssertEqual($0 as? LocalMCPError, .insecureDirectory)
        }
    }

    private func socketFixture() throws -> (URL, String) {
        let directory = URL(fileURLWithPath: "/tmp/mcp-\(UUID().uuidString.prefix(12))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return (directory, directory.appendingPathComponent("channel.sock").path)
    }

    private func helperExecutable() throws -> URL {
        let startingPoints = [Bundle(for: Self.self).bundleURL,
                              Bundle.main.executableURL,
                              URL(fileURLWithPath: CommandLine.arguments[0])].compactMap { $0 }
        for start in startingPoints {
            var directory = start.resolvingSymlinksInPath().deletingLastPathComponent()
            for _ in 0..<8 {
                let candidate = directory.appendingPathComponent("AgentBoxMCP")
                if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
                directory.deleteLastPathComponent()
            }
        }
        let missing: URL? = nil
        return try XCTUnwrap(missing, "AgentBoxMCP executable is missing beside the test bundle; build the executable target")
    }
}

private final class ForwardingCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var initialized = false
    private var notification = false
    private var initializeBeforeNotification = false
    private var toolBeforeNotification = false
    private var active = 0
    private var peak = 0

    func markInitialize() {
        lock.lock(); initialized = true; lock.unlock()
    }
    func markNotification() {
        lock.lock(); initializeBeforeNotification = initialized; notification = true; lock.unlock()
    }
    func enter() {
        lock.lock()
        if !notification { toolBeforeNotification = true }
        active += 1
        peak = max(peak, active)
        lock.unlock()
    }
    func leave() {
        lock.lock(); active -= 1; lock.unlock()
    }
    func snapshot() -> (initializeBeforeNotification: Bool, toolBeforeNotification: Bool, peak: Int) {
        lock.lock(); defer { lock.unlock() }
        return (initializeBeforeNotification, toolBeforeNotification, peak)
    }
}

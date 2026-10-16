import Foundation
import XCTest
@testable import AgentBoxCore

final class BrowserComputerServiceTests: XCTestCase {
    func testCreateUsesBoundedDockerProfileAndReconnectsOnlyVerifiedHealth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let policyStore = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        try policyStore.save(ComputerPolicy(creation: .manual, limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 2)))
        let runner = FakeBrowserDockerRunner()
        let tokens = FakeBrowserTokenStore()
        let service = BrowserComputerService(runner: runner, tokens: tokens, policyStore: policyStore,
                                             metadataStore: BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json")))
        let terminalID = UUID()
        let computer = try service.createAndStart(for: terminalID)
        XCTAssertEqual(computer.terminalID, terminalID)
        XCTAssertTrue(computer.running)
        let create = try XCTUnwrap(runner.commands.first(where: { $0.first == "create" }))
        XCTAssertTrue(create.contains("127.0.0.1::8765"))
        XCTAssertTrue(create.contains("--read-only"))
        XCTAssertTrue(create.contains("/home/agentbox:rw,nosuid,nodev,size=32m,uid=10001,gid=10001"))
        XCTAssertTrue(create.contains("type=volume,source=\(computer.volumeName),target=/data"))
        XCTAssertFalse(create.contains("--privileged"))
        XCTAssertFalse(create.contains("-v"))
        let envPath = try XCTUnwrap(create.firstIndex(of: "--env-file").map { create[$0 + 1] })
        XCTAssertFalse(FileManager.default.fileExists(atPath: envPath))
        XCTAssertEqual(try service.metadataStore.load().first?.computerID, computer.id)
        let storedToken = try tokens.read(computerID: computer.id)
        XCTAssertGreaterThanOrEqual(storedToken.count, 32)

        // Fresh computers start at generation zero before the first browser transition.
        BrowserServiceURLProtocol.healthJSON = #"{"computer_id":"\#(computer.id.uuidString)","generation":0,"mode":"http","browser_ready":false,"display_ready":false,"frame_source":"none","active_lease":null}"#
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserServiceURLProtocol.self]
        let endpoint = try await service.reconnectEndpoint(computerID: computer.id,
                                                           session: URLSession(configuration: config))
        XCTAssertEqual(endpoint.generation, 0)
        XCTAssertEqual(endpoint.computerID, computer.id)
        XCTAssertEqual(endpoint.baseURL.host, "127.0.0.1")
        try service.stop(computerID: computer.id)
        XCTAssertFalse(try XCTUnwrap(service.computer(for: terminalID)).running)
    }

    func testDisabledPolicyAndWrongHealthDoNotYieldEndpoint() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let policyStore = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        let runner = FakeBrowserDockerRunner()
        let tokens = FakeBrowserTokenStore()
        let service = BrowserComputerService(runner: runner, tokens: tokens, policyStore: policyStore,
                                             metadataStore: BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json")))
        XCTAssertThrowsError(try service.createAndStart(for: UUID()))
        XCTAssertFalse(runner.commands.contains(where: { $0.first == "create" }))
        try policyStore.save(ComputerPolicy(creation: .manual, limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 2)))
        let computer = try service.createAndStart(for: UUID())
        BrowserServiceURLProtocol.healthJSON = #"{"computer_id":"\#(UUID().uuidString)","generation":1,"mode":"http","browser_ready":false,"display_ready":false,"frame_source":"none","active_lease":null}"#
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserServiceURLProtocol.self]
        do {
            _ = try await service.reconnectEndpoint(computerID: computer.id,
                                                    session: URLSession(configuration: config))
            XCTFail("Wrong computer health must be rejected")
        } catch BrowserComputerError.notReady {}
    }

    func testKeychainGateTimesOutAndDoesNotQueueAnotherRead() throws {
        let gate = KeychainReadGate()
        let release = DispatchSemaphore(value: 0)
        XCTAssertThrowsError(try gate.execute(timeout: 0.05) {
            _ = release.wait(timeout: .now() + 2)
            return "late token"
        }) { XCTAssertEqual($0 as? BrowserComputerError, .keychainTimedOut) }
        var startedAnotherRead = false
        XCTAssertThrowsError(try gate.execute(timeout: 0.05) {
            startedAnotherRead = true
            return "other token"
        }) { XCTAssertEqual($0 as? BrowserComputerError, .keychainTimedOut) }
        XCTAssertFalse(startedAnotherRead)
        release.signal()
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if let value = try? gate.execute(timeout: 0.05, onTimeout: {}, { "recovered" }) {
                XCTAssertEqual(value, "recovered")
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTFail("Gate did not recover after the worker completed")
    }

    func testReconnectRequiresExplicitAuthorizationWhenFakeTokenStoreRequestsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let policyStore = ComputerPolicyStore(fileURL: root.appendingPathComponent("policy.json"))
        try policyStore.save(ComputerPolicy(creation: .manual, limits: .init(cpus: 1, memoryMiB: 2048, maxComputers: 2)))
        let tokens = FakeBrowserTokenStore()
        let service = BrowserComputerService(runner: FakeBrowserDockerRunner(), tokens: tokens,
            policyStore: policyStore,
            metadataStore: BrowserComputerMetadataStore(url: root.appendingPathComponent("metadata.json")))
        let computer = try service.createAndStart(for: UUID())
        tokens.requiresAuthorization = true
        do {
            _ = try await service.reconnectEndpoint(computerID: computer.id)
            XCTFail("Automatic lookup must not authorize")
        } catch BrowserComputerError.tokenAuthorizationRequired {}
        BrowserServiceURLProtocol.healthJSON = #"{"computer_id":"\#(computer.id.uuidString)","generation":0,"mode":"http","browser_ready":false,"display_ready":false,"frame_source":"none","active_lease":null}"#
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BrowserServiceURLProtocol.self]
        let endpoint = try await service.reconnectEndpoint(computerID: computer.id,
            session: URLSession(configuration: config), interactiveAuthorization: true)
        XCTAssertEqual(endpoint.computerID, computer.id)
        XCTAssertEqual(tokens.interactiveReads, 1)
    }
}

private final class FakeBrowserTokenStore: BrowserComputerTokenStoring {
    private var values: [UUID: String] = [:]
    var requiresAuthorization = false
    var interactiveReads = 0
    func put(computerID: UUID, value: String) throws { values[computerID] = value }
    func read(computerID: UUID) throws -> String {
        if requiresAuthorization { throw BrowserComputerError.tokenAuthorizationRequired }
        guard let value = values[computerID] else { throw BrowserComputerError.missingToken }
        return value
    }
    func readInteractively(computerID: UUID) throws -> String {
        interactiveReads += 1
        guard let value = values[computerID] else { throw BrowserComputerError.missingToken }
        return value
    }
    func delete(computerID: UUID) throws { values.removeValue(forKey: computerID) }
}

private final class FakeBrowserDockerRunner: DockerCommandRunning {
    var commands: [[String]] = []
    private var containerID: String?
    private var computerID: UUID?
    private var terminalID: UUID?
    private var running = false
    func run(_ arguments: [String], timeout: TimeInterval) throws -> DockerCommandResult {
        commands.append(arguments)
        if arguments.first == "volume" {
            if arguments.dropFirst().first == "inspect" { return DockerCommandResult(exitCode: 1) }
            return DockerCommandResult(exitCode: 0, stdout: "volume\n")
        }
        if arguments.first == "ps" { return DockerCommandResult(exitCode: 0, stdout: running || arguments.contains("-a") ? (containerID.map { "\($0)\n" } ?? "") : "") }
        if arguments.first == "create" {
            containerID = String(repeating: "a", count: 64)
            let labels = arguments.filter { $0.hasPrefix("com.agentbox.browser-") }
            computerID = labels.first(where: { $0.hasPrefix("com.agentbox.browser-computer-id=") })
                .flatMap { UUID(uuidString: String($0.split(separator: "=").last!)) }
            terminalID = labels.first(where: { $0.hasPrefix("com.agentbox.browser-terminal-id=") })
                .flatMap { UUID(uuidString: String($0.split(separator: "=").last!)) }
            return DockerCommandResult(exitCode: 0, stdout: "\(containerID!)\n")
        }
        if arguments.first == "inspect" {
            guard let containerID, let computerID, let terminalID else { return DockerCommandResult(exitCode: 1) }
            let json = #"{"Id":"\#(containerID)","Name":"/agentbox-browser-\#(computerID.uuidString.lowercased())","Config":{"Labels":{"com.agentbox.browser-managed":"true","com.agentbox.browser-computer-id":"\#(computerID.uuidString.lowercased())","com.agentbox.browser-terminal-id":"\#(terminalID.uuidString.lowercased())"}},"State":{"Running":\#(running)}}"#
            return DockerCommandResult(exitCode: 0, stdout: json)
        }
        if arguments.first == "start" { running = true; return DockerCommandResult(exitCode: 0) }
        if arguments.first == "stop" { running = false; return DockerCommandResult(exitCode: 0) }
        if arguments.first == "port" { return DockerCommandResult(exitCode: 0, stdout: "127.0.0.1:49152\n") }
        return DockerCommandResult(exitCode: 0)
    }
}

private final class BrowserServiceURLProtocol: URLProtocol {
    static var healthJSON = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Data(Self.healthJSON.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

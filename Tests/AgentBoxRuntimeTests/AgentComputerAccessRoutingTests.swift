import AgentBoxCore
import CryptoKit
import Foundation
import XCTest
@testable import AgentBox

final class AgentComputerAccessRoutingTests: XCTestCase {
    @MainActor
    func testConnectedChildCannotKeepUsingReplacedScrapingContext() async throws {
        let fixture = try await RoutingFixture(creation: .automatic)
        defer { fixture.shutdown() }
        try fixture.appendHook("SessionStart")
        try fixture.appendHook("SubagentStart", agentID: "one")
        _ = try await fixture.call("computer_acquire", agentID: "one", arguments: ["mode": "headless"])
        let computer = try await fixture.childComputer("one")
        let path = try XCTUnwrap(fixture.launch.claudeHookDescriptor?.childContextPath)
        try Data("replaced context".utf8).write(to: URL(fileURLWithPath: path))
        do {
            _ = try await fixture.call("computer_page", agentID: "one")
            XCTFail("Cached child controller must revalidate its reviewed skill")
        } catch AgentLaunchError.contextChanged {}
        try fixture.appendHook("SubagentStop", agentID: "one")
        let stopped = await fixture.waitUntil { await fixture.resources.wasStopped(computer.id) }
        XCTAssertTrue(stopped)
    }

    @MainActor
    func testTwoNativeChildrenRouteToOwnBoxesAndLeaveParentUnchanged() async throws {
        let fixture = try await RoutingFixture(creation: .automatic)
        defer { fixture.shutdown() }
        try fixture.appendHook("SessionStart")
        try fixture.appendHook("SubagentStart", agentID: "one")
        try fixture.appendHook("SubagentStart", agentID: "two")
        let parentPage = try await fixture.call("computer_page", agentID: nil)
        XCTAssertEqual(try fixture.pageTitle(parentPage), "Page-\(fixture.parentID.uuidString)")
        _ = try await fixture.call("computer_acquire", agentID: "one", arguments: ["mode": "headless"])
        _ = try await fixture.call("computer_acquire", agentID: "two", arguments: ["mode": "headless"])
        let one = try await fixture.childComputer("one")
        let two = try await fixture.childComputer("two")
        XCTAssertNotEqual(one.id, two.id)
        XCTAssertNotEqual(one.id, fixture.parentID)
        XCTAssertNotEqual(two.id, fixture.parentID)
        let onePage = try await fixture.call("computer_page", agentID: "one")
        let twoPage = try await fixture.call("computer_page", agentID: "two")
        let parentAgain = try await fixture.call("computer_page", agentID: nil)
        XCTAssertEqual(try fixture.pageTitle(onePage), "Page-\(one.id.uuidString)")
        XCTAssertEqual(try fixture.pageTitle(twoPage), "Page-\(two.id.uuidString)")
        XCTAssertEqual(try fixture.pageTitle(parentAgain), "Page-\(fixture.parentID.uuidString)")
        XCTAssertEqual(RoutingURLProtocol.actorID(computerID: one.id),
                       "child:\(fixture.runID.uuidString):one")
        XCTAssertEqual(RoutingURLProtocol.actorID(computerID: two.id),
                       "child:\(fixture.runID.uuidString):two")
        XCTAssertNil(RoutingURLProtocol.actorID(computerID: fixture.parentID))
        try fixture.appendHook("SubagentStop", agentID: "one")
        try fixture.appendHook("SubagentStop", agentID: "two")
        let cleaned = await fixture.waitUntil {
            let oneStopped = await fixture.resources.wasStopped(one.id)
            let twoStopped = await fixture.resources.wasStopped(two.id)
            return oneStopped && twoStopped
        }
        XCTAssertTrue(cleaned)
    }

    @MainActor
    func testManualPolicyRejectsAutomaticChildCreation() async throws {
        let fixture = try await RoutingFixture(creation: .manual)
        defer { fixture.shutdown() }
        try fixture.appendHook("SessionStart")
        try fixture.appendHook("SubagentStart", agentID: "one")
        do {
            _ = try await fixture.call("computer_acquire", agentID: "one", arguments: ["mode": "headless"])
            XCTFail("Manual policy must not create a child computer")
        } catch ComputerMCPAccessError.automaticCreationRequired {}
        let created = await fixture.resources.createdCount()
        XCTAssertEqual(created, 0)
        let parentPage = try await fixture.call("computer_page", agentID: nil)
        XCTAssertEqual(try fixture.pageTitle(parentPage), "Page-\(fixture.parentID.uuidString)")
    }

    @MainActor
    func testChildStopWaitsForHumanAndDoesNotStopSibling() async throws {
        let fixture = try await RoutingFixture(creation: .automatic)
        defer { fixture.shutdown() }
        try fixture.appendHook("SessionStart")
        try fixture.appendHook("SubagentStart", agentID: "one")
        try fixture.appendHook("SubagentStart", agentID: "two")
        _ = try await fixture.call("computer_acquire", agentID: "one", arguments: ["mode": "headless"])
        _ = try await fixture.call("computer_acquire", agentID: "two", arguments: ["mode": "headless"])
        let one = try await fixture.childComputer("one")
        let two = try await fixture.childComputer("two")
        let endpoint = try await fixture.resources.endpoint(one.id)
        let bridge = await DesktopBrokerService.bridge(endpoint: endpoint, broker: fixture.broker,
                                                       session: fixture.session)
        let human = try await bridge.assumeHuman()
        try fixture.appendHook("SubagentStop", agentID: "one")
        let retired = await fixture.waitUntil { fixture.access.cleanupFailures[one.id] != nil }
        XCTAssertTrue(retired)
        let stoppedBefore = await fixture.resources.wasStopped(one.id)
        XCTAssertFalse(stoppedBefore)
        let siblingPage = try await fixture.call("computer_page", agentID: "two")
        XCTAssertEqual(try fixture.pageTitle(siblingPage), "Page-\(two.id.uuidString)")
        try await bridge.releaseHuman(human)
        fixture.access.humanReleased(computerID: one.id)
        let stoppedOne = await fixture.waitUntil { await fixture.resources.wasStopped(one.id) }
        XCTAssertTrue(stoppedOne)
        let stoppedSibling = await fixture.resources.wasStopped(two.id)
        XCTAssertFalse(stoppedSibling)
        try fixture.appendHook("SubagentStop", agentID: "two")
        let stoppedTwo = await fixture.waitUntil { await fixture.resources.wasStopped(two.id) }
        XCTAssertTrue(stoppedTwo)
        let parentPage = try await fixture.call("computer_page", agentID: nil)
        XCTAssertEqual(try fixture.pageTitle(parentPage), "Page-\(fixture.parentID.uuidString)")
    }

    @MainActor
    func testChildHelpTargetsItsOwnBoxAndOnlyThatChildPauses() async throws {
        let fixture = try await RoutingFixture(creation: .automatic)
        defer { fixture.shutdown() }
        try fixture.appendHook("SessionStart")
        try fixture.appendHook("SubagentStart", agentID: "one")
        try fixture.appendHook("SubagentStart", agentID: "two")
        _ = try await fixture.call("computer_acquire", agentID: "one", arguments: ["mode": "headless"])
        _ = try await fixture.call("computer_acquire", agentID: "two", arguments: ["mode": "headless"])
        let one = try await fixture.childComputer("one")
        let two = try await fixture.childComputer("two")
        _ = try await fixture.call("computer_request_help", agentID: "one",
                                   arguments: ["reason": "private reason marker"])
        let requests = fixture.requestSink.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.target.sessionID, fixture.sessionID)
        XCTAssertEqual(request.target.terminalID, fixture.terminalID)
        XCTAssertEqual(request.target.computerID, one.id)
        XCTAssertEqual(request.target.runID, try fixture.childRunID("one"))
        XCTAssertFalse(request.summary.contains("private reason marker"))
        do {
            _ = try await fixture.call("computer_mode", agentID: "one", arguments: ["mode": "headless"])
            XCTFail("The requesting child must remain paused")
        } catch ComputerControlBridgeError.noTicket {}
        let siblingPage = try await fixture.call("computer_page", agentID: "two")
        XCTAssertEqual(try fixture.pageTitle(siblingPage), "Page-\(two.id.uuidString)")
        let endpoint = try await fixture.resources.endpoint(one.id)
        let bridge = await DesktopBrokerService.bridge(endpoint: endpoint, broker: fixture.broker,
                                                       session: fixture.session)
        let human = try await bridge.assumeHuman()
        try await bridge.releaseHuman(human)
        fixture.access.humanReleased(computerID: one.id)
        XCTAssertEqual(fixture.requestSink.completedIDs(), [request.id])
        _ = try await fixture.call("computer_mode", agentID: "one", arguments: ["mode": "headless"])
        let resumedPage = try await fixture.call("computer_page", agentID: "one")
        XCTAssertEqual(try fixture.pageTitle(resumedPage), "Page-\(one.id.uuidString)")
        try fixture.appendHook("SubagentStop", agentID: "one")
        try fixture.appendHook("SubagentStop", agentID: "two")
        let stopped = await fixture.waitUntil {
            let first = await fixture.resources.wasStopped(one.id)
            let second = await fixture.resources.wasStopped(two.id)
            return first && second
        }
        XCTAssertTrue(stopped)
    }
}

@MainActor private final class RoutingFixture {
    let root: URL
    let manager: TerminalRuntimeManager
    let monitor: NativeAgentMonitor
    let access: AgentComputerAccess
    let resources: RoutingResources
    let broker: ControlBroker
    let session: URLSession
    let requestSink: RoutingRequestSink
    let launch: MaterializedAgentLaunch
    private(set) var invocation: ClaudeHookInboxConfiguration!
    let terminalID: UUID
    let parentID: UUID
    private(set) var runID = UUID()
    let sessionID = UUID()
    private let nativeSession = "routing-fixture-session"

    init(creation: ComputerCreationPermission) async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("routing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("claude-fixture")
        try "#!/bin/sh\nexec sleep 60\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let skillContent = "---\nname: webscraping-expert\ndescription: Test-only scraping\n---\nUse the assigned browser.\n"
        let source = root.appendingPathComponent("dummy-skill/SKILL.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try skillContent.write(to: source, atomically: true, encoding: .utf8)
        let skillHash = SHA256.hash(data: Data(skillContent.utf8)).map { String(format: "%02x", $0) }.joined()
        let skill = SkillEntry(name: "webscraping-expert", summary: "Fixture", sourcePath: source.path,
                               content: skillContent, sha256: skillHash)
        let agent = SavedAgent(name: "Fixture", instructions: "Test route only", provider: .claude,
                               skillIDs: [skill.id])
        let hookScript = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("runtime/hooks/claude_event.py")
        parentID = UUID()
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
            resolver: CLIExecutableResolver(overrides: [.claude: executable.path]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent], skills: [skill]),
            workingDirectory: root.path, computerID: parentID, mcpHelper: URL(fileURLWithPath: "/bin/sh"),
            hookScriptURL: hookScript)
        launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        terminalID = try XCTUnwrap(launch.terminal?.id)
        let registry = try AgentRunRegistry(url: root.appendingPathComponent("runs.json"))
        monitor = NativeAgentMonitor(registry: registry, pollIntervalNanoseconds: 20_000_000)
        manager = TerminalRuntimeManager(nativeAgentMonitor: monitor)
        broker = try ControlBroker(url: root.appendingPathComponent("broker.json"))
        resources = RoutingResources()
        requestSink = RoutingRequestSink()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutingURLProtocol.self]
        session = URLSession(configuration: configuration)
        let port = RoutingURLProtocol.add(computerID: parentID, mode: .headless)
        let parentEndpoint = try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            apiToken: String(repeating: "a", count: 40), computerID: parentID, generation: 0)
        let context = ComputerPolicyContext(terminalID: terminalID, sessionID: sessionID, agentID: agent.id)
        access = AgentComputerAccess(resources: resources.adapters, runtime: manager, broker: broker,
            runtimeSession: session, policyProvider: { context in
                try ComputerPolicy(creation: creation).effective(for: context)
            }, notifyUser: { [requestSink] request in requestSink.record(request) },
            completeRequest: { [requestSink] id in requestSink.complete(id) })
        try await access.register(launch: launch, sessionID: sessionID,
                                  policyContext: context, endpoint: parentEndpoint)
        try manager.start(launch)
        try access.activate(terminalID: terminalID)
        invocation = try XCTUnwrap(manager.hookInvocation(for: terminalID, planID: launch.planID))
        runID = invocation.runID
    }

    func shutdown() {
        access.stop(terminalID: terminalID)
        manager.shutdown()
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: root)
    }

    func appendHook(_ event: String, agentID: String = "") throws {
        let key = try XCTUnwrap(Self.hexData(try XCTUnwrap(invocation.environment["AGENT_BOX_HOOK_TOKEN"])))
        let fields = [runID.uuidString, nativeSession, event, agentID, agentID.isEmpty ? "" : "Explore"]
        let signature = Self.hex(Data(HMAC<SHA256>.authenticationCode(
            for: Data((fields.joined(separator: "\n") + "\n").utf8), using: SymmetricKey(data: key))))
        let envelope = ["run_id": fields[0], "session_id": fields[1], "hook_event_name": event,
                        "agent_id": fields[3], "agent_type": fields[4], "signature": signature]
        var line = try JSONSerialization.data(withJSONObject: envelope)
        line.append(10)
        let file = try FileHandle(forWritingTo: invocation.inboxURL)
        try file.seekToEnd()
        try file.write(contentsOf: line)
        try file.close()
    }

    func call(_ name: String, agentID: String?, arguments: [String: Any] = [:]) async throws -> ComputerMCPResult {
        let key = try XCTUnwrap(Self.hexData(try XCTUnwrap(invocation.environment["AGENT_BOX_HOOK_TOKEN"])))
        let payload: [String: Any] = ["v": 1, "run_id": runID.uuidString,
            "session_id": nativeSession, "agent_id": agentID ?? "", "tool_use_id": UUID().uuidString,
            "tool_name": "mcp__agentbox__\(name)", "issued_at": Int(Date().timeIntervalSince1970),
            "nonce": Self.hex(Data((0..<16).map { _ in UInt8.random(in: 0...255) })),
            "arguments": arguments]
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let signature = Self.hex(Data(HMAC<SHA256>.authenticationCode(
            for: payloadData, using: SymmetricKey(data: key))))
        var routed = arguments
        routed["route_token"] = payloadData.base64EncodedString() + "." + signature
        return try await access.call(terminalID: terminalID, planID: launch.planID, name: name,
                                     data: JSONSerialization.data(withJSONObject: routed))
    }

    func pageTitle(_ result: ComputerMCPResult) throws -> String {
        guard case .text(let text) = result else { throw RoutingFixtureError.expectedText }
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        return try XCTUnwrap(value["title"] as? String)
    }
    func childComputer(_ nativeID: String) async throws -> BrowserManagedComputer {
        let runID = try childRunID(nativeID)
        let owner = BrowserComputerOwner.nativeChild(parentTerminalID: terminalID, agentRunID: runID)
        let found = await resources.lookup(owner)
        return try XCTUnwrap(found)
    }
    func childRunID(_ nativeID: String) throws -> UUID {
        try XCTUnwrap(monitor.runs.first { $0.nativeAgentID == nativeID && $0.parentRunID == runID }?.id)
    }
    func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        for _ in 0..<150 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return await condition()
    }
    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private static func hexData(_ text: String) -> Data? {
        guard text.count.isMultiple(of: 2) else { return nil }
        let bytes = stride(from: 0, to: text.count, by: 2).compactMap { offset -> UInt8? in
            let start = text.index(text.startIndex, offsetBy: offset)
            return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)
        }
        return bytes.count == text.count / 2 ? Data(bytes) : nil
    }
}

private enum RoutingFixtureError: Error { case expectedText }

private final class RoutingRequestSink {
    private let lock = NSLock()
    private var recorded: [HumanRequest] = []
    private var completed: [UUID] = []
    func record(_ request: HumanRequest) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
    }
    func complete(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        completed.append(id)
    }
    func requests() -> [HumanRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }
    func completedIDs() -> [UUID] {
        lock.lock(); defer { lock.unlock() }
        return completed
    }
}

private actor RoutingResources {
    private var byOwner: [BrowserComputerOwner: BrowserManagedComputer] = [:]
    private var ports: [UUID: Int] = [:]
    private var stopped: Set<UUID> = []
    nonisolated var adapters: AgentComputerResources {
        AgentComputerResources(lookup: { owner in await self.lookup(owner) },
            acquire: { owner, _ in try await self.acquire(owner) },
            endpoint: { id in try await self.endpoint(id) },
            stop: { id in await self.stop(id) })
    }
    func lookup(_ owner: BrowserComputerOwner) -> BrowserManagedComputer? { byOwner[owner] }
    func createdCount() -> Int { byOwner.count }
    func wasStopped(_ id: UUID) -> Bool { stopped.contains(id) }
    func acquire(_ owner: BrowserComputerOwner) throws -> BrowserManagedComputer {
        if let existing = byOwner[owner], existing.running { return existing }
        let id = byOwner[owner]?.id ?? UUID()
        let port = RoutingURLProtocol.add(computerID: id, mode: .http)
        let computer = BrowserManagedComputer(id: id, terminalID: owner.terminalID,
            containerID: "fixture-\(id.uuidString)", name: "fixture-\(id.uuidString)",
            volumeName: "fixture-\(id.uuidString)", running: true, agentRunID: owner.agentRunID)
        byOwner[owner] = computer; ports[id] = port
        return computer
    }
    func endpoint(_ id: UUID) throws -> BrowserRuntimeEndpoint {
        guard let port = ports[id] else { throw BrowserComputerError.notReady }
        return try BrowserRuntimeEndpoint(baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            apiToken: String(repeating: "a", count: 40), computerID: id,
            generation: RoutingURLProtocol.generation(computerID: id))
    }
    func stop(_ id: UUID) {
        stopped.insert(id)
        if let (owner, old) = byOwner.first(where: { $0.value.id == id }) {
            byOwner[owner] = BrowserManagedComputer(id: old.id, terminalID: old.terminalID,
                containerID: old.containerID, name: old.name, volumeName: old.volumeName,
                running: false, agentRunID: old.agentRunID)
        }
    }
}

private final class RoutingURLProtocol: URLProtocol {
    private struct Lease {
        let actorID: String
        let epoch: UInt64
        let paths: [String]
    }
    private struct Box {
        let id: UUID
        var generation: UInt64 = 0
        var mode: BrowserRuntimeMode
        var lease: Lease?
    }
    private static let lock = NSLock()
    private static var boxes: [Int: Box] = [:]
    private static var nextPort = 39_000
    static func add(computerID: UUID, mode: BrowserRuntimeMode) -> Int {
        lock.lock(); defer { lock.unlock() }
        nextPort += 1
        boxes[nextPort] = Box(id: computerID, mode: mode)
        return nextPort
    }
    static func actorID(computerID: UUID) -> String? {
        lock.lock(); defer { lock.unlock() }
        return boxes.values.first(where: { $0.id == computerID })?.lease?.actorID
    }
    static func generation(computerID: UUID) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return boxes.values.first(where: { $0.id == computerID })?.generation ?? 0
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, data) = Self.handle(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func handle(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        guard let port = request.url?.port, var box = boxes[port],
              request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 40) else {
            return (401, Data())
        }
        let body = (try? JSONSerialization.jsonObject(with: requestBody(request))) as? [String: Any] ?? [:]
        let result: [String: Any]
        switch request.url?.path {
        case "/v1/health": result = health(box)
        case "/v1/control/grant":
            guard box.lease == nil, let actor = body["actor_id"] as? String,
                  let epoch = (body["epoch"] as? NSNumber)?.uint64Value,
                  let paths = body["paths"] as? [String] else { return (409, Data()) }
            box.lease = Lease(actorID: actor, epoch: epoch, paths: paths)
            result = ["actor_id": actor, "epoch": epoch, "paths": paths, "control_token": "fixture-control-token"]
        case "/v1/control/revoke":
            guard let actor = body["actor_id"] as? String,
                  let epoch = (body["epoch"] as? NSNumber)?.uint64Value,
                  box.lease?.actorID == actor, box.lease?.epoch == epoch else { return (409, Data()) }
            box.lease = nil
            result = ["revoked_actor_id": actor, "revoked_epoch": epoch, "acknowledged": true]
        case "/v1/mode":
            guard authorized(request, box), let mode = body["mode"] as? String,
                  let selected = BrowserRuntimeMode(rawValue: mode) else { return (403, Data()) }
            box.mode = selected; box.generation += 1
            result = health(box)
        case "/v1/page":
            guard box.mode != .http else { return (409, Data()) }
            result = ["computer_id": box.id.uuidString, "generation": box.generation,
                      "url": "https://fixture.invalid/", "title": "Page-\(box.id.uuidString)",
                      "text": "Visible fixture", "links": [], "truncated": false]
        default: return (404, Data())
        }
        boxes[port] = box
        return (200, (try? JSONSerialization.data(withJSONObject: result)) ?? Data())
    }
    private static func authorized(_ request: URLRequest, _ box: Box) -> Bool {
        request.value(forHTTPHeaderField: "X-AgentBox-Actor-ID") == box.lease?.actorID &&
        request.value(forHTTPHeaderField: "X-AgentBox-Lease-Epoch") == box.lease.map { String($0.epoch) } &&
        request.value(forHTTPHeaderField: "X-AgentBox-Control-Token") == "fixture-control-token"
    }
    private static func health(_ box: Box) -> [String: Any] {
        let active: Any = box.lease.map { ["actor_id": $0.actorID, "epoch": $0.epoch,
                                          "paths": $0.paths] as [String: Any] } ?? NSNull()
        return ["computer_id": box.id.uuidString, "generation": box.generation,
                "mode": box.mode.rawValue, "browser_ready": box.mode != .http,
                "display_ready": box.mode == .desktop,
                "frame_source": box.mode == .http ? "none" : "browser", "active_lease": active]
    }
    private static func requestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

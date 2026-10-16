import Foundation
import XCTest
@testable import AgentBoxCore

final class ComputerControlBridgeTests: XCTestCase {
    func testIdleMaintenanceRejectsLiveControllerAndBlocksConcurrentTakeover() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let runtime = FakeControlRuntime(id: id, generation: 0)
        let bridge = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: runtime, id: id, generation: 0))
        let human = try await bridge.assumeHuman()
        let rejected = MaintenanceGate()
        do {
            try await bridge.performIdleMaintenance { await rejected.markCalled() }
            XCTFail("Maintenance must not stop a box held by a human")
        } catch ControlBrokerError.activeRuntimeLease {}
        let rejectedCount = await rejected.count
        XCTAssertEqual(rejectedCount, 0)
        try await bridge.releaseHuman(human)

        let gate = MaintenanceGate()
        let maintenance = Task { try await bridge.performIdleMaintenance { await gate.wait() } }
        await gate.waitUntilStarted()
        do {
            _ = try await bridge.assumeHuman()
            XCTFail("A human cannot acquire during the stop operation")
        } catch ControlBrokerError.transitionInProgress {}
        let otherBridge = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: runtime, id: id, generation: 0))
        do {
            _ = try await otherBridge.assumeHuman()
            XCTFail("A second bridge cannot reconcile during the stop operation")
        } catch ControlBrokerError.transitionInProgress {}
        let noGrant = await broker.currentGrant(computerID: id)
        XCTAssertNil(noGrant)
        await gate.release()
        try await maintenance.value
        let after = await bridge.ticket()
        XCTAssertNil(after)
        let humanAfterMaintenance = try await bridge.assumeHuman()
        try await bridge.releaseHuman(humanAfterMaintenance)
    }

    func testIndependentChildrenKeepSeparateBoxesAndTickets() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let firstID = UUID(), secondID = UUID(), parent = UUID()
        let firstRuntime = FakeControlRuntime(id: firstID, generation: 0)
        let secondRuntime = FakeControlRuntime(id: secondID, generation: 0)
        let first = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: firstRuntime, id: firstID, generation: 0))
        let second = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: secondRuntime, id: secondID, generation: 0))
        do {
            _ = try await first.assumeChild(parentRunID: parent, nativeChildID: "one",
                paths: [.mode], allowedParentPaths: [.navigate, .input])
            XCTFail("Parent policy limits child paths")
        } catch ControlBrokerError.invalidActor {}
        let one = try await first.assumeChild(parentRunID: parent, nativeChildID: "one",
            paths: [.navigate], allowedParentPaths: [.navigate, .input])
        let two = try await second.assumeChild(parentRunID: parent, nativeChildID: "two",
            paths: [.input], allowedParentPaths: [.input])
        XCTAssertEqual(one.grant.actor, .child(parentRunID: parent, nativeID: "one"))
        XCTAssertEqual(two.grant.actor, .child(parentRunID: parent, nativeID: "two"))
        XCTAssertNil(one.grant.delegatedFrom)
        let retry = try await first.assumeChild(parentRunID: parent, nativeChildID: "one",
            paths: [.navigate], allowedParentPaths: [.navigate])
        XCTAssertEqual(retry, one)
        do {
            _ = try await first.assumeChild(parentRunID: parent, nativeChildID: "two",
                paths: [.navigate], allowedParentPaths: [.navigate])
            XCTFail("Another child cannot take an active child box")
        } catch ControlBrokerError.activeRuntimeLease {}
        let lostToken = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: firstRuntime, id: firstID, generation: 0))
        do {
            _ = try await lostToken.assumeChild(parentRunID: parent, nativeChildID: "one",
                paths: [.navigate], allowedParentPaths: [.navigate])
            XCTFail("A new bridge cannot recover an unknown runtime token")
        } catch ControlBrokerError.activeRuntimeLease {}
        let firstLogBeforeHuman = await firstRuntime.log
        XCTAssertFalse(firstLogBeforeHuman.contains(where: { $0.hasPrefix("revoke:") }))

        let human = try await first.assumeHuman()
        XCTAssertEqual(human.grant.actor, .human)
        do { try await first.releaseController(one); XCTFail("Stale child ticket cannot release human") }
        catch ComputerControlBridgeError.noTicket {}
        do { try await first.releaseController(human); XCTFail("Controller release cannot release human") }
        catch ComputerControlBridgeError.wrongGrant {}
        do {
            _ = try await first.assumeChild(parentRunID: parent, nativeChildID: "one",
                paths: [.navigate], allowedParentPaths: [.navigate])
            XCTFail("Child cannot retake live human control")
        } catch ControlBrokerError.activeRuntimeLease {}
        let secondStillHeld = await second.ticket()
        let secondLease = await secondRuntime.lease
        XCTAssertEqual(secondStillHeld, two)
        XCTAssertEqual(secondLease?.actorID, two.grant.actorID)

        try await first.releaseHuman(human)
        let renewed = try await first.assumeChild(parentRunID: parent, nativeChildID: "one",
            paths: [.navigate], allowedParentPaths: [.navigate])
        XCTAssertNotEqual(renewed.id, one.id)
        do { try await first.releaseController(one); XCTFail("Old child ticket cannot release new lease") }
        catch ComputerControlBridgeError.noTicket {}
        try await first.releaseController(renewed)
        try await second.releaseController(two)
        let firstReleased = await firstRuntime.lease
        let secondReleased = await secondRuntime.lease
        XCTAssertNil(firstReleased)
        XCTAssertNil(secondReleased)
    }

    func testAgentCannotStealHumanLeaseAndCanResumeAfterRelease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), run = UUID()
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let shared = FakeControlRuntime(id: id, generation: 0)
        let bridge = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: shared, id: id, generation: 0))

        let agent = try await bridge.assumeAgent(runID: run)
        XCTAssertEqual(agent.grant.actor, .agent(runID: run))
        XCTAssertEqual(agent.grant.paths, [.navigate, .input, .mode, .httpRequest])
        let retry = try await bridge.assumeAgent(runID: run)
        XCTAssertEqual(retry, agent)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let navigated = try await bridge.navigate(to: url, ticket: agent)
        XCTAssertEqual(navigated, url)
        let http = try await bridge.httpRequest(to: url, method: "GET", ticket: agent)
        XCTAssertEqual(http.status, 200)
        XCTAssertEqual(http.body, Data("ok".utf8))
        do { _ = try await bridge.assumeAgent(runID: UUID()); XCTFail("Other run must not steal control") }
        catch ControlBrokerError.activeRuntimeLease {}
        do { try await bridge.releaseHuman(agent); XCTFail("Agent ticket must not release human control") }
        catch ComputerControlBridgeError.wrongGrant {}
        let stillAgent = await bridge.ticket()
        XCTAssertEqual(stillAgent, agent)

        let human = try await bridge.assumeHuman()
        XCTAssertEqual(human.grant.actor, .human)
        let log = await shared.log
        XCTAssertEqual(log.filter { $0.hasPrefix("revoke:") }, ["revoke:\(agent.grant.actorID):\(agent.grant.epoch)"])
        do { try await bridge.input(.key("Return"), ticket: agent); XCTFail("Old ticket must fail") }
        catch ComputerControlBridgeError.noTicket {}
        do { _ = try await bridge.navigate(to: url, ticket: agent); XCTFail("Old ticket must fail") }
        catch ComputerControlBridgeError.noTicket {}
        do { _ = try await bridge.httpRequest(to: url, method: "GET", ticket: agent); XCTFail("Old ticket must fail") }
        catch ComputerControlBridgeError.noTicket {}
        do { _ = try await bridge.changeMode(.desktop, ticket: agent); XCTFail("Old ticket must fail") }
        catch ComputerControlBridgeError.noTicket {}
        do { _ = try await bridge.assumeAgent(runID: run); XCTFail("Retry must not revoke human") }
        catch ControlBrokerError.activeRuntimeLease {}
        let stillHuman = await bridge.ticket()
        XCTAssertEqual(stillHuman, human)
        let afterRetryLog = await shared.log
        XCTAssertFalse(afterRetryLog.contains("revoke:human:\(human.grant.epoch)"))

        try await bridge.releaseHuman(human)
        let resumed = try await bridge.assumeAgent(runID: run)
        XCTAssertGreaterThan(resumed.grant.epoch, human.grant.epoch)
        XCTAssertNotEqual(resumed.id, agent.id)
        try await bridge.releaseAgent(resumed)
        let releasedTicket = await bridge.ticket()
        let releasedLease = await shared.lease
        XCTAssertNil(releasedTicket)
        XCTAssertNil(releasedLease)
    }

    func testAgentRejectsUnknownLiveLeaseAndNavigationWithoutPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), run = UUID()
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let shared = FakeControlRuntime(id: id, generation: 0,
            initialLease: BrowserRuntimeLease(actorID: "human", epoch: 4, paths: [.input]))
        let bridge = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: shared, id: id, generation: 0))
        do { _ = try await bridge.assumeAgent(runID: run); XCTFail("Unknown live lease must remain untouched") }
        catch ControlBrokerError.activeRuntimeLease {}
        let untouchedLease = await shared.lease
        let untouchedLog = await shared.log
        XCTAssertEqual(untouchedLease?.actorID, "human")
        XCTAssertFalse(untouchedLog.contains(where: { $0.hasPrefix("revoke:") }))

        let cleanID = UUID()
        let cleanBroker = try ControlBroker(url: root.appendingPathComponent("clean-control.json"))
        let cleanRuntime = FakeControlRuntime(id: cleanID, generation: 0)
        let cleanBridge = ComputerControlBridge(broker: cleanBroker,
            transport: FakeControlTransport(shared: cleanRuntime, id: cleanID, generation: 0))
        let inputOnly = try await cleanBridge.assumeAgent(runID: run, paths: [.input])
        do { _ = try await cleanBridge.navigate(to: URL(string: "https://example.com")!, ticket: inputOnly)
            XCTFail("Missing navigate path must deny write") }
        catch ComputerControlBridgeError.writeDenied {}
        do { _ = try await cleanBridge.httpRequest(to: URL(string: "https://example.com")!, method: "HEAD", ticket: inputOnly)
            XCTFail("Missing http_request path must deny write") }
        catch ComputerControlBridgeError.writeDenied {}
        let deniedLog = await cleanRuntime.log
        XCTAssertFalse(deniedLog.contains("navigate"))
        try await cleanBridge.releaseAgent(inputOnly)
    }

    func testWritesAreDeniedWhileHumanTakeoverAwaitsRevocationAck() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let shared = FakeControlRuntime(id: id, generation: 0)
        let bridge = ComputerControlBridge(broker: broker,
            transport: FakeControlTransport(shared: shared, id: id, generation: 0))
        let agent = try await bridge.assumeAgent(runID: UUID())
        await shared.pauseNextRevoke()
        let takeover = Task { try await bridge.assumeHuman() }
        await shared.waitForRevokeStart()
        do { try await bridge.input(.key("Return"), ticket: agent); XCTFail("Input during takeover must fail") }
        catch ControlBrokerError.transitionInProgress {}
        do { _ = try await bridge.navigate(to: URL(string: "https://example.com")!, ticket: agent)
            XCTFail("Navigate during takeover must fail") }
        catch ControlBrokerError.transitionInProgress {}
        do { _ = try await bridge.httpRequest(to: URL(string: "https://example.com")!, method: "GET", ticket: agent)
            XCTFail("HTTP during takeover must fail") }
        catch ControlBrokerError.transitionInProgress {}
        do { _ = try await bridge.changeMode(.desktop, ticket: agent); XCTFail("Mode during takeover must fail") }
        catch ControlBrokerError.transitionInProgress {}
        await shared.resumeRevocation()
        let human = try await takeover.value
        XCTAssertEqual(human.grant.actor, .human)
    }

    func testInputFailureRevokesRuntimeLeaseBeforeItIsForgotten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let shared = FakeControlRuntime(id: id, generation: 0)
        let bridge = ComputerControlBridge(broker: broker, transport: FakeControlTransport(shared: shared, id: id, generation: 0))
        let ticket = try await bridge.assumeHuman()
        await shared.setFailInput(true)
        do { try await bridge.input(.key("Return"), ticket: ticket); XCTFail("Input must fail") }
        catch BrowserRuntimeError.invalidResponse {}
        let lease = await shared.lease
        let active = await bridge.ticket()
        XCTAssertNil(lease)
        XCTAssertNil(active)
        let log = await shared.log
        XCTAssertEqual(log.last, "revoke:human:\(ticket.grant.epoch)")
    }
    func testTakeoverRevokesBeforeGrantAndOldEpochCannotWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let id = UUID(), run = UUID()
        try await broker.reconcile(computerID: id, activeRuntimeLease: nil)
        guard case .granted(let agent) = try await broker.requestAgent(computerID: id, runID: run) else {
            return XCTFail("Expected agent")
        }
        let shared = FakeControlRuntime(id: id, generation: 7,
                                        initialLease: BrowserRuntimeLease(actorID: agent.actorID,
                                                                          epoch: agent.epoch, paths: Array(agent.paths)))
        let bridge = ComputerControlBridge(broker: broker, transport: FakeControlTransport(shared: shared, id: id, generation: 7))
        let ticket = try await bridge.assumeHuman()
        XCTAssertEqual(ticket.grant.actor, .human)
        XCTAssertGreaterThan(ticket.grant.epoch, agent.epoch)
        let log = await shared.log
        XCTAssertEqual(log, ["health", "revoke:\(agent.actorID):\(agent.epoch)",
                             "grant:human:\(ticket.grant.epoch)"])
        let oldCanWrite = await broker.checkWrite(actor: agent.actor, computer: id, epoch: agent.epoch, path: .input)
        XCTAssertFalse(oldCanWrite)
        try await bridge.input(.key("Return"), ticket: ticket)
        let inputLog = await shared.log
        XCTAssertEqual(inputLog.last, "input")
        try await bridge.releaseHuman(ticket)
        let afterRelease = await bridge.ticket()
        XCTAssertNil(afterRelease)
        let humanCanWrite = await broker.checkWrite(actor: .human, computer: id, epoch: ticket.grant.epoch, path: .input)
        XCTAssertFalse(humanCanWrite)
    }

    func testBadRevokeAckSuspendsWithoutHumanTicket() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let id = UUID(), run = UUID()
        try await broker.reconcile(computerID: id, activeRuntimeLease: nil)
        guard case .granted(let agent) = try await broker.requestAgent(computerID: id, runID: run) else {
            return XCTFail("Expected agent")
        }
        let shared = FakeControlRuntime(id: id, generation: 1,
                                        initialLease: BrowserRuntimeLease(actorID: agent.actorID,
                                                                          epoch: agent.epoch, paths: Array(agent.paths)))
        await shared.setBadAck(true)
        let bridge = ComputerControlBridge(broker: broker, transport: FakeControlTransport(shared: shared, id: id, generation: 1))
        do { _ = try await bridge.assumeHuman(); XCTFail("Bad ACK must fail") }
        catch ComputerControlBridgeError.wrongGrant {}
        let ticket = await bridge.ticket()
        XCTAssertNil(ticket)
        let current = await broker.currentGrant(computerID: id)
        XCTAssertNil(current)
        let log = await shared.log
        XCTAssertFalse(log.contains(where: { $0.hasPrefix("grant:human:") }))
    }

    func testGenerationMismatchAndModeRefresh() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let shared = FakeControlRuntime(id: id, generation: 2)
        let stale = ComputerControlBridge(broker: broker, transport: FakeControlTransport(shared: shared, id: id, generation: 1))
        do { _ = try await stale.assumeHuman(); XCTFail("Stale generation must fail") }
        catch ComputerControlBridgeError.staleGeneration {}
        let current = ComputerControlBridge(broker: broker, transport: FakeControlTransport(shared: shared, id: id, generation: 2))
        let ticket = try await current.assumeHuman()
        let health = try await current.changeMode(.desktop, ticket: ticket)
        XCTAssertEqual(health.generation, 3)
        let newGeneration = await current.currentGeneration()
        XCTAssertEqual(newGeneration, 3)
        let updatedTicket = await current.ticket()
        let renewed = try XCTUnwrap(updatedTicket)
        XCTAssertEqual(renewed.generation, 3)
        do { try await current.input(.key("Return"), ticket: ticket); XCTFail("Old generation ticket must fail") }
        catch ComputerControlBridgeError.noTicket {}
        try await current.input(.key("Return"), ticket: renewed)
    }
}

private actor MaintenanceGate {
    private(set) var count = 0
    private var waitingForStart: CheckedContinuation<Void, Never>?
    private var resume: CheckedContinuation<Void, Never>?

    func markCalled() { count += 1 }

    func wait() async {
        count += 1
        waitingForStart?.resume()
        waitingForStart = nil
        await withCheckedContinuation { resume = $0 }
    }

    func waitUntilStarted() async {
        if count > 0 { return }
        await withCheckedContinuation { waitingForStart = $0 }
    }

    func release() { resume?.resume(); resume = nil }
}

private actor FakeControlRuntime {
    let id: UUID
    var generation: UInt64
    var lease: BrowserRuntimeLease?
    var log: [String] = []
    var badAck = false
    var failInput = false
    var holdNextRevoke = false
    var revokeStarted: CheckedContinuation<Void, Never>?
    var resumeRevoke: CheckedContinuation<Void, Never>?

    init(id: UUID, generation: UInt64, initialLease: BrowserRuntimeLease? = nil) {
        self.id = id; self.generation = generation; self.lease = initialLease
    }

    func setBadAck(_ value: Bool) { badAck = value }
    func setFailInput(_ value: Bool) { failInput = value }
    func pauseNextRevoke() { holdNextRevoke = true }
    func waitForRevokeStart() async {
        if log.contains(where: { $0.hasPrefix("revoke:") }) { return }
        await withCheckedContinuation { revokeStarted = $0 }
    }
    func resumeRevocation() { resumeRevoke?.resume(); resumeRevoke = nil }
    func health() throws -> BrowserRuntimeHealth {
        log.append("health")
        return try decode(#"{"computer_id":"\#(id.uuidString)","generation":\#(generation),"mode":"desktop","browser_ready":true,"display_ready":true,"frame_source":"desktop","active_lease":\#(leaseJSON())}"#)
    }
    func grant(actorID: String, epoch: UInt64, paths: Set<ControlWritePath>) throws -> BrowserRuntimeGrantedLease {
        guard lease == nil else { throw BrowserRuntimeError.rejected(409, "lease exists") }
        log.append("grant:\(actorID):\(epoch)")
        lease = BrowserRuntimeLease(actorID: actorID, epoch: epoch, paths: Array(paths))
        let pathsJSON = paths.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        return try decode(#"{"actor_id":"\#(actorID)","epoch":\#(epoch),"paths":[\#(pathsJSON)],"control_token":"private-token"}"#)
    }
    func revoke(actorID: String, epoch: UInt64) async throws -> BrowserRuntimeRevocationAck {
        log.append("revoke:\(actorID):\(epoch)")
        revokeStarted?.resume(); revokeStarted = nil
        if holdNextRevoke {
            holdNextRevoke = false
            await withCheckedContinuation { resumeRevoke = $0 }
        }
        guard lease?.actorID == actorID, lease?.epoch == epoch else { throw BrowserRuntimeError.rejected(409, "lease mismatch") }
        if badAck { return try decode(#"{"revoked_actor_id":"wrong","revoked_epoch":\#(epoch),"acknowledged":true}"#) }
        lease = nil
        return try decode(#"{"revoked_actor_id":"\#(actorID)","revoked_epoch":\#(epoch),"acknowledged":true}"#)
    }
    func input() throws -> BrowserDesktopInputResult {
        guard lease != nil else { throw BrowserRuntimeError.rejected(409, "no lease") }
        log.append("input")
        if failInput { throw BrowserRuntimeError.invalidResponse }
        return try decode(#"{"accepted":true,"generation":\#(generation)}"#)
    }
    func httpRequest(method: String) throws -> BrowserHTTPResponse {
        guard lease != nil else { throw BrowserRuntimeError.rejected(409, "no lease") }
        log.append("http:\(method)")
        return try decode(#"{"computer_id":"\#(id.uuidString)","generation":\#(generation),"status":200,"content_type":"text/plain","body_base64":"b2s="}"#)
    }
    func navigate(to url: URL) throws -> URL {
        guard lease != nil else { throw BrowserRuntimeError.rejected(409, "no lease") }
        log.append("navigate")
        return url
    }
    func changeMode() throws -> BrowserRuntimeHealth {
        generation += 1
        return try health()
    }
    private func leaseJSON() -> String {
        guard let lease else { return "null" }
        let paths = lease.paths.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        return #"{"actor_id":"\#(lease.actorID)","epoch":\#(lease.epoch),"paths":[\#(paths)]}"#
    }
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}

private struct FakeControlTransport: ComputerControlTransport {
    let shared: FakeControlRuntime
    let computerID: UUID
    let generation: UInt64
    init(shared: FakeControlRuntime, id: UUID, generation: UInt64) {
        self.shared = shared; self.computerID = id; self.generation = generation
    }
    func health() async throws -> BrowserRuntimeHealth { try await shared.health() }
    func grant(actorID: String, epoch: UInt64, paths: Set<ControlWritePath>) async throws -> BrowserRuntimeGrantedLease {
        try await shared.grant(actorID: actorID, epoch: epoch, paths: paths)
    }
    func revoke(actorID: String, epoch: UInt64) async throws -> BrowserRuntimeRevocationAck {
        try await shared.revoke(actorID: actorID, epoch: epoch)
    }
    func input(_ action: BrowserDesktopInput, lease: BrowserRuntimeGrantedLease) async throws -> BrowserDesktopInputResult {
        try await shared.input()
    }
    func navigate(to url: URL, lease: BrowserRuntimeGrantedLease) async throws -> URL {
        try await shared.navigate(to: url)
    }
    func httpRequest(to url: URL, method: String, lease: BrowserRuntimeGrantedLease) async throws -> BrowserHTTPResponse {
        try await shared.httpRequest(method: method)
    }
    func changeMode(_ mode: BrowserRuntimeMode, lease: BrowserRuntimeGrantedLease) async throws -> BrowserRuntimeHealth {
        try await shared.changeMode()
    }
    func refreshed(generation: UInt64) throws -> Self {
        Self(shared: shared, id: computerID, generation: generation)
    }
}

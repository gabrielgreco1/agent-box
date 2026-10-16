import XCTest
@testable import AgentBoxCore

final class ControlBrokerTests: XCTestCase {
    func testHumanTakeoverRequiresExactACKAndRejectsOldEpoch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let broker = try ControlBroker(url: root.appendingPathComponent("control.json"))
        let computer = UUID(), run = UUID()
        try await broker.reconcile(computerID: computer, activeRuntimeLease: nil)
        guard case .granted(let agent) = try await broker.requestAgent(computerID: computer, runID: run) else {
            return XCTFail("Expected agent grant")
        }
        let agentCanWrite = await broker.checkWrite(actor: agent.actor, computer: computer, epoch: agent.epoch, path: .input)
        XCTAssertTrue(agentCanWrite)
        guard case .revoking(let notice) = try await broker.requestHuman(computerID: computer) else {
            return XCTFail("Expected revocation")
        }
        let oldLeaseCanWrite = await broker.checkWrite(actor: agent.actor, computer: computer, epoch: agent.epoch, path: .input)
        XCTAssertFalse(oldLeaseCanWrite)
        let wrong = ControlRevocation(computerID: computer, actorID: notice.actorID, epoch: notice.epoch + 1)
        do {
            _ = try await broker.acknowledgeRevocation(wrong)
            XCTFail("Wrong epoch must not grant control")
        } catch ControlBrokerError.invalidAcknowledgment {}
        guard case .granted(let human) = try await broker.acknowledgeRevocation(notice) else {
            return XCTFail("Expected human grant")
        }
        XCTAssertGreaterThan(human.epoch, agent.epoch)
        let humanCanWrite = await broker.checkWrite(actor: .human, computer: computer, epoch: human.epoch, path: .navigate)
        let staleAgentCanWrite = await broker.checkWrite(actor: agent.actor, computer: computer, epoch: agent.epoch, path: .navigate)
        XCTAssertTrue(humanCanWrite)
        XCTAssertFalse(staleAgentCanWrite)
        let duplicateResult = try await broker.acknowledgeRevocation(notice)
        XCTAssertEqual(duplicateResult, .granted(human))
    }

    func testChildDelegationTimeoutDisconnectAndTwoIndependentBoxes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("control.json")
        let broker = try ControlBroker(url: url)
        let first = UUID(), second = UUID(), run = UUID()
        try await broker.reconcile(computerID: first, activeRuntimeLease: nil)
        try await broker.reconcile(computerID: second, activeRuntimeLease: nil)
        guard case .granted(let parent) = try await broker.requestAgent(computerID: first, runID: run) else {
            return XCTFail("Expected parent")
        }
        guard case .granted(let otherHuman) = try await broker.requestHuman(computerID: second) else {
            return XCTFail("Expected second box human")
        }
        guard case .revoking(let parentNotice) = try await broker.requestChild(computerID: first, parentRunID: run,
                                                                               nativeChildID: "native-1", paths: [.navigate, .input]) else {
            return XCTFail("Expected parent revocation")
        }
        let parentCanWrite = await broker.checkWrite(actor: parent.actor, computer: first, epoch: parent.epoch, path: .input)
        let otherCanWrite = await broker.checkWrite(actor: .human, computer: second, epoch: otherHuman.epoch, path: .input)
        XCTAssertFalse(parentCanWrite)
        XCTAssertTrue(otherCanWrite)
        guard case .granted(let child) = try await broker.acknowledgeRevocation(parentNotice) else {
            return XCTFail("Expected child grant")
        }
        let childCanSwitchMode = await broker.checkWrite(actor: child.actor, computer: first, epoch: child.epoch, path: .mode)
        XCTAssertFalse(childCanSwitchMode)
        guard case .revoking(let childNotice) = try await broker.revokeChild(computerID: first) else {
            return XCTFail("Expected child revocation")
        }
        try await broker.expireRevocation(computerID: first)
        do {
            _ = try await broker.acknowledgeRevocation(childNotice)
            XCTFail("Late ACK must not grant")
        } catch ControlBrokerError.invalidAcknowledgment {}
        let timedOutGrant = await broker.currentGrant(computerID: first)
        let otherStillCanWrite = await broker.checkWrite(actor: .human, computer: second, epoch: otherHuman.epoch, path: .input)
        XCTAssertNil(timedOutGrant)
        XCTAssertTrue(otherStillCanWrite)
        do {
            try await broker.reconcile(computerID: first, activeRuntimeLease: childNotice)
            XCTFail("Live runtime lease needs external revocation")
        } catch ControlBrokerError.activeRuntimeLease {}
        try await broker.reconcile(computerID: first, activeRuntimeLease: nil)
        let restarted = try ControlBroker(url: url)
        let restartedGrant = await restarted.currentGrant(computerID: second)
        XCTAssertNil(restartedGrant)
        do {
            _ = try await restarted.requestHuman(computerID: second)
            XCTFail("Restart requires reconciliation")
        } catch ControlBrokerError.notReconciled {}
    }
}

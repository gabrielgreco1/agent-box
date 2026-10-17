import Foundation
import XCTest
@testable import AgentBoxCore

final class ComputerMCPAccessPolicyTests: XCTestCase {
    func testExistingRunningChildCanConnectUnderManualWithoutCreating() throws {
        let terminalID = UUID(), runID = UUID()
        let owner = BrowserComputerOwner.nativeChild(parentTerminalID: terminalID, agentRunID: runID)
        let computer = box(owner: owner, running: true)
        XCTAssertEqual(try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: computer,
            creation: .manual, callerActive: true, busy: false, capabilitySupported: true), .connectExisting)
    }

    func testStoppedOrMissingChildRequiresAutomaticCreation() throws {
        let owner = BrowserComputerOwner.nativeChild(parentTerminalID: UUID(), agentRunID: UUID())
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner,
            existingComputer: box(owner: owner, running: false), creation: .manual,
            callerActive: true, busy: false, capabilitySupported: true)) {
            XCTAssertEqual($0 as? ComputerMCPAccessError, .automaticCreationRequired)
        }
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner,
            existingComputer: nil, creation: .manual,
            callerActive: true, busy: false, capabilitySupported: true)) {
            XCTAssertEqual($0 as? ComputerMCPAccessError, .automaticCreationRequired)
        }
        XCTAssertEqual(try ComputerMCPAcquirePolicy.decide(owner: owner,
            existingComputer: box(owner: owner, running: false), creation: .automatic,
            callerActive: true, busy: false, capabilitySupported: true), .startExisting)
        XCTAssertEqual(try ComputerMCPAcquirePolicy.decide(owner: owner,
            existingComputer: nil, creation: .automatic,
            callerActive: true, busy: false, capabilitySupported: true), .create)
    }

    func testWrongOwnerInactiveBusyAndUnsupportedCallerFailClosed() throws {
        let owner = BrowserComputerOwner.nativeChild(parentTerminalID: UUID(), agentRunID: UUID())
        let parentBox = box(owner: .terminal(owner.terminalID), running: true)
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: parentBox,
            creation: .automatic, callerActive: true, busy: false, capabilitySupported: true)) {
            XCTAssertEqual($0 as? ComputerMCPAccessError, .unsupportedCapability)
        }
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: nil,
            creation: .automatic, callerActive: false, busy: false, capabilitySupported: true)) {
            XCTAssertEqual($0 as? ComputerMCPAccessError, .callerInactive)
        }
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: nil,
            creation: .automatic, callerActive: true, busy: true, capabilitySupported: true)) {
            XCTAssertEqual($0 as? ComputerMCPAccessError, .busy)
        }
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: nil,
            creation: .automatic, callerActive: true, busy: false, capabilitySupported: false)) {
            XCTAssertEqual($0 as? ComputerMCPAccessError, .unsupportedCapability)
        }
        XCTAssertThrowsError(try ComputerMCPAcquirePolicy.decide(owner: owner, existingComputer: nil,
            creation: .disabled, callerActive: true, busy: false, capabilitySupported: true)) {
            guard case ComputerPolicyError.creationDisabled = $0 else {
                return XCTFail("Expected creationDisabled")
            }
        }
    }

    private func box(owner: BrowserComputerOwner, running: Bool) -> BrowserManagedComputer {
        BrowserManagedComputer(id: UUID(), terminalID: owner.terminalID,
            containerID: String(repeating: "a", count: 64), name: "agentbox-browser-test",
            volumeName: "agentbox-browser-data-test", running: running,
            agentRunID: owner.agentRunID)
    }
}

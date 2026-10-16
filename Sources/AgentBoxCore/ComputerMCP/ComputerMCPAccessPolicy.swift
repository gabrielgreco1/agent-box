import Foundation

/// Public route failures contain no computer ID, native agent ID, token or URL.
public enum ComputerMCPAccessError: Error, Equatable, Sendable {
    case childComputerMissing
    case automaticCreationRequired
    case callerInactive
    case busy
    case unsupportedCapability
}

public enum ComputerMCPAcquireAction: Equatable, Sendable {
    case connectExisting
    case startExisting
    case create
}

/// Pure permission gate for the explicit computer_acquire route. The host must
/// separately prove caller identity and recheck Docker state before mutation.
public enum ComputerMCPAcquirePolicy {
    public static func decide(owner: BrowserComputerOwner,
                              existingComputer: BrowserManagedComputer?,
                              creation: ComputerCreationPermission,
                              callerActive: Bool,
                              busy: Bool,
                              capabilitySupported: Bool) throws -> ComputerMCPAcquireAction {
        guard capabilitySupported else { throw ComputerMCPAccessError.unsupportedCapability }
        guard callerActive else { throw ComputerMCPAccessError.callerInactive }
        guard !busy else { throw ComputerMCPAccessError.busy }
        guard creation != .disabled else { throw ComputerPolicyError.creationDisabled }
        if let existingComputer {
            guard existingComputer.owner == owner else { throw ComputerMCPAccessError.unsupportedCapability }
            if existingComputer.running { return .connectExisting }
            guard creation == .automatic else { throw ComputerMCPAccessError.automaticCreationRequired }
            return .startExisting
        }
        guard creation == .automatic else { throw ComputerMCPAccessError.automaticCreationRequired }
        return .create
    }
}

import Foundation

/// Labels de todos os recursos Docker do app (07 CS-115, 08 §0).
public enum AgentBoxLabel {
    public static let owner = "agentbox.owner"
    public static let computer = "agentbox.computer"
    public static let computerName = "agentbox.computer_name"
    public static let session = "agentbox.session"
    public static let run = "agentbox.run"
    public static let batch = "agentbox.batch"
    public static let role = "agentbox.role"
    public static let ephemeral = "agentbox.ephemeral"
    public static let imageDigest = "agentbox.image_digest"
    /// Marca recursos criados por testes. Testes só tocam em recursos com `agentbox.test=1`.
    public static let test = "agentbox.test"
    public static let contextHash = "agentbox.context_hash"
}

public enum ComputerRole: String, Sendable, CaseIterable {
    case runtime, work, egress, agent
}

/// Montagem dos labels e dos nomes determinísticos de um computador (07 CS-115/CS-116).
public struct ComputerLabels: Sendable, Equatable {
    public var owner: String
    public var computerID: String
    public var computerName: String
    public var session: String?
    public var run: String?
    public var batch: String?
    public var ephemeral: Bool
    public var imageDigest: String?
    public var isTest: Bool

    public init(owner: String, computerID: String, computerName: String, session: String? = nil, run: String? = nil,
                batch: String? = nil, ephemeral: Bool = true, imageDigest: String? = nil, isTest: Bool = false) {
        self.owner = owner
        self.computerID = computerID
        self.computerName = computerName
        self.session = session
        self.run = run
        self.batch = batch
        self.ephemeral = ephemeral
        self.imageDigest = imageDigest
        self.isTest = isTest
    }

    public func labels(role: ComputerRole?) -> [String: String] {
        var result: [String: String] = [
            AgentBoxLabel.owner: owner, AgentBoxLabel.computer: computerID, AgentBoxLabel.computerName: computerName,
            AgentBoxLabel.ephemeral: ephemeral ? "true" : "false",
        ]
        if let role { result[AgentBoxLabel.role] = role.rawValue }
        if let session { result[AgentBoxLabel.session] = session }
        if let run { result[AgentBoxLabel.run] = run }
        if let batch { result[AgentBoxLabel.batch] = batch }
        if let imageDigest { result[AgentBoxLabel.imageDigest] = imageDigest }
        if isTest { result[AgentBoxLabel.test] = "1" }
        return result
    }

    /// `ab-<computerId8>-<role>`.
    public var shortID: String { String(computerID.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased() }
    public func containerName(_ role: ComputerRole) -> String { "ab-\(shortID)-\(role.rawValue)" }
    public var networkName: String { "agentbox-net-\(computerID)" }
}

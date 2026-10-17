import CryptoKit
import Foundation

public enum ComputerCallProvenanceError: Error, Equatable {
    case invalid
}

public struct VerifiedComputerCall: Sendable, Equatable {
    public let runID: UUID
    public let sessionID: String
    /// Nil is the native parent; a child ID must also be checked against the live run registry.
    public let agentID: String?
    public let toolUseID: String
    public let argumentsData: Data
}

/// Verifies the per-tool routing assertion produced by Claude's reviewed PreToolUse hook.
/// Keep one actor for the whole invocation so replay protection survives MCP reconnects.
public actor ComputerCallProvenanceVerifier {
    private let runID: UUID
    private let key: SymmetricKey
    private let now: @Sendable () -> Date
    private var seenNonces: [String: Int] = [:]
    private var seenToolUses: [String: Int] = [:]
    private static let lifetimeSeconds = 15 * 60
    private static let futureSeconds = 30
    private static let replayLimit = 4096

    public init(runID: UUID, tokenHex: String) throws {
        try self.init(runID: runID, tokenHex: tokenHex, now: { Date() })
    }

    init(runID: UUID, tokenHex: String, now: @escaping @Sendable () -> Date) throws {
        guard let bytes = Self.hexBytes(tokenHex), bytes.count == 32 else {
            throw ComputerCallProvenanceError.invalid
        }
        self.runID = runID
        self.key = SymmetricKey(data: bytes)
        self.now = now
    }

    public func verify(toolName: String, argumentsData: Data,
                       expectedSessionID: String? = nil) throws -> VerifiedComputerCall {
        guard toolName.hasPrefix("mcp__agentbox__computer_"),
              argumentsData.count <= 65_536,
              let outer = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any],
              let token = outer["route_token"] as? String,
              token.utf8.count <= 44_000 else { throw ComputerCallProvenanceError.invalid }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payload = Data(base64Encoded: String(parts[0])), payload.count <= 32_768,
              payload.base64EncodedString() == String(parts[0]),
              let provided = Self.hexBytes(String(parts[1])), provided.count == 32,
              let envelope = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              Set(envelope.keys) == ["v", "run_id", "session_id", "agent_id", "tool_use_id",
                                     "tool_name", "issued_at", "nonce", "arguments"],
              let version = envelope["v"] as? Int, version == 1,
              let signedRunID = envelope["run_id"] as? String, signedRunID == runID.uuidString,
              let sessionID = envelope["session_id"] as? String, !sessionID.isEmpty,
              sessionID.utf8.count <= 256,
              expectedSessionID == nil || expectedSessionID == sessionID,
              let agentID = envelope["agent_id"] as? String, agentID.utf8.count <= 256,
              let toolUseID = envelope["tool_use_id"] as? String, !toolUseID.isEmpty,
              toolUseID.utf8.count <= 256,
              let signedToolName = envelope["tool_name"] as? String,
              signedToolName == toolName,
              let timestamp = envelope["issued_at"] as? Int,
              let nonce = envelope["nonce"] as? String,
              nonce.count == 32, nonce.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
              let signedArguments = envelope["arguments"] as? [String: Any] else {
            throw ComputerCallProvenanceError.invalid
        }
        let current = Int(now().timeIntervalSince1970)
        guard timestamp >= current - Self.lifetimeSeconds,
              timestamp <= current + Self.futureSeconds else { throw ComputerCallProvenanceError.invalid }
        let digest = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        guard Self.constantTimeEqual(digest, provided) else { throw ComputerCallProvenanceError.invalid }
        var original = outer
        original.removeValue(forKey: "route_token")
        guard let actualData = try? JSONSerialization.data(withJSONObject: original, options: [.sortedKeys]),
              let signedData = try? JSONSerialization.data(withJSONObject: signedArguments, options: [.sortedKeys]),
              actualData.count <= 24_576, actualData == signedData else {
            throw ComputerCallProvenanceError.invalid
        }
        let earliest = current - Self.lifetimeSeconds
        seenNonces = seenNonces.filter { $0.value >= earliest }
        seenToolUses = seenToolUses.filter { $0.value >= earliest }
        guard seenNonces[nonce] == nil, seenToolUses[toolUseID] == nil,
              seenNonces.count < Self.replayLimit,
              seenToolUses.count < Self.replayLimit else { throw ComputerCallProvenanceError.invalid }
        seenNonces[nonce] = timestamp
        seenToolUses[toolUseID] = timestamp
        return VerifiedComputerCall(runID: runID, sessionID: sessionID,
                                    agentID: agentID.isEmpty ? nil : agentID,
                                    toolUseID: toolUseID, argumentsData: signedData)
    }

    private static func hexBytes(_ text: String) -> Data? {
        guard text.count.isMultiple(of: 2), text.utf8.allSatisfy({
            (48...57).contains($0) || (97...102).contains($0)
        }) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(text.count / 2)
        let scalars = Array(text.utf8)
        for index in stride(from: 0, to: scalars.count, by: 2) {
            guard let value = UInt8(String(decoding: scalars[index...index + 1], as: UTF8.self), radix: 16) else {
                return nil
            }
            bytes.append(value)
        }
        return Data(bytes)
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        var difference = lhs.count ^ rhs.count
        for index in 0..<32 {
            difference |= Int(index < lhs.count ? lhs[index] : 0) ^ Int(index < rhs.count ? rhs[index] : 0)
        }
        return difference == 0
    }
}

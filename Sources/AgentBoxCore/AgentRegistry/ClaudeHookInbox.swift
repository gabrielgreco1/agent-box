import Foundation
import CryptoKit

/// Per-launch opt-in transport. The caller passes `environment` to the Claude process and
/// appends `--settings settingsURL.path` to that process's arguments. No user settings are edited.
public struct ClaudeHookInboxConfiguration: Equatable, Sendable {
    public let runID: UUID
    public let settingsURL: URL
    public let inboxURL: URL
    public let environment: [String: String]

    public static func create(runID: UUID, directory: URL, hookScriptURL: URL) throws -> Self {
        let files = FileManager.default
        let root = directory.standardizedFileURL
        try files.createDirectory(at: root, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        guard files.isExecutableFile(atPath: hookScriptURL.path) else { throw ClaudeHookInboxError.missingHookScript }
        let token = (0..<32).map { _ in UInt8.random(in: 0...255) }.map { String(format: "%02x", $0) }.joined()
        let inbox = root.appendingPathComponent("events.jsonl")
        guard !files.fileExists(atPath: inbox.path) else { throw ClaudeHookInboxError.existingInbox }
        guard files.createFile(atPath: inbox.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else {
            throw ClaudeHookInboxError.invalidInbox
        }
        let command = shellQuote(hookScriptURL.standardizedFileURL.path)
        let entry: [String: Any] = ["type": "command", "command": command, "timeout": 5]
        let hooks = ["SessionStart", "SubagentStart", "SubagentStop"].reduce(into: [String: Any]()) {
            $0[$1] = [["hooks": [entry]]]
        }
        let settings = root.appendingPathComponent("hooks.settings.json")
        try JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.sortedKeys])
            .write(to: settings, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        return Self(runID: runID, settingsURL: settings, inboxURL: inbox,
                    environment: ["AGENT_BOX_HOOK_RUN_ID": runID.uuidString,
                                  "AGENT_BOX_HOOK_TOKEN": token,
                                  "AGENT_BOX_HOOK_INBOX": inbox.path])
    }

    private static func shellQuote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

public enum ClaudeHookInboxError: Error, Equatable {
    case missingHookScript, existingInbox, invalidInbox, oversizedInbox, invalidEnvelope, badSignature, wrongRun
}

/// Reads complete lines only. Cursor advances after successful verification and registry admission.
/// Keep this actor alive for one launched run; recreate with offset 0 after restart (registry is idempotent).
public actor ClaudeHookInbox {
    public let configuration: ClaudeHookInboxConfiguration
    private let registry: AgentRunRegistry
    private var offset = 0
    private let maximumBytes = 1_048_576

    public init(configuration: ClaudeHookInboxConfiguration, registry: AgentRunRegistry) {
        self.configuration = configuration
        self.registry = registry
    }

    @discardableResult
    public func drain() async throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: configuration.inboxURL.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular,
              let mode = attributes[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else {
            throw ClaudeHookInboxError.invalidInbox
        }
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maximumBytes else {
            throw ClaudeHookInboxError.oversizedInbox
        }
        let data = try Data(contentsOf: configuration.inboxURL)
        guard data.count <= maximumBytes, offset <= data.count else { throw ClaudeHookInboxError.oversizedInbox }
        var accepted = 0
        while offset < data.count {
            guard let end = data[offset...].firstIndex(of: 0x0A) else { break }
            let line = data[offset..<end]
            guard line.count <= 4096 else { throw ClaudeHookInboxError.invalidEnvelope }
            let envelope = try JSONDecoder().decode(Envelope.self, from: line)
            guard envelope.runID == configuration.runID.uuidString else { throw ClaudeHookInboxError.wrongRun }
            guard Self.verify(envelope, token: configuration.environment["AGENT_BOX_HOOK_TOKEN"] ?? "") else {
                throw ClaudeHookInboxError.badSignature
            }
            let eventData = try JSONSerialization.data(withJSONObject: [
                "hook_event_name": envelope.hookEventName, "session_id": envelope.sessionID,
                "agent_id": envelope.agentID, "agent_type": envelope.agentType
            ])
            let event = try NativeAgentHookEvent.parse(eventData, source: .claude)
            _ = try await registry.recordHookEvent(event, parentRunID: configuration.runID)
            offset = end + 1
            accepted += 1
        }
        return accepted
    }

    private struct Envelope: Decodable {
        let runID: String
        let sessionID: String
        let hookEventName: String
        let agentID: String
        let agentType: String
        let signature: String
        enum CodingKeys: String, CodingKey {
            case runID = "run_id", sessionID = "session_id", hookEventName = "hook_event_name"
            case agentID = "agent_id", agentType = "agent_type", signature
        }
    }

    private static func verify(_ envelope: Envelope, token: String) -> Bool {
        guard let key = Data(hex: token), key.count == 32, let signature = Data(hex: envelope.signature) else { return false }
        let message = [envelope.runID, envelope.sessionID, envelope.hookEventName,
                       envelope.agentID, envelope.agentType].joined(separator: "\n") + "\n"
        let digest = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
        return Data(digest) == signature
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

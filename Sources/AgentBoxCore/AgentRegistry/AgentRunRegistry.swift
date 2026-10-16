import Foundation

/// Documentation describes possible signals; it does not mean Agent Box receives them yet.
public struct AgentIdentityCapability: Equatable, Sendable {
    public let provider: CLIProvider
    public let observedPTYProcess: Bool
    public let documentedSubagentHooks: Bool
    public let liveSubagentCapture: Bool
    public let independentChildTerminal: Bool

    public static func current(for provider: CLIProvider) -> Self {
        Self(provider: provider, observedPTYProcess: true,
             documentedSubagentHooks: provider == .claude || provider == .codex,
             liveSubagentCapture: false, independentChildTerminal: false)
    }
}

public enum AgentRunKind: String, Codable, Sendable { case terminal, nativeSubagent }
public enum AgentRunStatus: String, Codable, Sendable { case running, finished }
public enum NativeHookSource: String, Codable, Sendable { case claude, codex }
public enum NativeHookKind: String, Codable, Sendable { case sessionStart, subagentStart, subagentStop }

/// An adapter may construct this from a trusted hook stdin payload. PTY text is never an event source.
public struct NativeAgentHookEvent: Equatable, Sendable {
    public let source: NativeHookSource
    public let kind: NativeHookKind
    public let sessionID: String
    public let agentID: String?
    public let agentType: String?

    public static func parse(_ data: Data, source: NativeHookSource) throws -> Self {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.sessionID.isEmpty, let kind = NativeHookKind(hookName: payload.hookEventName) else {
            throw AgentRegistryError.invalidEvent
        }
        if kind != .sessionStart {
            guard let id = payload.agentID, !id.isEmpty,
                  let type = payload.agentType, !type.isEmpty else { throw AgentRegistryError.invalidEvent }
        }
        return Self(source: source, kind: kind, sessionID: payload.sessionID,
                    agentID: payload.agentID, agentType: payload.agentType)
    }

    private struct Payload: Decodable {
        let sessionID: String
        let hookEventName: String
        let agentID: String?
        let agentType: String?
        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id", hookEventName = "hook_event_name"
            case agentID = "agent_id", agentType = "agent_type"
        }
    }
}

private extension NativeHookKind {
    init?(hookName: String) {
        switch hookName {
        case "SessionStart": self = .sessionStart
        case "SubagentStart": self = .subagentStart
        case "SubagentStop": self = .subagentStop
        default: return nil
        }
    }
}

public struct AgentRunRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: AgentRunKind
    public let provider: CLIProvider
    public let terminalID: UUID
    public let parentRunID: UUID?
    public let parentTerminalID: UUID?
    public let processID: Int32?
    public let nativeSessionID: String?
    public let nativeAgentID: String?
    public let nativeAgentType: String?
    public let nativeHookSource: NativeHookSource?
    public let startedAt: Date
    public var endedAt: Date?
    public var status: AgentRunStatus
}

public enum AgentRegistryError: Error, Equatable {
    case invalidEvent
    case invalidProcess
    case runNotFound
    case parentMismatch
    case sessionMismatch
    case duplicateRun
    case unsupportedProvider
    case unsupportedSchema
}

/// Metadata only. The CLI owns its native agents; this registry never launches or controls them.
public actor AgentRunRegistry {
    private struct Store: Codable {
        var schemaVersion = 1
        var runs: [AgentRunRecord] = []
    }

    public let url: URL
    private var store: Store

    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("AgentRuns.json")) throws {
        self.url = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: self.url.path) {
            let loaded = try JSONDecoder().decode(Store.self, from: Data(contentsOf: self.url))
            guard loaded.schemaVersion == 1 else { throw AgentRegistryError.unsupportedSchema }
            self.store = loaded
        } else {
            self.store = Store()
        }
    }

    public func allRuns() -> [AgentRunRecord] { store.runs }

    /// Call only after TerminalRuntimeManager reports `.running(pid:)`.
    @discardableResult
    public func recordTerminalStart(terminalID: UUID, provider: CLIProvider, processID: Int32,
                                    runID: UUID = UUID(),
                                    at date: Date = Date()) throws -> AgentRunRecord {
        guard processID > 0 else { throw AgentRegistryError.invalidProcess }
        guard !store.runs.contains(where: { $0.id == runID }) else { throw AgentRegistryError.duplicateRun }
        guard !store.runs.contains(where: { $0.kind == .terminal && $0.terminalID == terminalID && $0.status == .running }) else {
            throw AgentRegistryError.duplicateRun
        }
        let run = AgentRunRecord(id: runID, kind: .terminal, provider: provider, terminalID: terminalID,
                                 parentRunID: nil, parentTerminalID: nil, processID: processID,
                                 nativeSessionID: nil, nativeAgentID: nil, nativeAgentType: nil,
                                 nativeHookSource: nil, startedAt: date, endedAt: nil, status: .running)
        var next = store; next.runs.append(run)
        try persist(next); store = next
        return run
    }

    public func finishTerminalRun(_ runID: UUID, at date: Date = Date()) throws {
        guard let index = store.runs.firstIndex(where: { $0.id == runID && $0.kind == .terminal }) else {
            throw AgentRegistryError.runNotFound
        }
        var next = store
        next.runs[index].status = .finished; next.runs[index].endedAt = date
        // Parent terminal exit is not proof each native child completed; leave their last observed state.
        try persist(next); store = next
    }

    /// Admits only structured hook events that a future trusted hook transport binds to this run.
    /// SessionStart establishes the session correlation before any child can be recorded.
    @discardableResult
    public func recordHookEvent(_ event: NativeAgentHookEvent, parentRunID: UUID,
                                at date: Date = Date()) throws -> AgentRunRecord? {
        guard let parentIndex = store.runs.firstIndex(where: { $0.id == parentRunID && $0.kind == .terminal && $0.status == .running }) else {
            throw AgentRegistryError.runNotFound
        }
        let parent = store.runs[parentIndex]
        guard (event.source == .claude && parent.provider == .claude) ||
              (event.source == .codex && parent.provider == .codex) else {
            throw AgentRegistryError.unsupportedProvider
        }
        var next = store
        if event.kind == .sessionStart {
            guard parent.nativeSessionID == nil || parent.nativeSessionID == event.sessionID else {
                throw AgentRegistryError.sessionMismatch
            }
            next.runs[parentIndex] = AgentRunRecord(id: parent.id, kind: .terminal, provider: parent.provider,
                                                     terminalID: parent.terminalID, parentRunID: nil,
                                                     parentTerminalID: nil, processID: parent.processID,
                                                     nativeSessionID: event.sessionID, nativeAgentID: nil,
                                                     nativeAgentType: nil, nativeHookSource: event.source,
                                                     startedAt: parent.startedAt, endedAt: nil, status: .running)
            try persist(next); store = next
            return nil
        }
        guard parent.nativeSessionID == event.sessionID, parent.nativeHookSource == event.source,
              let agentID = event.agentID, let agentType = event.agentType else {
            throw AgentRegistryError.sessionMismatch
        }
        if event.kind == .subagentStart {
            // A resume may emit another Start for the same native id. Keep one identity.
            if let index = next.runs.firstIndex(where: { $0.parentRunID == parentRunID && $0.nativeAgentID == agentID }) {
                if next.runs[index].status == .finished {
                    next.runs[index].status = .running
                    next.runs[index].endedAt = nil
                    try persist(next); store = next
                }
                return next.runs[index]
            }
            let child = AgentRunRecord(id: UUID(), kind: .nativeSubagent, provider: parent.provider,
                                       terminalID: parent.terminalID, parentRunID: parent.id,
                                       parentTerminalID: parent.terminalID, processID: nil,
                                       nativeSessionID: event.sessionID, nativeAgentID: agentID,
                                       nativeAgentType: agentType, nativeHookSource: event.source,
                                       startedAt: date, endedAt: nil, status: .running)
            next.runs.append(child)
            try persist(next); store = next
            return child
        }
        guard let childIndex = next.runs.firstIndex(where: { $0.parentRunID == parentRunID &&
            $0.nativeAgentID == agentID && $0.nativeSessionID == event.sessionID &&
            $0.nativeAgentType == agentType }) else { return nil }
        next.runs[childIndex].status = .finished; next.runs[childIndex].endedAt = date
        let child = next.runs[childIndex]
        try persist(next); store = next
        return child
    }

    private func persist(_ next: Store) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(next)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

import Foundation

public enum CLIProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, opencode, shell
    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .claude: return "Claude Code"; case .codex: return "Codex"; case .opencode: return "OpenCode"; case .shell: return "Shell" }
    }
    public var executableName: String {
        switch self { case .claude: return "claude"; case .codex: return "codex"; case .opencode: return "opencode"; case .shell: return "zsh" }
    }
}

public struct TerminalRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var provider: CLIProvider
    public var cwd: String
    public var arguments: [String]
    public var createdAt: Date
    public var agentDefinitionID: UUID?
    public var nativeConversation: CLIConversationIdentity?
    public init(id: UUID = UUID(), title: String, provider: CLIProvider, cwd: String, arguments: [String] = [], createdAt: Date = Date(), agentDefinitionID: UUID? = nil, nativeConversation: CLIConversationIdentity? = nil) {
        self.id = id; self.title = title; self.provider = provider; self.cwd = cwd; self.arguments = arguments; self.createdAt = createdAt; self.agentDefinitionID = agentDefinitionID
        self.nativeConversation = nativeConversation
    }
}

public struct WorkspaceSession: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var terminals: [TerminalRecord]
    public var createdAt: Date
    public init(id: UUID = UUID(), title: String, terminals: [TerminalRecord] = [], createdAt: Date = Date()) {
        self.id = id; self.title = title; self.terminals = terminals; self.createdAt = createdAt
    }
}

public enum AppPaths {
    public static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AgentBox", isDirectory: true)
    }
}

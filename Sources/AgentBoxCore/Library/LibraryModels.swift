import Foundation

public struct SavedAgent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var instructions: String
    public var provider: CLIProvider
    public var skillIDs: [UUID]
    public var memoryIDs: [UUID]
    public var revision: Int
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), name: String, summary: String = "", instructions: String = "", provider: CLIProvider = .claude, skillIDs: [UUID] = [], memoryIDs: [UUID] = [], revision: Int = 1, archived: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id=id; self.name=name; self.summary=summary; self.instructions=instructions; self.provider=provider; self.skillIDs=skillIDs; self.memoryIDs=memoryIDs; self.revision=revision; self.archived=archived; self.createdAt=createdAt; self.updatedAt=updatedAt
    }
}

public enum MemoryScope: String, Codable, CaseIterable, Sendable {
    case agent, project, task, preference
    public var label: String { switch self { case .agent: return "Agente"; case .project: return "Projeto"; case .task: return "Tarefa"; case .preference: return "Preferência" } }
}
public struct AgentMemory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var scope: MemoryScope
    public var scopeKey: String
    public var source: String
    public var revision: Int
    public var archived: Bool
    public var updatedAt: Date
    public init(id: UUID = UUID(), title: String, content: String, scope: MemoryScope = .agent, scopeKey: String, source: String = "Usuário", revision: Int = 1, archived: Bool = false, updatedAt: Date = Date()) {
        self.id=id; self.title=title; self.content=content; self.scope=scope; self.scopeKey=scopeKey; self.source=source; self.revision=revision; self.archived=archived; self.updatedAt=updatedAt
    }
}
public struct SkillEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    public var sourcePath: String
    public var content: String
    public var sha256: String
    public var importedAt: Date
    public init(id: UUID = UUID(), name: String, summary: String, sourcePath: String, content: String, sha256: String, importedAt: Date = Date()) {
        self.id=id; self.name=name; self.summary=summary; self.sourcePath=sourcePath; self.content=content; self.sha256=sha256; self.importedAt=importedAt
    }
}
public struct AgentUsageRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var agentID: UUID
    public var agentRevision: Int
    public var terminalID: UUID
    public var sessionID: UUID?
    public var computerIDs: [UUID]
    public var startedAt: Date
}
public struct LibraryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var agents: [SavedAgent]
    public var memories: [AgentMemory]
    public var skills: [SkillEntry]
    public var history: [AgentUsageRecord]
    public init(schemaVersion: Int = 1, agents: [SavedAgent] = [], memories: [AgentMemory] = [], skills: [SkillEntry] = [], history: [AgentUsageRecord] = []) {
        self.schemaVersion=schemaVersion; self.agents=agents; self.memories=memories; self.skills=skills; self.history=history
    }
}

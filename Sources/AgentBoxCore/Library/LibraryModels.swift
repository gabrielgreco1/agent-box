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
        self.id = id; self.name = name; self.summary = summary; self.instructions = instructions
        self.provider = provider; self.skillIDs = skillIDs; self.memoryIDs = memoryIDs
        self.revision = revision; self.archived = archived; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct AgentDefinitionRevision: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let agentID: UUID
    public let revision: Int
    public let name: String
    public let summary: String
    public let instructions: String
    public let provider: CLIProvider
    public let skillIDs: [UUID]
    public let memoryIDs: [UUID]
    public let recordedAt: Date
    public init(agent: SavedAgent, recordedAt: Date = Date()) {
        self.id = UUID(); self.agentID = agent.id; self.revision = agent.revision
        self.name = agent.name; self.summary = agent.summary; self.instructions = agent.instructions
        self.provider = agent.provider; self.skillIDs = agent.skillIDs; self.memoryIDs = agent.memoryIDs
        self.recordedAt = recordedAt
    }
}

public enum MemoryScope: String, Codable, CaseIterable, Sendable {
    case agent, project, task, preference, profile
    public var label: String {
        switch self {
        case .agent: return "Agente"
        case .project: return "Projeto"
        case .task: return "Tarefa"
        case .preference: return "Preferência"
        case .profile: return "Perfil"
        }
    }
}

public enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case preference, verifiedKnowledge, procedure, taskNote
    public var label: String {
        switch self {
        case .preference: return "Preferência"
        case .verifiedKnowledge: return "Conhecimento verificado"
        case .procedure: return "Procedimento"
        case .taskNote: return "Nota de tarefa"
        }
    }
}

public struct AgentMemory: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var content: String
    public var scope: MemoryScope
    public var scopeKey: String
    public var source: String
    public var kind: MemoryKind
    public var author: String
    public var revision: Int
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var validUntil: Date?

    public init(id: UUID = UUID(), title: String, content: String, scope: MemoryScope = .agent,
                scopeKey: String, source: String = "Usuário", revision: Int = 1,
                archived: Bool = false, updatedAt: Date = Date(), kind: MemoryKind = .taskNote,
                author: String = "Usuário", createdAt: Date = Date(), validUntil: Date? = nil) {
        self.id = id; self.title = title; self.content = content; self.scope = scope
        self.scopeKey = scopeKey; self.source = source; self.kind = kind; self.author = author
        self.revision = revision; self.archived = archived; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.validUntil = validUntil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, content, scope, scopeKey, source, kind, author, revision, archived
        case createdAt, updatedAt, validUntil
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        content = try c.decode(String.self, forKey: .content)
        scope = try c.decode(MemoryScope.self, forKey: .scope)
        scopeKey = try c.decode(String.self, forKey: .scopeKey)
        source = try c.decode(String.self, forKey: .source)
        kind = try c.decodeIfPresent(MemoryKind.self, forKey: .kind) ?? .taskNote
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "Usuário"
        revision = try c.decode(Int.self, forKey: .revision)
        archived = try c.decode(Bool.self, forKey: .archived)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
        validUntil = try c.decodeIfPresent(Date.self, forKey: .validUntil)
    }
}

public struct AgentMemoryRevision: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let memoryID: UUID
    public let revision: Int
    public let title: String
    public let content: String
    public let scope: MemoryScope
    public let scopeKey: String
    public let source: String
    public let kind: MemoryKind
    public let author: String
    public let archived: Bool
    public let validUntil: Date?
    public let recordedAt: Date
    public init(memory: AgentMemory, recordedAt: Date = Date()) {
        self.id = UUID(); self.memoryID = memory.id; self.revision = memory.revision
        self.title = memory.title; self.content = memory.content; self.scope = memory.scope
        self.scopeKey = memory.scopeKey; self.source = memory.source; self.kind = memory.kind
        self.author = memory.author; self.archived = memory.archived
        self.validUntil = memory.validUntil; self.recordedAt = recordedAt
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
        self.id = id; self.name = name; self.summary = summary; self.sourcePath = sourcePath
        self.content = content; self.sha256 = sha256; self.importedAt = importedAt
    }
}

public struct SelectedMemoryRevision: Codable, Equatable, Sendable {
    public let memoryID: UUID
    public let revision: Int
    public let title: String
    public let source: String
    public let kind: MemoryKind
    public let scope: MemoryScope
    public let scopeKey: String
    public init(memory: AgentMemory) {
        memoryID = memory.id; revision = memory.revision; title = memory.title
        source = memory.source; kind = memory.kind
        scope = memory.scope; scopeKey = memory.scopeKey
    }
}

public struct PreparedSkillReference: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let sha256: String
    public let sourcePath: String
    public init(skill: SkillEntry) {
        id = skill.id; name = skill.name; sha256 = skill.sha256; sourcePath = skill.sourcePath
    }
}

public struct PreparedAgentContext: Equatable, Sendable {
    public let agentID: UUID
    public let agentRevision: Int
    public let provider: CLIProvider
    public let text: String
    public let selectedMemories: [SelectedMemoryRevision]
    public let selectedSkills: [PreparedSkillReference]
}

/// Created only after an actual CLI launch is observed. A saved definition is never a run.
public struct AgentUsageRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var agentID: UUID
    public var agentRevision: Int
    public var terminalID: UUID
    public var sessionID: UUID?
    public var computerIDs: [UUID]
    public var profileIDs: [UUID]
    public var selectedMemories: [SelectedMemoryRevision]
    public var selectedSkills: [PreparedSkillReference]
    public var nativeSessionID: String?
    public var nativeAgentID: String?
    public var taskSummary: String?
    public var resultSummary: String?
    public var startedAt: Date
    public var endedAt: Date?

    public init(id: UUID = UUID(), agentID: UUID, agentRevision: Int, terminalID: UUID,
                sessionID: UUID? = nil, computerIDs: [UUID] = [], profileIDs: [UUID] = [],
                selectedMemories: [SelectedMemoryRevision] = [], selectedSkills: [PreparedSkillReference] = [],
                nativeSessionID: String? = nil, nativeAgentID: String? = nil,
                taskSummary: String? = nil, resultSummary: String? = nil,
                startedAt: Date = Date(), endedAt: Date? = nil) {
        self.id = id; self.agentID = agentID; self.agentRevision = agentRevision
        self.terminalID = terminalID; self.sessionID = sessionID; self.computerIDs = computerIDs
        self.profileIDs = profileIDs; self.selectedMemories = selectedMemories
        self.selectedSkills = selectedSkills; self.nativeSessionID = nativeSessionID
        self.nativeAgentID = nativeAgentID; self.taskSummary = taskSummary
        self.resultSummary = resultSummary; self.startedAt = startedAt; self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, agentID, agentRevision, terminalID, sessionID, computerIDs, profileIDs
        case selectedMemories, selectedSkills, nativeSessionID, nativeAgentID
        case taskSummary, resultSummary, startedAt, endedAt
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        agentID = try c.decode(UUID.self, forKey: .agentID)
        agentRevision = try c.decode(Int.self, forKey: .agentRevision)
        terminalID = try c.decode(UUID.self, forKey: .terminalID)
        sessionID = try c.decodeIfPresent(UUID.self, forKey: .sessionID)
        computerIDs = try c.decodeIfPresent([UUID].self, forKey: .computerIDs) ?? []
        profileIDs = try c.decodeIfPresent([UUID].self, forKey: .profileIDs) ?? []
        selectedMemories = try c.decodeIfPresent([SelectedMemoryRevision].self, forKey: .selectedMemories) ?? []
        selectedSkills = try c.decodeIfPresent([PreparedSkillReference].self, forKey: .selectedSkills) ?? []
        nativeSessionID = try c.decodeIfPresent(String.self, forKey: .nativeSessionID)
        nativeAgentID = try c.decodeIfPresent(String.self, forKey: .nativeAgentID)
        taskSummary = try c.decodeIfPresent(String.self, forKey: .taskSummary)
        resultSummary = try c.decodeIfPresent(String.self, forKey: .resultSummary)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
    }
}

public struct LibraryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var agents: [SavedAgent]
    public var agentRevisions: [AgentDefinitionRevision]
    public var memories: [AgentMemory]
    public var memoryRevisions: [AgentMemoryRevision]
    public var skills: [SkillEntry]
    public var history: [AgentUsageRecord]

    public init(schemaVersion: Int = 1, agents: [SavedAgent] = [], memories: [AgentMemory] = [],
                skills: [SkillEntry] = [], history: [AgentUsageRecord] = [],
                agentRevisions: [AgentDefinitionRevision] = [], memoryRevisions: [AgentMemoryRevision] = []) {
        self.schemaVersion = schemaVersion; self.agents = agents; self.memories = memories
        self.skills = skills; self.history = history; self.agentRevisions = agentRevisions
        self.memoryRevisions = memoryRevisions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, agents, agentRevisions, memories, memoryRevisions, skills, history
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        agents = try c.decode([SavedAgent].self, forKey: .agents)
        agentRevisions = try c.decodeIfPresent([AgentDefinitionRevision].self, forKey: .agentRevisions) ?? []
        memories = try c.decode([AgentMemory].self, forKey: .memories)
        memoryRevisions = try c.decodeIfPresent([AgentMemoryRevision].self, forKey: .memoryRevisions) ?? []
        skills = try c.decode([SkillEntry].self, forKey: .skills)
        history = try c.decode([AgentUsageRecord].self, forKey: .history)
    }
}

import Foundation

/// Pure, versioned edits. Callers persist the resulting document with LibraryRepository.
public enum LibraryMutations {
    public static func saveAgent(_ candidate: SavedAgent, in document: inout LibraryDocument,
                                 at time: Date = Date()) throws {
        guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryError.invalid("O agente precisa de um nome.")
        }
        var next = candidate
        next.updatedAt = time
        if let index = document.agents.firstIndex(where: { $0.id == candidate.id }) {
            let previous = document.agents[index]
            if !document.agentRevisions.contains(where: { $0.agentID == previous.id && $0.revision == previous.revision }) {
                document.agentRevisions.append(AgentDefinitionRevision(agent: previous, recordedAt: previous.updatedAt))
            }
            next.createdAt = previous.createdAt
            next.revision = previous.revision + 1
            document.agents[index] = next
        } else {
            next.createdAt = time; next.revision = 1
            document.agents.append(next)
        }
        document.agentRevisions.append(AgentDefinitionRevision(agent: next, recordedAt: time))
    }

    public static func saveMemory(_ candidate: AgentMemory, in document: inout LibraryDocument,
                                  selectingFor agentID: UUID? = nil, at time: Date = Date()) throws {
        guard !candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !candidate.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !candidate.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LibraryError.invalid("A memória precisa de título, conteúdo e fonte.")
        }
        if candidate.scope != .preference && candidate.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LibraryError.invalid("Escolha a identidade do escopo da memória.")
        }
        var next = candidate
        next.updatedAt = time
        let isNew = !document.memories.contains(where: { $0.id == candidate.id })
        if let index = document.memories.firstIndex(where: { $0.id == candidate.id }) {
            let previous = document.memories[index]
            if !document.memoryRevisions.contains(where: { $0.memoryID == previous.id && $0.revision == previous.revision }) {
                document.memoryRevisions.append(AgentMemoryRevision(memory: previous, recordedAt: previous.updatedAt))
            }
            next.createdAt = previous.createdAt
            next.revision = previous.revision + 1
            document.memories[index] = next
        } else {
            next.createdAt = time; next.revision = 1
            document.memories.append(next)
        }
        document.memoryRevisions.append(AgentMemoryRevision(memory: next, recordedAt: time))
        if isNew, let agentID, let index = document.agents.firstIndex(where: { $0.id == agentID }),
           !document.agents[index].memoryIDs.contains(next.id) {
            document.agents[index].memoryIDs.append(next.id)
            try bumpAgent(at: index, in: &document, time: time)
        }
    }

    public static func selectMemory(_ memoryID: UUID, for agentID: UUID,
                                    selected: Bool, in document: inout LibraryDocument,
                                    at time: Date = Date()) throws {
        guard let index = document.agents.firstIndex(where: { $0.id == agentID }) else {
            throw LibraryError.invalid("Agente indisponível.")
        }
        if selected {
            guard let memory = document.memories.first(where: { $0.id == memoryID && !$0.archived }) else {
                throw LibraryError.unavailableMemory(memoryID.uuidString)
            }
            if memory.scope == .agent && memory.scopeKey != agentID.uuidString {
                throw LibraryError.unavailableMemory(memory.title)
            }
        }
        let had = document.agents[index].memoryIDs.contains(memoryID)
        guard had != selected else { return }
        document.agents[index].memoryIDs.removeAll { $0 == memoryID }
        if selected { document.agents[index].memoryIDs.append(memoryID) }
        try bumpAgent(at: index, in: &document, time: time)
    }

    public static func selectSkill(_ skillID: UUID, for agentID: UUID,
                                   selected: Bool, in document: inout LibraryDocument,
                                   at time: Date = Date()) throws {
        guard let index = document.agents.firstIndex(where: { $0.id == agentID }) else {
            throw LibraryError.invalid("Agente indisponível.")
        }
        if selected && !document.skills.contains(where: { $0.id == skillID }) {
            throw LibraryError.invalid("Skill indisponível.")
        }
        let had = document.agents[index].skillIDs.contains(skillID)
        guard had != selected else { return }
        document.agents[index].skillIDs.removeAll { $0 == skillID }
        if selected { document.agents[index].skillIDs.append(skillID) }
        try bumpAgent(at: index, in: &document, time: time)
    }

    public static func deleteMemory(_ memoryID: UUID, in document: inout LibraryDocument,
                                    at time: Date = Date()) throws {
        guard document.memories.contains(where: { $0.id == memoryID }) else { return }
        document.memories.removeAll { $0.id == memoryID }
        // Revision snapshots remain for history; no future context can select the deleted memory.
        for index in document.agents.indices where document.agents[index].memoryIDs.contains(memoryID) {
            document.agents[index].memoryIDs.removeAll { $0 == memoryID }
            try bumpAgent(at: index, in: &document, time: time)
        }
    }

    /// Record only after the provider adapter observes that a CLI process actually launched.
    @discardableResult public static func recordRun(prepared: PreparedAgentContext,
                                                      terminalID: UUID, sessionID: UUID,
                                                      in document: inout LibraryDocument,
                                                      nativeSessionID: String? = nil,
                                                      nativeAgentID: String? = nil,
                                                      taskSummary: String? = nil,
                                                      startedAt: Date = Date()) throws -> AgentUsageRecord {
        guard document.agentRevisions.contains(where: { $0.agentID == prepared.agentID && $0.revision == prepared.agentRevision }) ||
              document.agents.contains(where: { $0.id == prepared.agentID && $0.revision == prepared.agentRevision }) else {
            throw LibraryError.invalid("A revisão de agente usada nesta execução não está disponível.")
        }
        let record = AgentUsageRecord(agentID: prepared.agentID, agentRevision: prepared.agentRevision,
                                      terminalID: terminalID, sessionID: sessionID,
                                      selectedMemories: prepared.selectedMemories,
                                      selectedSkills: prepared.selectedSkills,
                                      nativeSessionID: nativeSessionID, nativeAgentID: nativeAgentID,
                                      taskSummary: taskSummary, startedAt: startedAt)
        document.history.append(record)
        return record
    }

    public static func updateRunResources(_ runID: UUID, in document: inout LibraryDocument,
                                          computerIDs: [UUID], profileIDs: [UUID]) throws {
        guard let index = document.history.firstIndex(where: { $0.id == runID }) else {
            throw LibraryError.invalid("Execução não encontrada.")
        }
        document.history[index].computerIDs = computerIDs
        document.history[index].profileIDs = profileIDs
    }

    public static func finishRun(_ runID: UUID, in document: inout LibraryDocument,
                                 computerIDs: [UUID] = [], profileIDs: [UUID] = [],
                                 resultSummary: String? = nil, endedAt: Date = Date()) throws {
        guard let index = document.history.firstIndex(where: { $0.id == runID }) else {
            throw LibraryError.invalid("Execução não encontrada.")
        }
        document.history[index].computerIDs = computerIDs
        document.history[index].profileIDs = profileIDs
        document.history[index].resultSummary = resultSummary
        document.history[index].endedAt = endedAt
    }

    private static func bumpAgent(at index: Int, in document: inout LibraryDocument,
                                  time: Date) throws {
        let previous = document.agents[index]
        if !document.agentRevisions.contains(where: { $0.agentID == previous.id && $0.revision == previous.revision }) {
            document.agentRevisions.append(AgentDefinitionRevision(agent: previous, recordedAt: previous.updatedAt))
        }
        document.agents[index].revision += 1
        document.agents[index].updatedAt = time
        document.agentRevisions.append(AgentDefinitionRevision(agent: document.agents[index], recordedAt: time))
    }
}

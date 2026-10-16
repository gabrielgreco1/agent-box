import Foundation
import Combine
import AgentBoxCore

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var document = LibraryDocument()
    @Published var error: String?
    @Published private(set) var readOnly = false
    private let repository: LibraryRepository

    init(repository: LibraryRepository = LibraryRepository()) {
        self.repository = repository
        do { document = try repository.load() }
        catch { self.error = error.localizedDescription; readOnly = true }
    }

    @discardableResult func change(_ edit: (inout LibraryDocument) throws -> Void) -> Bool {
        guard !readOnly else {
            error = "A biblioteca não foi carregada. Corrija o arquivo antes de salvar; seus dados foram preservados."
            return false
        }
        var next = document
        do {
            try edit(&next)
            try repository.save(next)
            document = next
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @discardableResult func saveAgent(_ agent: SavedAgent) -> Bool {
        change { try LibraryMutations.saveAgent(agent, in: &$0) }
    }

    func duplicate(_ agent: SavedAgent) -> UUID? {
        var copy = agent
        copy.id = UUID(); copy.name += " · cópia"; copy.revision = 1
        copy.createdAt = Date(); copy.updatedAt = copy.createdAt; copy.archived = false
        let result = change { document in
            copy.memoryIDs = try agent.memoryIDs.compactMap { id in
                guard var memory = document.memories.first(where: { $0.id == id }) else { return nil }
                if memory.scope == .agent {
                    memory.id = UUID(); memory.scopeKey = copy.id.uuidString
                    memory.revision = 1; memory.createdAt = Date(); memory.updatedAt = memory.createdAt
                    try LibraryMutations.saveMemory(memory, in: &document)
                }
                return memory.id
            }
            try LibraryMutations.saveAgent(copy, in: &document)
        }
        return result ? copy.id : nil
    }

    func selectMemory(_ id: UUID, agentID: UUID, selected: Bool) {
        change { try LibraryMutations.selectMemory(id, for: agentID, selected: selected, in: &$0) }
    }
    func selectSkill(_ id: UUID, agentID: UUID, selected: Bool) {
        change { try LibraryMutations.selectSkill(id, for: agentID, selected: selected, in: &$0) }
    }
    @discardableResult func saveMemory(_ memory: AgentMemory, agentID: UUID) -> Bool {
        change { try LibraryMutations.saveMemory(memory, in: &$0, selectingFor: agentID) }
    }
    func setMemoryArchived(_ memory: AgentMemory, archived: Bool) {
        var next = memory; next.archived = archived
        change { try LibraryMutations.saveMemory(next, in: &$0) }
    }
    func deleteMemory(_ id: UUID) {
        change { try LibraryMutations.deleteMemory(id, in: &$0) }
    }

    func importSkill(_ url: URL, agentID: UUID?) {
        do {
            let skill = try SkillImporter.read(url)
            change { document in
                let entryID: UUID
                if let existing = document.skills.first(where: { $0.sha256 == skill.sha256 && $0.sourcePath == skill.sourcePath }) {
                    entryID = existing.id
                } else {
                    document.skills.append(skill); entryID = skill.id
                }
                if let agentID {
                    try LibraryMutations.selectSkill(entryID, for: agentID, selected: true, in: &document)
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}

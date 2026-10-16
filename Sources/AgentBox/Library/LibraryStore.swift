import Foundation
import Combine
import AgentBoxCore

@MainActor final class LibraryStore: ObservableObject {
    @Published private(set) var document=LibraryDocument()
    @Published var error: String?
    @Published private(set) var readOnly=false
    private let repository:LibraryRepository
    init(repository:LibraryRepository = LibraryRepository()) {
        self.repository=repository
        do { document=try repository.load() } catch { self.error=error.localizedDescription; readOnly=true }
    }
    @discardableResult func change(_ edit: (inout LibraryDocument)->Void)->Bool {
        guard !readOnly else { error="A biblioteca não foi carregada. Corrija o arquivo antes de salvar; seus dados foram preservados."; return false }
        var next=document; edit(&next)
        do { try repository.save(next); document=next; return true } catch { self.error=error.localizedDescription; return false }
    }
    func saveAgent(_ agent:SavedAgent) {
        change { doc in
            var next=agent; next.updatedAt=Date()
            if let i=doc.agents.firstIndex(where:{$0.id==agent.id}) { next.revision=doc.agents[i].revision+1; doc.agents[i]=next }
            else { doc.agents.append(next) }
        }
    }
    func duplicate(_ agent:SavedAgent) -> UUID? {
        var copy=agent;copy.id=UUID();copy.name += " · cópia";copy.revision=1;copy.createdAt=Date();copy.updatedAt=Date();copy.archived=false
        let result=change { doc in
            copy.memoryIDs=agent.memoryIDs.compactMap { id in
                guard var memory=doc.memories.first(where:{$0.id==id}) else { return nil }
                if memory.scope == .agent {
                    memory.id=UUID();memory.scopeKey=copy.id.uuidString;memory.revision=1;memory.updatedAt=Date();doc.memories.append(memory)
                }
                return memory.id
            }
            doc.agents.append(copy)
        }
        return result ? copy.id : nil
    }
    func selectMemory(_ id:UUID,agentID:UUID,selected:Bool) {
        change { doc in guard let i=doc.agents.firstIndex(where:{$0.id==agentID}) else {return}; doc.agents[i].memoryIDs.removeAll{$0==id}; if selected {doc.agents[i].memoryIDs.append(id)};doc.agents[i].revision+=1;doc.agents[i].updatedAt=Date() }
    }
    func selectSkill(_ id:UUID,agentID:UUID,selected:Bool) {
        change { doc in guard let i=doc.agents.firstIndex(where:{$0.id==agentID}) else {return}; doc.agents[i].skillIDs.removeAll{$0==id};if selected {doc.agents[i].skillIDs.append(id)};doc.agents[i].revision+=1;doc.agents[i].updatedAt=Date() }
    }
    func saveMemory(_ memory:AgentMemory, agentID:UUID) {
        change { doc in
            var next=memory; next.updatedAt=Date()
            if let i=doc.memories.firstIndex(where:{$0.id==memory.id}) {next.revision=doc.memories[i].revision+1;doc.memories[i]=next}
            else { doc.memories.append(next); if let i=doc.agents.firstIndex(where:{$0.id==agentID}) {doc.agents[i].memoryIDs.append(next.id);doc.agents[i].revision+=1} }
        }
    }
    func deleteMemory(_ id:UUID) {
        change { doc in doc.memories.removeAll{$0.id==id};for i in doc.agents.indices where doc.agents[i].memoryIDs.contains(id) {doc.agents[i].memoryIDs.removeAll{$0==id};doc.agents[i].revision+=1;doc.agents[i].updatedAt=Date()} }
    }
    func importSkill(_ url:URL,agentID:UUID?) {
        do {
            let skill=try SkillImporter.read(url)
            change { doc in
                let entryID:UUID
                if let existing=doc.skills.first(where:{$0.sha256==skill.sha256 && $0.sourcePath==skill.sourcePath}) {entryID=existing.id}
                else {doc.skills.append(skill);entryID=skill.id}
                if let agentID,let i=doc.agents.firstIndex(where:{$0.id==agentID}),!doc.agents[i].skillIDs.contains(entryID) {doc.agents[i].skillIDs.append(entryID);doc.agents[i].revision+=1;doc.agents[i].updatedAt=Date()}
            }
        } catch { self.error=error.localizedDescription }
    }
}

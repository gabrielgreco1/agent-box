import Foundation
import CryptoKit

public enum LibraryError: LocalizedError, Equatable {
    case unsupportedSchema(Int), invalid(String), unavailableMemory(String), oversized
    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "A biblioteca usa a versão \(version). O arquivo foi preservado."
        case .invalid(let message): return message
        case .unavailableMemory(let title): return "A memória ‘\(title)’ está arquivada, ausente ou pertence a outro escopo. Revise a seleção."
        case .oversized: return "O contexto ultrapassa 200 KB. Reduza a seleção antes de exportar."
        }
    }
}

public struct LibraryRepository {
    public let url: URL
    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("library.json")) { self.url=url }
    public func load() throws -> LibraryDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { return LibraryDocument() }
        let document = try JSONDecoder().decode(LibraryDocument.self, from: Data(contentsOf:url))
        guard document.schemaVersion == 1 else { throw LibraryError.unsupportedSchema(document.schemaVersion) }
        try Self.validate(document)
        return document
    }
    public func save(_ document: LibraryDocument) throws {
        try Self.validate(document)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:url.path)
    }
    private static func validate(_ document:LibraryDocument) throws {
        guard document.schemaVersion == 1 else { throw LibraryError.unsupportedSchema(document.schemaVersion) }
        guard Set(document.agents.map(\.id)).count == document.agents.count,
              Set(document.memories.map(\.id)).count == document.memories.count,
              Set(document.skills.map(\.id)).count == document.skills.count else {
            throw LibraryError.invalid("A biblioteca contém IDs duplicados; o arquivo original foi preservado.")
        }
        guard document.agents.allSatisfy({ !$0.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }) else {
            throw LibraryError.invalid("O agente precisa de um nome.")
        }
    }
}

public enum SkillImporter {
    /// Reads data only. It never evaluates frontmatter, shell substitutions or referenced scripts.
    public static func read(_ url: URL) throws -> SkillEntry {
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 1_048_576 else { throw LibraryError.invalid("A skill excede 1 MB.") }
        let data=try Data(contentsOf:url)
        guard let content=String(data:data,encoding:.utf8), !content.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw LibraryError.invalid("A skill precisa ser um arquivo de texto UTF-8 não vazio.") }
        var name=url.deletingPathExtension().lastPathComponent
        if name.uppercased() == "SKILL" { name=url.deletingLastPathComponent().lastPathComponent }
        var summary=""
        let lines=content.components(separatedBy:.newlines)
        if lines.first?.trimmingCharacters(in:.whitespaces) == "---" {
            for line in lines.dropFirst().prefix(while: { $0.trimmingCharacters(in:.whitespaces) != "---" }) {
                if line.hasPrefix("name:") { let value=plainValue(String(line.dropFirst(5))); if !value.isEmpty { name=value } }
                if line.hasPrefix("description:") { summary=plainValue(String(line.dropFirst(12))) }
            }
        }
        let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        return SkillEntry(name:name,summary:summary,sourcePath:url.standardizedFileURL.path,content:content,sha256:hash)
    }
    private static func plainValue(_ value:String)->String { value.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\"'"))) }
}

public enum LibraryContext {
    /// Generates reviewable text; does not activate a native CLI agent or install a skill.
    public static func render(agentID:UUID, in document:LibraryDocument, projectKey:String? = nil, taskKey:String? = nil) throws -> String {
        guard let agent=document.agents.first(where:{$0.id==agentID && !$0.archived}) else { throw LibraryError.invalid("Agente indisponível.") }
        var parts=["# \(agent.name)","Revisão: \(agent.revision)","## Instruções\n\(agent.instructions)"]
        for id in agent.memoryIDs {
            guard let memory=document.memories.first(where:{$0.id==id}), !memory.archived else { throw LibraryError.unavailableMemory(id.uuidString) }
            let allowed:Bool
            switch memory.scope { case .agent: allowed=memory.scopeKey==agent.id.uuidString; case .preference: allowed=true; case .project: allowed=projectKey != nil && projectKey==memory.scopeKey; case .task: allowed=taskKey != nil && taskKey==memory.scopeKey }
            guard allowed else { throw LibraryError.unavailableMemory(memory.title) }
            parts.append("## Memória: \(memory.title)\nEscopo: \(memory.scope.label) · revisão \(memory.revision)\nFonte: \(memory.source)\n\n\(memory.content)")
        }
        for id in agent.skillIDs {
            guard let skill=document.skills.first(where:{$0.id==id}) else { throw LibraryError.invalid("Uma skill selecionada não está mais disponível.") }
            parts.append("## Skill selecionada: \(skill.name)\nOrigem: \(skill.sourcePath)\nSHA-256: \(skill.sha256)\n\n\(skill.content)")
        }
        let text=parts.joined(separator:"\n\n")+"\n"
        guard text.utf8.count <= 200_000 else { throw LibraryError.oversized }
        return text
    }
}

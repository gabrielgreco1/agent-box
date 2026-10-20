import XCTest
@testable import RackyCore

final class LibraryTests:XCTestCase {
    func testRoundTripKeepsSelectionsAndRevisions() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let repo=LibraryRepository(url:directory.appendingPathComponent("library.json"))
        var agent=SavedAgent(name:"Pesquisador",instructions:"Salvar fontes.")
        let memory=AgentMemory(title:"Fonte",content:"Preservar URL",scopeKey:agent.id.uuidString)
        agent.memoryIDs=[memory.id]
        let document=LibraryDocument(agents:[agent],memories:[memory])
        try repo.save(document)
        XCTAssertEqual(try repo.load(),document)
        XCTAssertTrue(try LibraryContext.render(agentID:agent.id,in:repo.load()).contains("Preservar URL"))
    }
    func testUnknownSchemaAndCorruptFileArePreserved() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let file=directory.appendingPathComponent("library.json")
        let data=try JSONEncoder().encode(LibraryDocument(schemaVersion:99))
        try data.write(to:file)
        XCTAssertThrowsError(try LibraryRepository(url:file).load())
        XCTAssertEqual(try Data(contentsOf:file),data)
    }
    func testCrossAgentAndUnspecifiedProjectMemoryCannotExport() throws {
        var agent=SavedAgent(name:"A")
        var memory=AgentMemory(title:"Privada",content:"Não atravessar identidade",scopeKey:UUID().uuidString)
        agent.memoryIDs=[memory.id]
        XCTAssertThrowsError(try LibraryContext.render(agentID:agent.id,in:LibraryDocument(agents:[agent],memories:[memory])))
        memory.scope = .project;memory.scopeKey="project-a"
        let document=LibraryDocument(agents:[agent],memories:[memory])
        XCTAssertThrowsError(try LibraryContext.render(agentID:agent.id,in:document))
        XCTAssertNoThrow(try LibraryContext.render(agentID:agent.id,in:document,projectKey:"project-a"))
    }
    func testSkillImportIsDataAndHasStableDigest() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:dir)}
        let url=dir.appendingPathComponent("SKILL.md")
        let content="---\nname: Coleta\ndescription: $(touch should-not-exist)\n---\n# Coleta\nNão executar scripts ao importar.\n"
        try content.write(to:url,atomically:true,encoding:.utf8)
        let first=try SkillImporter.read(url),second=try SkillImporter.read(url)
        XCTAssertEqual(first.name,"Coleta");XCTAssertEqual(first.content,content);XCTAssertEqual(first.sha256,second.sha256);XCTAssertEqual(first.sha256.count,64)
        XCTAssertFalse(FileManager.default.fileExists(atPath:dir.appendingPathComponent("should-not-exist").path))
    }
    func testMissingSelectionDoesNotDisappearSilently() throws {
        let agent=SavedAgent(name:"A",skillIDs:[UUID()])
        XCTAssertThrowsError(try LibraryContext.render(agentID:agent.id,in:LibraryDocument(agents:[agent])))
    }
    func testOversizedContextIsRejectedRatherThanTruncated() throws {
        let agent=SavedAgent(name:"A",instructions:String(repeating:"x",count:200_001))
        XCTAssertThrowsError(try LibraryContext.render(agentID:agent.id,in:LibraryDocument(agents:[agent])))
    }
    func testAgentAndMemoryEditsPreserveImmutableRevisions() throws {
        var document=LibraryDocument()
        var agent=SavedAgent(name:"Pesquisador",instructions:"Primeira instrução")
        try LibraryMutations.saveAgent(agent,in:&document)
        agent.instructions="Instrução revista"
        try LibraryMutations.saveAgent(agent,in:&document)
        XCTAssertEqual(document.agents[0].revision,2)
        XCTAssertEqual(document.agentRevisions.map(\.revision),[1,2])
        XCTAssertEqual(document.agentRevisions[0].instructions,"Primeira instrução")
        XCTAssertEqual(document.agentRevisions[1].instructions,"Instrução revista")

        var memory=AgentMemory(title:"Fonte",content:"Primeiro conteúdo",scopeKey:agent.id.uuidString)
        try LibraryMutations.saveMemory(memory,in:&document,selectingFor:agent.id)
        memory.content="Conteúdo revisto"
        try LibraryMutations.saveMemory(memory,in:&document,selectingFor:agent.id)
        XCTAssertEqual(document.memories[0].revision,2)
        XCTAssertEqual(document.memoryRevisions.map(\.revision),[1,2])
        XCTAssertEqual(document.memoryRevisions[0].content,"Primeiro conteúdo")
        XCTAssertEqual(document.memoryRevisions[1].content,"Conteúdo revisto")
        XCTAssertEqual(document.agents[0].revision,3)
    }

    func testPreparedContextChecksIdentityScopeAndValidity() throws {
        let agent=SavedAgent(name:"A")
        let project=AgentMemory(title:"Projeto",content:"Somente projeto A",scope:.project,scopeKey:"project-a",source:"evidence-1")
        let profile=AgentMemory(title:"Perfil",content:"Identidade A",scope:.profile,scopeKey:"profile-a")
        let expired=AgentMemory(title:"Antiga",content:"Expirou",scopeKey:agent.id.uuidString,validUntil:Date(timeIntervalSince1970:1))
        let document=LibraryDocument(agents:[agent],memories:[project,profile,expired])
        XCTAssertThrowsError(try LibraryContext.prepare(agentID:agent.id,in:document,selectedMemoryIDs:[project.id]))
        let selected=try LibraryContext.prepare(agentID:agent.id,in:document,projectKey:"project-a",selectedMemoryIDs:[project.id])
        XCTAssertEqual(selected.selectedMemories[0].source,"evidence-1")
        XCTAssertEqual(selected.selectedMemories[0].revision,1)
        XCTAssertFalse(selected.text.contains("Identidade A"))
        XCTAssertThrowsError(try LibraryContext.prepare(agentID:agent.id,in:document,projectKey:"project-b",selectedMemoryIDs:[project.id]))
        XCTAssertThrowsError(try LibraryContext.prepare(agentID:agent.id,in:document,selectedMemoryIDs:[profile.id]))
        XCTAssertNoThrow(try LibraryContext.prepare(agentID:agent.id,in:document,profileKey:"profile-a",selectedMemoryIDs:[profile.id]))
        XCTAssertThrowsError(try LibraryContext.prepare(agentID:agent.id,in:document,selectedMemoryIDs:[expired.id]))
    }

    func testRunHistoryReferencesObservedIDsAndCapturedRevisions() throws {
        var document=LibraryDocument()
        let agent=SavedAgent(name:"A",instructions:"Pesquisar")
        try LibraryMutations.saveAgent(agent,in:&document)
        let memory=AgentMemory(title:"Procedimento",content:"Citar URL",scopeKey:agent.id.uuidString,source:"manual")
        try LibraryMutations.saveMemory(memory,in:&document,selectingFor:agent.id)
        let skill=SkillEntry(name:"Coleta",summary:"",sourcePath:"/tmp/SKILL.md",content:"# Skill",sha256:String(repeating:"a",count:64))
        document.skills.append(skill)
        try LibraryMutations.selectSkill(skill.id,for:agent.id,selected:true,in:&document)
        let prepared=try LibraryContext.prepare(agentID:agent.id,in:document)
        XCTAssertEqual(prepared.selectedSkills[0].sha256,skill.sha256)
        let terminalID=UUID(),sessionID=UUID(),computerID=UUID(),profileID=UUID()
        let run=try LibraryMutations.recordRun(prepared:prepared,terminalID:terminalID,sessionID:sessionID,
                                               in:&document,nativeSessionID:"native-123",taskSummary:"Buscar fontes")
        XCTAssertEqual(run.agentRevision,prepared.agentRevision)
        XCTAssertEqual(run.selectedMemories[0].source,"manual")
        XCTAssertEqual(run.terminalID,terminalID)
        try LibraryMutations.finishRun(run.id,in:&document,computerIDs:[computerID],profileIDs:[profileID],resultSummary:"Encontradas 2 fontes")
        XCTAssertEqual(document.history[0].sessionID,sessionID)
        XCTAssertEqual(document.history[0].computerIDs,[computerID])
        XCTAssertEqual(document.history[0].profileIDs,[profileID])
        XCTAssertEqual(document.history[0].resultSummary,"Encontradas 2 fontes")
        var revised=document.agents[0];revised.instructions="Nova revisão"
        try LibraryMutations.saveAgent(revised,in:&document)
        XCTAssertEqual(document.history[0].agentRevision,prepared.agentRevision)
        XCTAssertNotEqual(document.agents[0].revision,document.history[0].agentRevision)
    }

    func testDeletedMemoryCannotBeReusedButRevisionRemains() throws {
        var document=LibraryDocument()
        let agent=SavedAgent(name:"A")
        try LibraryMutations.saveAgent(agent,in:&document)
        let memory=AgentMemory(title:"Removida",content:"Texto",scopeKey:agent.id.uuidString)
        try LibraryMutations.saveMemory(memory,in:&document,selectingFor:agent.id)
        try LibraryMutations.deleteMemory(memory.id,in:&document)
        XCTAssertTrue(document.memories.isEmpty)
        XCTAssertEqual(document.memoryRevisions.first?.memoryID,memory.id)
        XCTAssertTrue(document.agents[0].memoryIDs.isEmpty)
        XCTAssertThrowsError(try LibraryContext.prepare(agentID:agent.id,in:document,selectedMemoryIDs:[memory.id]))
    }

    func testLegacyLibraryDocumentDecodesWithoutNewFields() throws {
        let agent=SavedAgent(name:"A")
        let memory=AgentMemory(title:"M",content:"C",scopeKey:agent.id.uuidString)
        let old=LibraryDocument(agents:[agent],memories:[memory])
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(old)) as? [String:Any])
        json.removeValue(forKey:"agentRevisions")
        json.removeValue(forKey:"memoryRevisions")
        var memories=try XCTUnwrap(json["memories"] as? [[String:Any]])
        memories[0].removeValue(forKey:"kind")
        memories[0].removeValue(forKey:"author")
        memories[0].removeValue(forKey:"createdAt")
        json["memories"]=memories
        let decoded=try JSONDecoder().decode(LibraryDocument.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(decoded.agentRevisions,[])
        XCTAssertEqual(decoded.memories[0].kind,.taskNote)
        XCTAssertEqual(decoded.memories[0].author,"Usuário")
    }

}

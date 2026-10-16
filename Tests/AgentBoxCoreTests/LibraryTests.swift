import XCTest
@testable import AgentBoxCore

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
}

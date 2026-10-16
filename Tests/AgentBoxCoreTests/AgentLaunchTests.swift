import XCTest
import CryptoKit
@testable import AgentBoxCore

final class AgentLaunchTests: XCTestCase {
    func testClaudePlanReviewsSelectionsThenWritesProtectedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let skillContent = "---\nname: pesquisa\ndescription: Usar fontes verificadas\n---\nUsar fontes verificadas.\n"
        let skillHash = SHA256.hash(data: Data(skillContent.utf8)).map { String(format: "%02x", $0) }.joined()
        let skill = SkillEntry(name: "Pesquisa", summary: "", sourcePath: "/imported/SKILL.md",
                               content: skillContent, sha256: skillHash)
        var agent = SavedAgent(name: "Pesquisador", instructions: "Pesquisar com fontes.", provider: .claude)
        let memory = AgentMemory(title: "Fonte", content: "Guardar a URL.", scopeKey: agent.id.uuidString,
                                 source: "Nota revisada", revision: 3)
        agent.memoryIDs = [memory.id]
        agent.skillIDs = [skill.id]
        let document = LibraryDocument(agents: [agent], memories: [memory], skills: [skill])
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))

        let plan = try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.contextFile.url.path))
        XCTAssertEqual(plan.activation, .claudeAppendPromptFile)
        XCTAssertEqual(plan.arguments, ["--append-system-prompt-file", plan.contextFile.url.path,
                                        "--plugin-dir", try XCTUnwrap(plan.pluginDirectory).path])
        XCTAssertTrue(plan.review.contextText.contains("Guardar a URL."))
        XCTAssertEqual(plan.review.selectedMemories.first?.revision, 3)
        XCTAssertEqual(plan.review.selectedMemories.first?.source, "Nota revisada")
        XCTAssertEqual(plan.review.selectedSkills.first?.sha256, skill.sha256)
        XCTAssertEqual(plan.review.selectedSkills.first?.sourcePath, skill.sourcePath)
        XCTAssertEqual(plan.review.skillFiles.first?.content, skillContent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(plan.skillFiles.first).url.path))

        XCTAssertThrowsError(try planner.materialize(plan, reviewedDigest: "unreviewed")) {
            XCTAssertEqual($0 as? AgentLaunchError, .reviewRequired)
        }
        let materialized = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        XCTAssertEqual(materialized.terminal?.provider, .claude)
        XCTAssertEqual(materialized.terminal?.agentDefinitionID, agent.id)
        XCTAssertEqual(materialized.terminal?.arguments, plan.arguments)
        XCTAssertEqual(try String(contentsOf: plan.contextFile.url, encoding: .utf8), plan.contextFile.text)
        let nativeSkill = try XCTUnwrap(plan.skillFiles.first)
        XCTAssertEqual(try String(contentsOf: nativeSkill.url, encoding: .utf8), skillContent)
        XCTAssertEqual((try XCTUnwrap(FileManager.default.attributesOfItem(atPath: nativeSkill.url.path)[.posixPermissions] as? NSNumber)).intValue & 0o777, 0o600)
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: plan.contextFile.url.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        XCTAssertNoThrow(try materialized.validateContextFile())
        let binding = try XCTUnwrap(materialized.binding)
        let decoded = try JSONDecoder().decode(AgentLaunchBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(decoded, binding)
        let restored = try planner.restore(decoded, terminal: try XCTUnwrap(materialized.terminal))
        XCTAssertEqual(restored.binding, binding)
        XCTAssertThrowsError(try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)) {
            XCTAssertEqual($0 as? AgentLaunchError, .alreadyMaterialized)
        }
        try planner.removeContextFile(for: materialized)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.contextFile.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nativeSkill.url.path))
    }

    func testRestoreRejectsTamperedBindingAndChangedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = SavedAgent(name: "Guardado", instructions: "Revisado", provider: .claude)
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]), workingDirectory: "/tmp")
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        let terminal = try XCTUnwrap(launch.terminal)
        let binding = try XCTUnwrap(launch.binding)
        XCTAssertNoThrow(try planner.restore(binding, terminal: terminal))
        let otherTerminal = TerminalRecord(id: terminal.id, title: terminal.title, provider: .claude,
                                           cwd: terminal.cwd, arguments: ["--dangerous"], agentDefinitionID: agent.id)
        XCTAssertThrowsError(try planner.restore(binding, terminal: otherTerminal))
        let wrongPath = AgentLaunchBinding(planID: binding.planID, agentDefinitionID: binding.agentDefinitionID,
                                           executablePath: binding.executablePath, contextFilePath: "/tmp/context.md",
                                           contextSHA256: binding.contextSHA256, provider: binding.provider,
                                           workingDirectory: binding.workingDirectory, arguments: binding.arguments)
        XCTAssertThrowsError(try planner.restore(wrongPath, terminal: terminal))
        let wrongExecutable = AgentLaunchBinding(planID: binding.planID, agentDefinitionID: binding.agentDefinitionID,
                                                 executablePath: "/usr/bin/false", contextFilePath: binding.contextFilePath,
                                                 contextSHA256: binding.contextSHA256, provider: binding.provider,
                                                 workingDirectory: binding.workingDirectory, arguments: binding.arguments)
        XCTAssertThrowsError(try planner.restore(wrongExecutable, terminal: terminal))
        try Data("changed".utf8).write(to: launch.contextFileURL)
        XCTAssertThrowsError(try planner.restore(binding, terminal: terminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
    }

    func testCodexPlanExportsWithoutClaimingActivation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = SavedAgent(name: "Codex agent", instructions: "Preservar contexto.", provider: .codex)
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.codex: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]), workingDirectory: "/tmp")
        XCTAssertFalse(plan.activation.contextIsActiveAtLaunch)
        XCTAssertTrue(plan.arguments.isEmpty)
        let export = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        XCTAssertNil(export.terminal)
        XCTAssertNoThrow(try export.validateContextFile())
    }

    func testInvalidMemorySelectionDoesNotWriteContext() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = SavedAgent(name: "A", provider: .claude)
        let memory = AgentMemory(title: "Outro projeto", content: "privado", scope: .project, scopeKey: "project-b")
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        XCTAssertThrowsError(try planner.prepare(agentID: agent.id,
                                                  in: LibraryDocument(agents: [agent], memories: [memory]),
                                                  workingDirectory: "/tmp", projectKey: "project-a",
                                                  selectedMemoryIDs: [memory.id]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testNativeSkillTamperingBlocksRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "---\nname: native-test\ndescription: Test\n---\nNative instructions.\n"
        let hash = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        let skill = SkillEntry(name: "Native", summary: "Test", sourcePath: "/imported/native/SKILL.md",
                               content: content, sha256: hash)
        var agent = SavedAgent(name: "Saved", provider: .claude)
        agent.skillIDs = [skill.id]
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent], skills: [skill]),
                                       workingDirectory: "/tmp")
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        let binding = try XCTUnwrap(launch.binding)
        let terminal = try XCTUnwrap(launch.terminal)
        XCTAssertNoThrow(try planner.restore(binding, terminal: terminal))
        try Data("altered".utf8).write(to: try XCTUnwrap(plan.skillFiles.first).url)
        XCTAssertThrowsError(try launch.validateContextFile()) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
        XCTAssertThrowsError(try planner.restore(binding, terminal: terminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
    }

    func testInvalidSkillHashDoesNotWriteFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let skill = SkillEntry(name: "Broken", summary: "", sourcePath: "/imported/SKILL.md",
                               content: "Instructions", sha256: String(repeating: "0", count: 64))
        var agent = SavedAgent(name: "Saved", provider: .claude)
        agent.skillIDs = [skill.id]
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        XCTAssertThrowsError(try planner.prepare(agentID: agent.id,
                                                  in: LibraryDocument(agents: [agent], skills: [skill]),
                                                  workingDirectory: "/tmp")) {
            guard case .incompatibleSkill = $0 as? AgentLaunchError else { return XCTFail("Expected incompatible skill") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}

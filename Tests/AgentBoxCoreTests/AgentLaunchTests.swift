import XCTest
import CryptoKit
@testable import AgentBoxCore

final class AgentLaunchTests: XCTestCase {
    func testClaudePlanReviewsSelectionsThenWritesProtectedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let skillContent = "---\nname: pesquisa\ndescription: Usar fontes verificadas\n---\nUsar fontes verificadas.\n"
        let skillHash = SHA256.hash(data: Data(skillContent.utf8)).map { String(format: "%02x", $0) }.joined()
        let skillSource = try makeSkillPackage(at: root, content: skillContent)
        let skill = SkillEntry(name: "Pesquisa", summary: "", sourcePath: skillSource.path,
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

    func testDistinctReviewedPlansCanReuseOneTerminalID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = SavedAgent(name: "Guardado", instructions: "Revisado", provider: .claude)
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let document = LibraryDocument(agents: [agent])
        let terminalID = UUID()
        let firstPlan = try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")
        let firstLaunch = try planner.materialize(firstPlan, reviewedDigest: firstPlan.review.contextSHA256,
                                                  terminalID: terminalID)
        let firstTerminal = try XCTUnwrap(firstLaunch.terminal)
        let firstBinding = try XCTUnwrap(firstLaunch.binding)
        XCTAssertEqual(firstTerminal.id, terminalID)
        XCTAssertEqual(firstBinding.terminalID, terminalID)
        XCTAssertEqual(firstBinding.planID, firstPlan.id)
        XCTAssertNoThrow(try planner.restore(firstBinding, terminal: firstTerminal))

        let secondPlan = try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")
        let secondLaunch = try planner.materialize(secondPlan, reviewedDigest: secondPlan.review.contextSHA256,
                                                   terminalID: terminalID)
        let secondTerminal = try XCTUnwrap(secondLaunch.terminal)
        let secondBinding = try XCTUnwrap(secondLaunch.binding)
        XCTAssertNotEqual(secondPlan.id, firstPlan.id)
        XCTAssertEqual(secondTerminal.id, terminalID)
        XCTAssertEqual(secondBinding.terminalID, terminalID)
        XCTAssertEqual(secondBinding.planID, secondPlan.id)
        XCTAssertNotEqual(secondLaunch.contextFileURL, firstLaunch.contextFileURL)
        XCTAssertEqual(secondLaunch.contextFileURL, secondPlan.contextFile.url)
        XCTAssertNoThrow(try planner.restore(secondBinding, terminal: secondTerminal))

        let mismatchedTerminal = TerminalRecord(id: secondPlan.id, title: secondTerminal.title,
                                                 provider: secondTerminal.provider, cwd: secondTerminal.cwd,
                                                 arguments: secondTerminal.arguments,
                                                 agentDefinitionID: secondTerminal.agentDefinitionID)
        XCTAssertThrowsError(try planner.restore(secondBinding, terminal: mismatchedTerminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .invalidBinding)
        }
    }

    func testLegacyBindingDecodesTerminalIDFromPlanID() throws {
        let planID = UUID()
        let binding = AgentLaunchBinding(planID: planID, agentDefinitionID: UUID(),
                                         executablePath: "/bin/sh", contextFilePath: "/tmp/context.md",
                                         contextSHA256: String(repeating: "0", count: 64), provider: .claude,
                                         workingDirectory: "/tmp", arguments: [])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any])
        json.removeValue(forKey: "terminalID")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AgentLaunchBinding.self, from: legacyData)
        XCTAssertEqual(decoded.planID, planID)
        XCTAssertEqual(decoded.terminalID, planID)
        XCTAssertEqual(decoded, binding)
    }

    func testComputerMCPFilesAreProtectedAndRestoredWithReviewedPlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = SavedAgent(name: "Browser", instructions: "Use the assigned computer", provider: .claude)
        let computerID = UUID()
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]),
                                       workingDirectory: "/tmp", computerID: computerID,
                                       mcpHelper: URL(fileURLWithPath: "/bin/sh"))
        let mcp = try XCTUnwrap(plan.computerMCP)
        let capability = try XCTUnwrap(plan.mcpCapabilityData)
        XCTAssertEqual(mcp.computerID, computerID)
        XCTAssertEqual(Array(plan.arguments.suffix(2)), ["--mcp-config", mcp.configPath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: mcp.configPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mcp.capabilityPath))
        XCTAssertFalse(plan.review.contextText.contains(String(decoding: capability, as: UTF8.self)))

        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        XCTAssertEqual(launch.computerMCP, mcp)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: mcp.configPath)), plan.mcpConfigData)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: mcp.capabilityPath)), capability)
        for path in [mcp.configPath, mcp.capabilityPath] {
            let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        }
        XCTAssertNoThrow(try launch.validateContextFile())
        let binding = try XCTUnwrap(launch.binding)
        let decoded = try JSONDecoder().decode(AgentLaunchBinding.self, from: JSONEncoder().encode(binding))
        XCTAssertEqual(decoded.computerMCP, mcp)
        let restored = try planner.restore(decoded, terminal: try XCTUnwrap(launch.terminal))
        XCTAssertEqual(restored.computerMCP, mcp)
        try planner.removeContextFile(for: launch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mcp.configPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mcp.capabilityPath))
    }

    func testComputerMCPRejectsTamperedFilesAndMismatchedPlanPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let agent = SavedAgent(name: "Browser", provider: .claude)
        let planner = AgentLaunchPlanner(contextDirectory: root,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]),
                                       workingDirectory: "/tmp", computerID: UUID(),
                                       mcpHelper: URL(fileURLWithPath: "/bin/sh"))
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        let mcp = try XCTUnwrap(launch.computerMCP)
        let terminal = try XCTUnwrap(launch.terminal)
        let binding = try XCTUnwrap(launch.binding)

        try Data("changed config".utf8).write(to: URL(fileURLWithPath: mcp.configPath))
        XCTAssertThrowsError(try launch.validateContextFile()) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
        try XCTUnwrap(plan.mcpConfigData).write(to: URL(fileURLWithPath: mcp.configPath))
        try Data("changed capability".utf8).write(to: URL(fileURLWithPath: mcp.capabilityPath))
        XCTAssertThrowsError(try planner.restore(binding, terminal: terminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
        try XCTUnwrap(plan.mcpCapabilityData).write(to: URL(fileURLWithPath: mcp.capabilityPath))

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any])
        var descriptor = try XCTUnwrap(json["computerMCP"] as? [String: Any])
        descriptor["configPath"] = root.appendingPathComponent(UUID().uuidString).appendingPathComponent("computer.mcp.json").path
        json["computerMCP"] = descriptor
        let wrongPath = try JSONDecoder().decode(AgentLaunchBinding.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try planner.restore(wrongPath, terminal: terminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .invalidBinding)
        }
    }

    func testClaudeHooksFreezeReviewedTemplateAndCreateFreshProcessInvocations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("source-hook.py")
        try Data("#!/usr/bin/env python3\nimport sys\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let agent = SavedAgent(name: "Hooked", provider: .claude)
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]),
                                       workingDirectory: "/tmp", hookScriptURL: script)
        let descriptor = try XCTUnwrap(plan.claudeHookSnapshot?.descriptor)
        var legacyDescriptor = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor)) as? [String: Any])
        for key in ["childContextPath", "childContextHash", "childContextChunkCount"] { legacyDescriptor.removeValue(forKey: key) }
        XCTAssertEqual(try JSONDecoder().decode(ClaudeHookLaunchDescriptor.self,
            from: JSONSerialization.data(withJSONObject: legacyDescriptor)), descriptor)
        XCTAssertEqual(Array(plan.arguments.suffix(2)), ["--settings", descriptor.settingsPath])
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.settingsPath))
        try Data("#!/usr/bin/env python3\nraise RuntimeError('changed after review')\n".utf8).write(to: script)
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        XCTAssertNil(launch.claudeHook)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: descriptor.scriptPath)),
                       plan.claudeHookSnapshot?.scriptData)
        for path in [descriptor.settingsPath, descriptor.scriptPath] {
            let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)
            XCTAssertEqual(permissions.intValue & 0o077, 0)
        }
        let first = try launch.prepareHookInvocation()
        let second = try launch.prepareHookInvocation()
        let firstHook = try XCTUnwrap(first.claudeHook)
        let secondHook = try XCTUnwrap(second.claudeHook)
        XCTAssertNotEqual(firstHook.runID, secondHook.runID)
        XCTAssertNotEqual(firstHook.inboxURL, secondHook.inboxURL)
        XCTAssertNotEqual(firstHook.settingsURL, secondHook.settingsURL)
        XCTAssertNotEqual(firstHook.environment["AGENT_BOX_HOOK_TOKEN"],
                          secondHook.environment["AGENT_BOX_HOOK_TOKEN"])
        let firstToken = firstHook.settingsURL.deletingLastPathComponent().appendingPathComponent("hook.token")
        let originalToken = try Data(contentsOf: firstToken)
        let originalSettings = try Data(contentsOf: firstHook.settingsURL)
        XCTAssertThrowsError(try launch.prepareHookInvocation(runID: firstHook.runID)) {
            XCTAssertEqual($0 as? AgentLaunchError, .alreadyMaterialized)
        }
        XCTAssertEqual(try Data(contentsOf: firstToken), originalToken)
        XCTAssertEqual(try Data(contentsOf: firstHook.settingsURL), originalSettings)
        XCTAssertEqual(try Data(contentsOf: firstHook.inboxURL), Data())
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data("keep".utf8).write(to: sentinel)
        let linkedRunID = UUID()
        let linkedRun = firstHook.settingsURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(linkedRunID.uuidString)
        try FileManager.default.createSymbolicLink(at: linkedRun, withDestinationURL: outside)
        XCTAssertThrowsError(try launch.prepareHookInvocation(runID: linkedRunID)) {
            XCTAssertEqual($0 as? AgentLaunchError, .alreadyMaterialized)
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linkedRun.path), outside.path)
        XCTAssertEqual(Array(try XCTUnwrap(first.terminal).arguments.suffix(2)),
                       ["--settings", firstHook.settingsURL.path])
        XCTAssertEqual(first.binding, launch.binding)
        XCTAssertEqual(second.binding, launch.binding)
        XCTAssertThrowsError(try first.prepareHookInvocation()) {
            XCTAssertEqual($0 as? AgentLaunchError, .invalidBinding)
        }
        XCTAssertNoThrow(try first.validateContextFile())
        XCTAssertNoThrow(try second.validateContextFile())
        let binding = try XCTUnwrap(first.binding)
        let restored = try planner.restore(binding, terminal: try XCTUnwrap(launch.terminal))
        XCTAssertNil(restored.claudeHook)
        let third = try restored.prepareHookInvocation()
        XCTAssertNotEqual(third.claudeHook?.runID, firstHook.runID)
        XCTAssertEqual(try Data(contentsOf: firstHook.inboxURL), Data())
        XCTAssertEqual(try Data(contentsOf: secondHook.inboxURL), Data())
        try planner.removeContextFile(for: launch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstHook.inboxURL.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
    }

    func testReviewedScrapingSkillIsFrozenForNativeChildContextAndTamperingBlocksRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("source-hook.py")
        try Data("#!/usr/bin/env python3\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let content = "---\nname: webscraping-expert\n---\n" + String(repeating: "Read sources é😀 and keep links.\n", count: 650)
        let source = try makeSkillPackage(at: root, content: content)
        let hash = SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
        let skill = SkillEntry(name: "webscraping-expert", summary: "", sourcePath: source.path,
                               content: content, sha256: hash)
        let agent = SavedAgent(name: "Scraping", provider: .claude, skillIDs: [skill.id])
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
            resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let document = LibraryDocument(agents: [agent], skills: [skill])
        let plan = try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp", hookScriptURL: script)
        let descriptor = try XCTUnwrap(plan.claudeHookSnapshot?.descriptor)
        XCTAssertGreaterThan(descriptor.childContextChunkCount, 1)
        XCTAssertEqual(descriptor.childContextPath,
            plan.contextFile.url.deletingLastPathComponent().appendingPathComponent("child-skill-context.txt").path)
        XCTAssertEqual(descriptor.childContextHash, plan.claudeHookSnapshot?.childContextData.map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        })
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        XCTAssertNoThrow(try launch.validateContextFile())
        let binding = try XCTUnwrap(launch.binding)
        XCTAssertEqual(try planner.restore(binding, terminal: try XCTUnwrap(launch.terminal)).binding, binding)
        let childFile = URL(fileURLWithPath: try XCTUnwrap(descriptor.childContextPath))
        XCTAssertTrue(try String(contentsOf: childFile, encoding: .utf8).contains(content))
        try Data("tampered".utf8).write(to: childFile)
        XCTAssertThrowsError(try launch.validateContextFile())
        XCTAssertThrowsError(try planner.restore(binding, terminal: try XCTUnwrap(launch.terminal)))
    }

    func testClaudeHooksRejectTamperedTemplateAndInvocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("source-hook.py")
        try Data("#!/usr/bin/env python3\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let agent = SavedAgent(name: "Hooked", provider: .claude)
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent]),
                                       workingDirectory: "/tmp", hookScriptURL: script)
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        let binding = try XCTUnwrap(launch.binding)
        let terminal = try XCTUnwrap(launch.terminal)
        let invocation = try launch.prepareHookInvocation()
        let tokenPath = try XCTUnwrap(invocation.claudeHook).settingsURL.deletingLastPathComponent()
            .appendingPathComponent("hook.token")
        try Data("bad".utf8).write(to: tokenPath)
        XCTAssertThrowsError(try invocation.validateContextFile()) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
        XCTAssertNoThrow(try launch.validateContextFile())
        let descriptor = try XCTUnwrap(launch.claudeHookDescriptor)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(binding)) as? [String: Any])
        var hookJSON = try XCTUnwrap(json["claudeHookDescriptor"] as? [String: Any])
        hookJSON["scriptPath"] = root.appendingPathComponent("outside.py").path
        json["claudeHookDescriptor"] = hookJSON
        let wrongPath = try JSONDecoder().decode(AgentLaunchBinding.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try planner.restore(wrongPath, terminal: terminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .invalidBinding)
        }
        try Data("changed script".utf8).write(to: URL(fileURLWithPath: descriptor.scriptPath))
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
        let skillSource = try makeSkillPackage(at: root, content: content)
        let skill = SkillEntry(name: "Native", summary: "Test", sourcePath: skillSource.path,
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

    func testSupportFilesFreezeAtReviewAndTamperingBlocksRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "---\nname: webscraping-expert\n---\nRead approach/guide.md.\n"
        let source = try makeSkillPackage(at: root, content: content)
        let guide = source.deletingLastPathComponent().appendingPathComponent("approach/guide.md")
        try FileManager.default.createDirectory(at: guide.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original guide".utf8).write(to: guide)
        let skill = try SkillImporter.read(source)
        var agent = SavedAgent(name: "Scraping", provider: .claude)
        agent.skillIDs = [skill.id]
        let planner = AgentLaunchPlanner(contextDirectory: root.appendingPathComponent("contexts"),
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let plan = try planner.prepare(agentID: agent.id, in: LibraryDocument(agents: [agent], skills: [skill]),
                                       workingDirectory: "/tmp")
        XCTAssertEqual(plan.review.supportFiles.count, 1)
        XCTAssertEqual(plan.review.supportFiles.first?.data, Data("original guide".utf8))
        try Data("changed after review".utf8).write(to: guide)
        let launch = try planner.materialize(plan, reviewedDigest: plan.review.contextSHA256)
        let frozen = try XCTUnwrap(launch.supportFiles.first)
        XCTAssertEqual(try Data(contentsOf: frozen.url), Data("original guide".utf8))
        let binding = try XCTUnwrap(launch.binding)
        let terminal = try XCTUnwrap(launch.terminal)
        XCTAssertEqual(binding.supportFileHashes.count, 1)
        XCTAssertNoThrow(try planner.restore(binding, terminal: terminal))
        try Data("tampered".utf8).write(to: frozen.url)
        XCTAssertThrowsError(try planner.restore(binding, terminal: terminal)) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
        try FileManager.default.removeItem(at: frozen.url)
        XCTAssertThrowsError(try launch.validateContextFile()) {
            XCTAssertEqual($0 as? AgentLaunchError, .contextChanged)
        }
    }

    func testSupportPackageRejectsSymlinksAndMissingSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSkillPackage(at: root, content: "---\nname: scraping\n---\nRead guides.\n")
        let skill = try SkillImporter.read(source)
        var agent = SavedAgent(name: "Scraping", provider: .claude)
        agent.skillIDs = [skill.id]
        let document = LibraryDocument(agents: [agent], skills: [skill])
        let contexts = root.appendingPathComponent("contexts")
        let planner = AgentLaunchPlanner(contextDirectory: contexts,
                                         resolver: CLIExecutableResolver(overrides: [.claude: "/bin/sh"]))
        let link = source.deletingLastPathComponent().appendingPathComponent("guide.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        XCTAssertThrowsError(try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")) {
            guard case .incompatibleSkill = $0 as? AgentLaunchError else { return XCTFail("Expected incompatible skill") }
        }
        try FileManager.default.removeItem(at: link)
        try Data("-----BEGIN OPENSSH PRIVATE KEY-----\nsecret\n".utf8).write(to: link)
        XCTAssertThrowsError(try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")) {
            guard case .incompatibleSkill = $0 as? AgentLaunchError else { return XCTFail("Expected incompatible skill") }
        }
        try FileManager.default.removeItem(at: link)
        try FileManager.default.removeItem(at: source)
        XCTAssertThrowsError(try planner.prepare(agentID: agent.id, in: document, workingDirectory: "/tmp")) {
            guard case .incompatibleSkill = $0 as? AgentLaunchError else { return XCTFail("Expected incompatible skill") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: contexts.path))
    }

    private func makeSkillPackage(at root: URL, content: String) throws -> URL {
        let directory = root.appendingPathComponent("skill", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("SKILL.md")
        try Data(content.utf8).write(to: source)
        return source
    }
}

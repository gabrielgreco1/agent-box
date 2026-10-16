import Foundation
import CryptoKit
import Darwin

public enum AgentLaunchActivation: Equatable, Sendable {
    /// Claude Code reads a snapshot file while keeping its native system prompt and TUI.
    case claudeAppendPromptFile
    /// The snapshot is reviewable/exportable but not presented as active in this CLI.
    case exportOnly(reason: String)

    public var contextIsActiveAtLaunch: Bool {
        if case .claudeAppendPromptFile = self { return true }
        return false
    }
}

public struct AgentLaunchContextFile: Equatable, Sendable {
    public let url: URL
    public let sha256: String
    public let text: String
}

/// Exact imported bytes copied into a session-only Claude plugin.
public struct AgentLaunchSkillFile: Equatable, Sendable {
    public let reference: PreparedSkillReference
    public let url: URL
    public let content: String
}

public struct AgentLaunchSupportFile: Equatable, Sendable {
    public let url: URL
    public let data: Data
    public let sha256: String
}

public struct AgentLaunchPlan: Equatable, Sendable {
    public let id: UUID
    public let agentID: UUID
    public let agentRevision: Int
    public let agentName: String
    public let provider: CLIProvider
    public let executablePath: String
    public let workingDirectory: String
    public let arguments: [String]
    public let environmentOverrides: [String: String]
    public let contextFile: AgentLaunchContextFile
    public let selectedMemories: [SelectedMemoryRevision]
    public let selectedSkills: [PreparedSkillReference]
    public let skillFiles: [AgentLaunchSkillFile]
    public let supportFiles: [AgentLaunchSupportFile]
    public let pluginDirectory: URL?
    public let computerMCP: ComputerMCPConfiguration?
    public let mcpConfigData: Data?
    public let mcpCapabilityData: Data?
    public let claudeHookSnapshot: ClaudeHookLaunchSnapshot?
    public let activation: AgentLaunchActivation

    /// Full text and provenance for a human review before `materialize` writes a file.
    public var review: AgentLaunchReview {
        AgentLaunchReview(agentName: agentName, agentRevision: agentRevision, provider: provider,
                          executablePath: executablePath, workingDirectory: workingDirectory,
                          arguments: arguments, environmentOverrides: environmentOverrides,
                          contextFilePath: contextFile.url.path, contextSHA256: contextFile.sha256,
                          contextText: contextFile.text, selectedMemories: selectedMemories,
                          selectedSkills: selectedSkills, skillFiles: skillFiles, supportFiles: supportFiles,
                          pluginDirectoryPath: pluginDirectory?.path, activation: activation)
    }
}

public struct AgentLaunchReview: Equatable, Sendable {
    public let agentName: String
    public let agentRevision: Int
    public let provider: CLIProvider
    public let executablePath: String
    public let workingDirectory: String
    public let arguments: [String]
    public let environmentOverrides: [String: String]
    public let contextFilePath: String
    public let contextSHA256: String
    public let contextText: String
    public let selectedMemories: [SelectedMemoryRevision]
    public let selectedSkills: [PreparedSkillReference]
    public let skillFiles: [AgentLaunchSkillFile]
    public let supportFiles: [AgentLaunchSupportFile]
    public let pluginDirectoryPath: String?
    public let activation: AgentLaunchActivation
}

/// `terminal` is nil when the selected CLI has no verified safe context adapter.
/// A caller may export/show that context, then separately open a plain CLI terminal.
public struct MaterializedAgentLaunch: Equatable, Sendable {
    public let planID: UUID
    public let executablePath: String
    public let contextFileURL: URL
    public let contextSHA256: String
    public let terminal: TerminalRecord?
    public let activation: AgentLaunchActivation
    public let skillFiles: [AgentLaunchSkillFile]
    public let supportFiles: [AgentLaunchSupportFile]
    public let pluginDirectory: URL?
    public let computerMCP: ComputerMCPConfiguration?
    public let claudeHookDescriptor: ClaudeHookLaunchDescriptor?
    public let claudeHook: ClaudeHookInboxConfiguration?

    /// Persist only this metadata. The context body stays in its protected snapshot file.
    public var binding: AgentLaunchBinding? {
        guard let terminal, let agentID = terminal.agentDefinitionID else { return nil }
        var storedArguments = terminal.arguments
        if let claudeHookDescriptor, let claudeHook {
            guard Array(storedArguments.suffix(2)) == ["--settings", claudeHook.settingsURL.path] else { return nil }
            storedArguments.replaceSubrange((storedArguments.count - 2)..<storedArguments.count,
                                            with: ["--settings", claudeHookDescriptor.settingsPath])
        }
        return AgentLaunchBinding(planID: planID, terminalID: terminal.id, agentDefinitionID: agentID,
                                  executablePath: executablePath, contextFilePath: contextFileURL.path,
                                  contextSHA256: contextSHA256, provider: terminal.provider,
                                  workingDirectory: terminal.cwd, arguments: storedArguments,
                                  skillReferences: skillFiles.map(\.reference),
                                  supportFileHashes: Dictionary(uniqueKeysWithValues: supportFiles.map {
                                      ($0.url.path.replacingOccurrences(of: pluginDirectory!.path + "/", with: ""), $0.sha256)
                                  }), computerMCP: computerMCP,
                                  claudeHookDescriptor: claudeHookDescriptor)
    }

    public func validateContextFile() throws {
        let snapshotRoot = contextFileURL.deletingLastPathComponent().deletingLastPathComponent()
        try Self.requireRegularFile(contextFileURL, through: snapshotRoot)
        let data = try Data(contentsOf: contextFileURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == contextSHA256 else { throw AgentLaunchError.contextChanged }
        for skill in skillFiles {
            try Self.requireRegularFile(skill.url, through: snapshotRoot)
            let data = try Data(contentsOf: skill.url)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == skill.reference.sha256 else {
                throw AgentLaunchError.contextChanged
            }
        }
        for support in supportFiles {
            try Self.requireRegularFile(support.url, through: snapshotRoot)
            let data = try Data(contentsOf: support.url)
            guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == support.sha256 else {
                throw AgentLaunchError.contextChanged
            }
        }
        try computerMCP?.validate(directory: contextFileURL.deletingLastPathComponent())
        if let claudeHookDescriptor {
            let directory = contextFileURL.deletingLastPathComponent()
            try claudeHookDescriptor.validate(directory: directory)
            if let claudeHook {
                try claudeHookDescriptor.validateInvocation(claudeHook, directory: directory)
            }
        } else if claudeHook != nil { throw AgentLaunchError.invalidBinding }
    }

    /// Prepare a fresh authenticated hook run for one process start. A terminal
    /// restored from the same reviewed snapshot receives a distinct run ID.
    public func prepareHookInvocation(runID: UUID = UUID()) throws -> MaterializedAgentLaunch {
        try validateContextFile()
        guard let descriptor = claudeHookDescriptor, claudeHook == nil,
              var terminal, Array(terminal.arguments.suffix(2)) == ["--settings", descriptor.settingsPath] else {
            throw AgentLaunchError.invalidBinding
        }
        let configuration = try descriptor.prepareInvocation(
            directory: contextFileURL.deletingLastPathComponent(), runID: runID)
        terminal.arguments.replaceSubrange((terminal.arguments.count - 2)..<terminal.arguments.count,
                                           with: ["--settings", configuration.settingsURL.path])
        return MaterializedAgentLaunch(planID: planID, executablePath: executablePath,
            contextFileURL: contextFileURL, contextSHA256: contextSHA256,
            terminal: terminal, activation: activation, skillFiles: skillFiles,
            supportFiles: supportFiles, pluginDirectory: pluginDirectory,
            computerMCP: computerMCP, claudeHookDescriptor: descriptor,
            claudeHook: configuration)
    }

    private static func requireRegularFile(_ url: URL, through root: URL) throws {
        var fileInfo = stat()
        guard lstat(url.path, &fileInfo) == 0,
              (fileInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw AgentLaunchError.contextChanged
        }
        var parent = url.deletingLastPathComponent()
        while parent.path.count >= root.path.count {
            var info = stat()
            guard lstat(parent.path, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw AgentLaunchError.contextChanged
            }
            if parent == root { break }
            parent.deleteLastPathComponent()
        }
    }
}

/// Reusable only after explicit Start and `AgentLaunchPlanner.restore` verification.
/// Stored argv is checked against the adapter's current exact argv, never trusted as a command.
public struct AgentLaunchBinding: Codable, Equatable, Sendable {
    public let planID: UUID
    public let terminalID: UUID
    public let agentDefinitionID: UUID
    public let executablePath: String
    public let contextFilePath: String
    public let contextSHA256: String
    public let provider: CLIProvider
    public let workingDirectory: String
    public let arguments: [String]
    public let skillReferences: [PreparedSkillReference]
    public let supportFileHashes: [String: String]
    public let computerMCP: ComputerMCPConfiguration?
    public let claudeHookDescriptor: ClaudeHookLaunchDescriptor?

    public init(planID: UUID, terminalID: UUID? = nil, agentDefinitionID: UUID, executablePath: String,
                contextFilePath: String, contextSHA256: String, provider: CLIProvider,
                workingDirectory: String, arguments: [String],
                skillReferences: [PreparedSkillReference] = [], supportFileHashes: [String: String] = [:],
                computerMCP: ComputerMCPConfiguration? = nil,
                claudeHookDescriptor: ClaudeHookLaunchDescriptor? = nil) {
        self.planID = planID; self.terminalID = terminalID ?? planID
        self.agentDefinitionID = agentDefinitionID
        self.executablePath = executablePath; self.contextFilePath = contextFilePath
        self.contextSHA256 = contextSHA256; self.provider = provider
        self.workingDirectory = workingDirectory; self.arguments = arguments
        self.skillReferences = skillReferences
        self.supportFileHashes = supportFileHashes
        self.computerMCP = computerMCP
        self.claudeHookDescriptor = claudeHookDescriptor
    }

    private enum CodingKeys: String, CodingKey {
        case planID, terminalID, agentDefinitionID, executablePath, contextFilePath, contextSHA256
        case provider, workingDirectory, arguments, skillReferences, supportFileHashes, computerMCP, claudeHookDescriptor
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let planID = try values.decode(UUID.self, forKey: .planID)
        self.init(planID: planID,
                  terminalID: try values.decodeIfPresent(UUID.self, forKey: .terminalID) ?? planID,
                  agentDefinitionID: try values.decode(UUID.self, forKey: .agentDefinitionID),
                  executablePath: try values.decode(String.self, forKey: .executablePath),
                  contextFilePath: try values.decode(String.self, forKey: .contextFilePath),
                  contextSHA256: try values.decode(String.self, forKey: .contextSHA256),
                  provider: try values.decode(CLIProvider.self, forKey: .provider),
                  workingDirectory: try values.decode(String.self, forKey: .workingDirectory),
                  arguments: try values.decode([String].self, forKey: .arguments),
                  skillReferences: try values.decodeIfPresent([PreparedSkillReference].self, forKey: .skillReferences) ?? [],
                  supportFileHashes: try values.decodeIfPresent([String: String].self, forKey: .supportFileHashes) ?? [:],
                  computerMCP: try values.decodeIfPresent(ComputerMCPConfiguration.self, forKey: .computerMCP),
                  claudeHookDescriptor: try values.decodeIfPresent(ClaudeHookLaunchDescriptor.self, forKey: .claudeHookDescriptor))
    }
}

public enum AgentLaunchError: LocalizedError, Equatable {
    case contextChanged
    case reviewRequired
    case planDirectoryMismatch
    case alreadyMaterialized
    case contextNotActive
    case invalidBinding
    case writeFailed(Int32)
    case incompatibleSkill(String)

    public var errorDescription: String? {
        switch self {
        case .contextChanged: return "O contexto mudou depois da revisão. Prepare um novo plano antes de iniciar."
        case .reviewRequired: return "Revise o conteúdo e confirme o hash do plano antes de materializar."
        case .planDirectoryMismatch: return "O plano pertence a outro diretório de contexto."
        case .alreadyMaterialized: return "Este plano já foi materializado. Prepare uma nova execução."
        case .contextNotActive: return "Este provedor tem apenas exportação de contexto; o agente salvo não seria ativado na TUI."
        case .invalidBinding: return "O vínculo do agente salvo não corresponde ao contexto revisado ou ao terminal. Prepare um novo lançamento."
        case .writeFailed(let code): return "Não foi possível gravar o contexto protegido (erro \(code))."
        case .incompatibleSkill(let reason): return "A skill não pode ser ativada no Claude: \(reason)"
        }
    }
}

/// Preparing a plan reads data only. Materializing writes one protected snapshot;
/// neither method starts a CLI or sends bytes to an existing PTY.
public struct AgentLaunchPlanner {
    public let contextDirectory: URL
    public let resolver: CLIExecutableResolver

    public init(contextDirectory: URL = AppPaths.applicationSupport.appendingPathComponent("LaunchContexts", isDirectory: true),
                resolver: CLIExecutableResolver = CLIExecutableResolver()) {
        self.contextDirectory = contextDirectory.standardizedFileURL
        self.resolver = resolver
    }

    public func prepare(agentID: UUID, in document: LibraryDocument, workingDirectory: String,
                        title: String? = nil, projectKey: String? = nil, taskKey: String? = nil,
                        profileKey: String? = nil, selectedMemoryIDs: [UUID]? = nil,
                        selectedSkillIDs: [UUID]? = nil, computerID: UUID? = nil,
                        mcpHelper: URL? = nil, hookScriptURL: URL? = nil) throws -> AgentLaunchPlan {
        let prepared = try LibraryContext.prepare(agentID: agentID, in: document,
                                                  projectKey: projectKey, taskKey: taskKey, profileKey: profileKey,
                                                  selectedMemoryIDs: selectedMemoryIDs, selectedSkillIDs: selectedSkillIDs)
        let agentName = title ?? document.agents.first(where: { $0.id == agentID })?.name ?? "Agente"
        let executablePath = try resolver.resolve(prepared.provider)
        let cwd = try resolver.validateWorkingDirectory(workingDirectory)
        let id = UUID()
        let file = contextDirectory.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("context.md")
        let plugin = file.deletingLastPathComponent().appendingPathComponent("agentbox-\(id.uuidString.lowercased())", isDirectory: true)
        let claudeHookSnapshot: ClaudeHookLaunchSnapshot?
        let computerMCP: ComputerMCPConfiguration?
        let mcpConfigData: Data?
        let mcpCapabilityData: Data?
        if let computerID, let mcpHelper {
            guard prepared.provider == .claude else { throw AgentLaunchError.contextNotActive }
            (computerMCP, mcpConfigData, mcpCapabilityData) = try ComputerMCPConfiguration.prepare(
                planID: id, directory: file.deletingLastPathComponent(), helper: mcpHelper, computerID: computerID)
        } else {
            guard computerID == nil, mcpHelper == nil else { throw AgentLaunchError.invalidBinding }
            computerMCP = nil; mcpConfigData = nil; mcpCapabilityData = nil
        }
        var skillFiles: [AgentLaunchSkillFile] = []
        var supportFiles: [AgentLaunchSupportFile] = []
        if prepared.provider == .claude {
            var commandNames = Set<String>()
            for reference in prepared.selectedSkills {
                guard let skill = document.skills.first(where: { $0.id == reference.id }),
                      Self.sha256(Data(skill.content.utf8)) == reference.sha256 else {
                    throw AgentLaunchError.incompatibleSkill("o conteúdo importado mudou depois de seu hash registrado")
                }
                let commandName = try Self.claudeCommandName(skill.content, fallback: skill.id.uuidString.lowercased())
                guard commandNames.insert(commandName).inserted else {
                    throw AgentLaunchError.incompatibleSkill("duas skills selecionadas usam o comando /\(commandName)")
                }
                let url = plugin.appendingPathComponent("skills", isDirectory: true)
                    .appendingPathComponent(skill.id.uuidString.lowercased(), isDirectory: true)
                    .appendingPathComponent("SKILL.md")
                let source = URL(fileURLWithPath: skill.sourcePath)
                if source.lastPathComponent == "SKILL.md" {
                    var sourceInfo = stat()
                    guard lstat(source.path, &sourceInfo) == 0,
                          (sourceInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                          Self.sha256(try Data(contentsOf: source)) == reference.sha256 else {
                        throw AgentLaunchError.incompatibleSkill("SKILL.md original está ausente ou mudou; importe novamente")
                    }
                }
                skillFiles.append(AgentLaunchSkillFile(reference: reference, url: url, content: skill.content))
                supportFiles += try Self.snapshotSupportFiles(source: source,
                    destination: url.deletingLastPathComponent())
            }
        }
        let scrapingSkill = skillFiles.first(where: { $0.reference.name == "webscraping-expert" })
        if computerID != nil, scrapingSkill != nil, hookScriptURL == nil {
            throw AgentLaunchError.incompatibleSkill("a skill de scraping para subagentes exige observação nativa do Claude neste lançamento")
        }
        if let hookScriptURL {
            guard prepared.provider == .claude else { throw AgentLaunchError.contextNotActive }
            let childContext = scrapingSkill.map(Self.childScrapingContext)
            claudeHookSnapshot = try ClaudeHookLaunchSnapshot.prepare(
                planID: id, directory: file.deletingLastPathComponent(), hookScriptURL: hookScriptURL,
                childContextData: childContext)
        } else { claudeHookSnapshot = nil }
        let digest = SHA256.hash(data: Data(prepared.text.utf8)).map { String(format: "%02x", $0) }.joined()
        let activation: AgentLaunchActivation
        let arguments: [String]
        switch prepared.provider {
        case .claude:
            activation = .claudeAppendPromptFile
            arguments = ["--append-system-prompt-file", file.path]
                + (skillFiles.isEmpty ? [] : ["--plugin-dir", plugin.path])
                + (computerMCP.map { ["--mcp-config", $0.configPath] } ?? [])
                + (claudeHookSnapshot.map { ["--settings", $0.descriptor.settingsPath] } ?? [])
        case .codex:
            activation = .exportOnly(reason: "Codex não oferece um append de arquivo verificado para a TUI sem substituir instruções internas.")
            arguments = []
        case .opencode:
            activation = .exportOnly(reason: "A ativação segura de contexto por arquivo no OpenCode ainda não foi verificada.")
            arguments = []
        case .shell:
            activation = .exportOnly(reason: "Shell não carrega definições de agente automaticamente.")
            arguments = []
        }
        return AgentLaunchPlan(id: id, agentID: prepared.agentID, agentRevision: prepared.agentRevision,
                               agentName: agentName, provider: prepared.provider, executablePath: executablePath,
                               workingDirectory: cwd, arguments: arguments, environmentOverrides: [:],
                               contextFile: AgentLaunchContextFile(url: file, sha256: digest, text: prepared.text),
                               selectedMemories: prepared.selectedMemories, selectedSkills: prepared.selectedSkills,
                               skillFiles: skillFiles, supportFiles: supportFiles,
                               pluginDirectory: skillFiles.isEmpty ? nil : plugin,
                               computerMCP: computerMCP, mcpConfigData: mcpConfigData,
                               mcpCapabilityData: mcpCapabilityData,
                               claudeHookSnapshot: claudeHookSnapshot,
                               activation: activation)
    }

    public func materialize(_ plan: AgentLaunchPlan, reviewedDigest: String,
                            terminalID: UUID? = nil) throws -> MaterializedAgentLaunch {
        guard reviewedDigest == plan.contextFile.sha256 else { throw AgentLaunchError.reviewRequired }
        let directory = contextDirectory.appendingPathComponent(plan.id.uuidString, isDirectory: true)
        guard plan.contextFile.url.standardizedFileURL == directory.appendingPathComponent("context.md").standardizedFileURL else {
            throw AgentLaunchError.planDirectoryMismatch
        }
        let data = Data(plan.contextFile.text.utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == plan.contextFile.sha256 else { throw AgentLaunchError.contextChanged }
        for skill in plan.skillFiles {
            guard Self.sha256(Data(skill.content.utf8)) == skill.reference.sha256 else {
                throw AgentLaunchError.contextChanged
            }
        }
        for support in plan.supportFiles {
            guard Self.sha256(support.data) == support.sha256 else { throw AgentLaunchError.contextChanged }
        }
        if let mcp = plan.computerMCP {
            guard plan.provider == .claude, plan.activation.contextIsActiveAtLaunch,
                  let config = plan.mcpConfigData, let capability = plan.mcpCapabilityData,
                  mcp.configPath == directory.appendingPathComponent("computer.mcp.json").path,
                  mcp.capabilityPath == directory.appendingPathComponent("computer.capability").path,
                  mcp.socketPath == "/private/tmp/ab-\(plan.id.uuidString.lowercased())/control.sock",
                  FileManager.default.isExecutableFile(atPath: mcp.helperPath),
                  Self.sha256(config) == mcp.configHash,
                  Self.sha256(capability) == mcp.capabilityHash else {
                throw AgentLaunchError.invalidBinding
            }
        } else if plan.mcpConfigData != nil || plan.mcpCapabilityData != nil {
            throw AgentLaunchError.invalidBinding
        }
        if let hook = plan.claudeHookSnapshot {
            let descriptor = hook.descriptor
            guard plan.provider == .claude, plan.activation.contextIsActiveAtLaunch,
                  descriptor.planID == plan.id,
                  descriptor.settingsPath == directory.appendingPathComponent("hooks.settings.json").path,
                  descriptor.scriptPath == directory.appendingPathComponent("claude_event.py").path,
                  hook.settingsData == (try ClaudeHookLaunchDescriptor.settingsData(scriptPath: descriptor.scriptPath,
                    childContextPath: descriptor.childContextPath, childContextHash: descriptor.childContextHash,
                    childContextChunkCount: descriptor.childContextChunkCount)),
                  Self.sha256(hook.settingsData) == descriptor.settingsHash,
                  Self.sha256(hook.scriptData) == descriptor.scriptHash else {
                throw AgentLaunchError.invalidBinding
            }
            let expectedChildContext = plan.skillFiles.first(where: { $0.reference.name == "webscraping-expert" })
                .map(Self.childScrapingContext)
            guard hook.childContextData == expectedChildContext,
                  descriptor.childContextPath == expectedChildContext.map({ _ in directory.appendingPathComponent("child-skill-context.txt").path }),
                  descriptor.childContextHash == expectedChildContext.map(Self.sha256),
                  descriptor.childContextChunkCount == (expectedChildContext.map(ClaudeHookLaunchDescriptor.contextChunkCount) ?? 0) else {
                throw AgentLaunchError.invalidBinding
            }
        }
        try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: contextDirectory.path)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            if FileManager.default.fileExists(atPath: directory.path) { throw AgentLaunchError.alreadyMaterialized }
            throw error
        }
        do {
            try writeProtected(data, to: plan.contextFile.url)
            if let mcp = plan.computerMCP,
               let config = plan.mcpConfigData, let capability = plan.mcpCapabilityData {
                try writeProtected(config, to: URL(fileURLWithPath: mcp.configPath))
                try writeProtected(capability, to: URL(fileURLWithPath: mcp.capabilityPath))
                try mcp.validate(directory: directory)
            }
            if let hook = plan.claudeHookSnapshot {
                try writeProtected(hook.settingsData, to: URL(fileURLWithPath: hook.descriptor.settingsPath))
                try writeProtected(hook.scriptData, to: URL(fileURLWithPath: hook.descriptor.scriptPath), permissions: 0o700)
                if let childContextData = hook.childContextData,
                   let path = hook.descriptor.childContextPath {
                    try writeProtected(childContextData, to: URL(fileURLWithPath: path))
                }
                try hook.descriptor.validate(directory: directory)
            }
            if let plugin = plan.pluginDirectory {
                try FileManager.default.createDirectory(at: plugin, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                for skill in plan.skillFiles {
                    let skillDirectory = skill.url.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    try writeProtected(Data(skill.content.utf8), to: skill.url)
                }
                for support in plan.supportFiles {
                    try FileManager.default.createDirectory(at: support.url.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    try writeProtected(support.data, to: support.url)
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        let terminal: TerminalRecord? = plan.activation.contextIsActiveAtLaunch
            ? TerminalRecord(id: terminalID ?? plan.id, title: plan.agentName, provider: plan.provider,
                             cwd: plan.workingDirectory, arguments: plan.arguments, agentDefinitionID: plan.agentID)
            : nil
        return MaterializedAgentLaunch(planID: plan.id, executablePath: plan.executablePath,
                                       contextFileURL: plan.contextFile.url, contextSHA256: digest,
                                       terminal: terminal, activation: plan.activation,
                                       skillFiles: plan.skillFiles, supportFiles: plan.supportFiles,
                                       pluginDirectory: plan.pluginDirectory,
                                       computerMCP: plan.computerMCP,
                                       claudeHookDescriptor: plan.claudeHookSnapshot?.descriptor,
                                       claudeHook: nil)
    }

    /// Restore a reviewed snapshot for an explicit restart. Never starts the process.
    public func restore(_ binding: AgentLaunchBinding, terminal: TerminalRecord) throws -> MaterializedAgentLaunch {
        guard binding.provider == .claude,
              terminal.id == binding.terminalID,
              terminal.agentDefinitionID == binding.agentDefinitionID,
              terminal.provider == binding.provider,
              terminal.cwd == binding.workingDirectory,
              terminal.arguments == binding.arguments else { throw AgentLaunchError.invalidBinding }
        let expected = contextDirectory.appendingPathComponent(binding.planID.uuidString, isDirectory: true)
            .appendingPathComponent("context.md")
        guard URL(fileURLWithPath: binding.contextFilePath).standardizedFileURL == expected.standardizedFileURL,
              expected.path == binding.contextFilePath,
              binding.contextSHA256.count == 64,
              binding.contextSHA256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw AgentLaunchError.invalidBinding
        }
        guard Set(binding.skillReferences.map(\.id)).count == binding.skillReferences.count,
              binding.skillReferences.allSatisfy({ $0.sha256.count == 64 && $0.sha256.allSatisfy { $0.isHexDigit && !$0.isUppercase } }) else {
            throw AgentLaunchError.invalidBinding
        }
        guard binding.supportFileHashes.allSatisfy({ path, hash in
            !path.isEmpty && !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) &&
            path.hasPrefix("skills/") && !path.contains("\\") &&
            hash.count == 64 && hash.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }) else { throw AgentLaunchError.invalidBinding }
        let plugin = expected.deletingLastPathComponent()
            .appendingPathComponent("agentbox-\(binding.planID.uuidString.lowercased())", isDirectory: true)
        let expectedArgs = ["--append-system-prompt-file", expected.path]
            + (binding.skillReferences.isEmpty ? [] : ["--plugin-dir", plugin.path])
            + (binding.computerMCP.map { ["--mcp-config", $0.configPath] } ?? [])
            + (binding.claudeHookDescriptor.map { ["--settings", $0.settingsPath] } ?? [])
        guard binding.arguments == expectedArgs else { throw AgentLaunchError.invalidBinding }
        try binding.computerMCP?.validate(directory: expected.deletingLastPathComponent())
        try binding.claudeHookDescriptor?.validate(directory: expected.deletingLastPathComponent())
        let executable = try resolver.resolve(binding.provider)
        let cwd = try resolver.validateWorkingDirectory(binding.workingDirectory)
        guard executable == binding.executablePath, cwd == binding.workingDirectory else {
            throw AgentLaunchError.invalidBinding
        }
        // Neither the parent directory nor the file may redirect through a symlink.
        var directoryInfo = stat(); var fileInfo = stat()
        guard lstat(expected.deletingLastPathComponent().path, &directoryInfo) == 0,
              (directoryInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              lstat(expected.path, &fileInfo) == 0,
              (fileInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw AgentLaunchError.invalidBinding
        }
        let skillFiles = binding.skillReferences.map { reference in
            AgentLaunchSkillFile(reference: reference,
                                 url: plugin.appendingPathComponent("skills", isDirectory: true)
                                    .appendingPathComponent(reference.id.uuidString.lowercased(), isDirectory: true)
                                    .appendingPathComponent("SKILL.md"), content: "")
        }
        let supportFiles = binding.supportFileHashes.map { path, hash in
            AgentLaunchSupportFile(url: plugin.appendingPathComponent(path), data: Data(), sha256: hash)
        }
        let launch = MaterializedAgentLaunch(planID: binding.planID, executablePath: executable,
                                             contextFileURL: expected, contextSHA256: binding.contextSHA256,
                                             terminal: terminal, activation: .claudeAppendPromptFile,
                                             skillFiles: skillFiles, supportFiles: supportFiles,
                                             pluginDirectory: skillFiles.isEmpty ? nil : plugin,
                                             computerMCP: binding.computerMCP,
                                             claudeHookDescriptor: binding.claudeHookDescriptor,
                                             claudeHook: nil)
        try launch.validateContextFile()
        return launch
    }

    /// Call after the corresponding process has exited or an export is no longer needed.
    public func removeContextFile(for launch: MaterializedAgentLaunch) throws {
        let directory = contextDirectory.appendingPathComponent(launch.planID.uuidString, isDirectory: true)
        guard launch.contextFileURL.standardizedFileURL == directory.appendingPathComponent("context.md").standardizedFileURL else {
            throw AgentLaunchError.planDirectoryMismatch
        }
        try FileManager.default.removeItem(at: launch.contextFileURL)
        if let plugin = launch.pluginDirectory {
            guard plugin.standardizedFileURL == directory.appendingPathComponent("agentbox-\(launch.planID.uuidString.lowercased())").standardizedFileURL else {
                throw AgentLaunchError.planDirectoryMismatch
            }
            try FileManager.default.removeItem(at: plugin)
        }
        if let mcp = launch.computerMCP {
            guard mcp.configPath == directory.appendingPathComponent("computer.mcp.json").path,
                  mcp.capabilityPath == directory.appendingPathComponent("computer.capability").path else {
                throw AgentLaunchError.planDirectoryMismatch
            }
            try FileManager.default.removeItem(atPath: mcp.configPath)
            try FileManager.default.removeItem(atPath: mcp.capabilityPath)
        }
        if let hook = launch.claudeHookDescriptor {
            guard hook.planID == launch.planID,
                  hook.settingsPath == directory.appendingPathComponent("hooks.settings.json").path,
                  hook.scriptPath == directory.appendingPathComponent("claude_event.py").path else {
                throw AgentLaunchError.planDirectoryMismatch
            }
            for path in [hook.settingsPath, hook.scriptPath] + (hook.childContextPath.map { [$0] } ?? []) {
                try FileManager.default.removeItem(atPath: path)
            }
            let runs = directory.appendingPathComponent("hook-runs", isDirectory: true)
            if FileManager.default.fileExists(atPath: runs.path) {
                try FileManager.default.removeItem(at: runs)
            }
        }
        _ = Darwin.rmdir(directory.path) // Leave any unexpected sibling files untouched.
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func childScrapingContext(_ skill: AgentLaunchSkillFile) -> Data {
        let path = skill.url.path
        return Data(("Reviewed webscraping-expert is the default skill for this native child when doing web scraping. "
            + "The full reviewed SKILL.md follows. Supporting files and relative paths are frozen beside \(path). "
            + "Use the Agent Box computer tools only if a separate child box has been assigned and authenticated.\n\n"
            + skill.content).utf8)
    }

    /// Freeze referenced package files with the launch. Refuse links, hidden files and oversized trees.
    private static func snapshotSupportFiles(source: URL, destination: URL) throws -> [AgentLaunchSupportFile] {
        guard source.lastPathComponent == "SKILL.md" else { return [] }
        let root = source.deletingLastPathComponent()
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0,
              (rootInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw AgentLaunchError.incompatibleSkill("a pasta de origem não está disponível ou é um link")
        }
        var walkFailed = false
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
            options: [], errorHandler: { _, _ in walkFailed = true; return false }) else {
            throw AgentLaunchError.incompatibleSkill("não foi possível ler o pacote completo")
        }
        var files: [AgentLaunchSupportFile] = []
        var totalBytes = 0
        // FileManager's enumerator canonicalizes /var to /private/var on macOS.
        guard let canonicalRoot = realpath(root.path, nil) else {
            throw AgentLaunchError.incompatibleSkill("não foi possível resolver a pasta da skill")
        }
        defer { free(canonicalRoot) }
        let rootPath = String(cString: canonicalRoot)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        while let item = walker.nextObject() as? URL {
            guard item.path.hasPrefix(prefix) else {
                throw AgentLaunchError.incompatibleSkill("um arquivo saiu da pasta da skill")
            }
            let relative = String(item.path.dropFirst(prefix.count))
            let components = relative.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != ".." }),
                  !relative.contains("\\") else {
                throw AgentLaunchError.incompatibleSkill("o pacote contém caminhos inválidos")
            }
            if components.contains(where: { $0.hasPrefix(".") }) {
                walker.skipDescendants()
                continue
            }
            let sensitiveNames = Set(["id_rsa", "id_ed25519", "credentials", "credentials.json",
                                      "secrets", "secrets.json", "token", "token.json", "key.pem"])
            guard !components.contains(where: { sensitiveNames.contains($0.lowercased()) }) else {
                throw AgentLaunchError.incompatibleSkill("o pacote contém um possível arquivo de credenciais")
            }
            var info = stat()
            guard lstat(item.path, &info) == 0 else {
                throw AgentLaunchError.incompatibleSkill("um arquivo do pacote desapareceu")
            }
            let kind = info.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFDIR) { continue }
            guard kind == mode_t(S_IFREG) else {
                throw AgentLaunchError.incompatibleSkill("o pacote contém links ou arquivos especiais")
            }
            if relative == "SKILL.md" { continue }
            guard files.count < 200, info.st_size <= 1_048_576,
                  totalBytes + Int(info.st_size) <= 5_242_880 else {
                throw AgentLaunchError.incompatibleSkill("o pacote excede 200 arquivos ou 5 MB")
            }
            let data = try Data(contentsOf: item)
            guard data.count == Int(info.st_size) else {
                throw AgentLaunchError.incompatibleSkill("um arquivo do pacote mudou durante a leitura")
            }
            if let text = String(data: data, encoding: .utf8),
               text.range(of: #"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}"#,
                          options: .regularExpression) != nil {
                throw AgentLaunchError.incompatibleSkill("o pacote contém um possível segredo no conteúdo")
            }
            totalBytes += data.count
            files.append(AgentLaunchSupportFile(url: destination.appendingPathComponent(relative),
                                                data: data, sha256: sha256(data)))
        }
        guard !walkFailed else { throw AgentLaunchError.incompatibleSkill("não foi possível ler o pacote completo") }
        return files.sorted { $0.url.path < $1.url.path }
    }

    private static func claudeCommandName(_ content: String, fallback: String) throws -> String {
        let lines = content.components(separatedBy: .newlines)
        guard lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") else { return fallback }
        let names = lines[1..<closing].filter { $0.hasPrefix("name:") }
        guard names.count <= 1 else { throw AgentLaunchError.incompatibleSkill("frontmatter contém nomes duplicados") }
        guard let line = names.first else { return fallback }
        let name = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !name.isEmpty,
              name.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0) }) else {
            throw AgentLaunchError.incompatibleSkill("o nome no frontmatter ‘\(name)’ não é um comando seguro")
        }
        return name.lowercased()
    }

    private func writeProtected(_ data: Data, to url: URL, permissions: mode_t = 0o600) throws {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, permissions)
        guard fd >= 0 else { throw AgentLaunchError.writeFailed(errno) }
        defer { _ = Darwin.close(fd) }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentLaunchError.writeFailed(errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw AgentLaunchError.writeFailed(errno) }
    }
}

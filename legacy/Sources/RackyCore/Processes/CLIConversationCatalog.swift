import Darwin
import Foundation

public struct CLIConversationIdentity: Hashable, Codable, Sendable {
    public let provider: CLIProvider
    public let nativeSessionID: String
    public init(provider: CLIProvider, nativeSessionID: String) throws {
        guard let normalized = Self.normalized(nativeSessionID, provider: provider) else {
            throw CLIConversationError.invalidSessionID
        }
        self.provider = provider
        self.nativeSessionID = normalized
    }
    private static func normalized(_ value: String, provider: CLIProvider) -> String? {
        switch provider {
        case .claude, .codex:
            guard let id = UUID(uuidString: value), value.count == 36 else { return nil }
            return id.uuidString.lowercased()
        case .opencode:
            guard value.hasPrefix("ses_"), (8...128).contains(value.utf8.count),
                  value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) ||
                      (97...122).contains($0) || $0 == 95 || $0 == 45 }) else { return nil }
            return value
        case .shell: return nil
        }
    }
}

public enum CLIConversationSource: String, Codable, Sendable {
    case claudeAgentsCLI
    case explicitSessionID
}

public enum CLIConversationActivity: String, Codable, Sendable {
    case active, stopped, unknown
}

/// Metadata only. No prompt, transcript, tool result, or CLI config is read.
public struct CLIConversationCandidate: Equatable, Sendable {
    public let identity: CLIConversationIdentity
    public let source: CLIConversationSource
    public let projectPath: String
    public let activity: CLIConversationActivity
    public let originIsExternal: Bool

    public init(identity: CLIConversationIdentity, source: CLIConversationSource,
                projectPath: String, activity: CLIConversationActivity,
                originIsExternal: Bool = true) throws {
        guard projectPath.hasPrefix("/"), !projectPath.contains("\0"),
              projectPath.utf8.count <= 4096 else { throw CLIConversationError.invalidProjectPath }
        self.identity = identity; self.source = source
        self.projectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path
        self.activity = activity; self.originIsExternal = originIsExternal
    }
}

public enum CLIConversationError: Error, Equatable, LocalizedError {
    case invalidSessionID
    case invalidProjectPath
    case unsupportedDiscovery
    case invalidListing
    case listingFailed
    case listingTimedOut
    case listingTooLarge
    case executableUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidSessionID: "ID de conversa inválido para este provedor."
        case .invalidProjectPath: "A pasta do projeto precisa ser um caminho local absoluto."
        case .unsupportedDiscovery: "Este provedor não oferece descoberta de conversas verificada no Racky; informe o ID explicitamente."
        case .invalidListing: "A lista de conversas retornada pela CLI não pôde ser validada."
        case .listingFailed: "A CLI não conseguiu listar as conversas."
        case .listingTimedOut: "A CLI demorou demais para listar as conversas."
        case .listingTooLarge: "A lista de conversas excedeu o limite seguro."
        case .executableUnavailable: "A CLI selecionada não está disponível como executável local."
        }
    }
}

/// A descriptor for a future PTY launch, never an instruction to run immediately.
/// The host must first acquire an exclusive writer and verify that no external
/// process still owns the conversation; a listing alone cannot prove that.
public struct CLIConversationResumeCommand: Equatable, Sendable {
    public let identity: CLIConversationIdentity
    public let executablePath: String
    public let arguments: [String]
    public let workingDirectory: String
    public let requiresExclusiveWriterAdmission: Bool
}

public enum CLIConversationCatalog {
    /// Claude Code 2.1.301 documents this metadata-only active-session listing.
    /// Codex 0.162.1 has no verified noninteractive JSON session listing.
    /// OpenCode is not installed in the tested environment, so its JSON schema
    /// has not been validated here; both use explicit IDs until an adapter is proven.
    public static func discoveryArguments(for provider: CLIProvider) throws -> [String] {
        guard provider == .claude else { throw CLIConversationError.unsupportedDiscovery }
        return ["agents", "--json"]
    }

    /// Parses only documented Claude listing metadata. The JSON may contain
    /// other private fields; they are never copied into the model.
    public static func parseClaudeAgentsJSON(_ data: Data, maximumRecords: Int = 500) throws -> [CLIConversationCandidate] {
        guard data.count <= 1_048_576, (1...500).contains(maximumRecords) else {
            throw CLIConversationError.listingTooLarge
        }
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count <= maximumRecords else { throw CLIConversationError.invalidListing }
        var seen = Set<CLIConversationIdentity>()
        var result: [CLIConversationCandidate] = []
        for row in rows {
            guard let nativeID = row["sessionId"] as? String,
                  let cwd = row["cwd"] as? String,
                  let identity = try? CLIConversationIdentity(provider: .claude, nativeSessionID: nativeID),
                  let candidate = try? CLIConversationCandidate(identity: identity,
                      source: .claudeAgentsCLI, projectPath: cwd, activity: .active) else { continue }
            if seen.insert(identity).inserted { result.append(candidate) }
        }
        return result
    }

    public static func explicitIdentity(provider: CLIProvider, sessionID: String,
                                        projectPath: String) throws -> CLIConversationCandidate {
        try CLIConversationCandidate(identity: CLIConversationIdentity(provider: provider, nativeSessionID: sessionID),
                                     source: .explicitSessionID, projectPath: projectPath, activity: .unknown)
    }

    public static func resumeCommand(for candidate: CLIConversationCandidate,
                                     executablePath: String) throws -> CLIConversationResumeCommand {
        guard executablePath.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CLIConversationError.executableUnavailable
        }
        _ = try CLIExecutableResolver().validateWorkingDirectory(candidate.projectPath)
        let arguments: [String]
        switch candidate.identity.provider {
        case .claude: arguments = ["--resume", candidate.identity.nativeSessionID]
        case .codex: arguments = ["resume", candidate.identity.nativeSessionID]
        case .opencode: arguments = ["--session", candidate.identity.nativeSessionID]
        case .shell: throw CLIConversationError.invalidSessionID
        }
        return CLIConversationResumeCommand(identity: candidate.identity,
            executablePath: URL(fileURLWithPath: executablePath).standardizedFileURL.path,
            arguments: arguments, workingDirectory: candidate.projectPath,
            requiresExclusiveWriterAdmission: true)
    }

    /// Runs only the fixed read-only listing command, with no shell, prompt,
    /// transcript export, or CLI configuration mutation requested by Racky.
    /// The temporary metadata file is owner-private and removed on return.
    public static func discoverActiveClaude(executablePath: String, workingDirectory: String,
                                            timeout: TimeInterval = 5) throws -> [CLIConversationCandidate] {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CLIConversationError.executableUnavailable
        }
        let cwd = try CLIExecutableResolver().validateWorkingDirectory(workingDirectory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ab-conversations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("listing.json")
        guard FileManager.default.createFile(atPath: output.path, contents: Data(),
            attributes: [.posixPermissions: 0o600]) else { throw CLIConversationError.listingFailed }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = try discoveryArguments(for: .claude)
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw CLIConversationError.listingFailed }
        let deadline = Date().addingTimeInterval(max(0.1, min(timeout, 30)))
        while process.isRunning {
            if Date() >= deadline {
                stopBoundedly(process)
                throw CLIConversationError.listingTimedOut
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: output.path),
               let size = (attributes[.size] as? NSNumber)?.intValue,
               size > 1_048_576 {
                stopBoundedly(process)
                throw CLIConversationError.listingTooLarge
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIConversationError.listingFailed }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue,
              size <= 1_048_576 else { throw CLIConversationError.listingTooLarge }
        return try parseClaudeAgentsJSON(Data(contentsOf: output))
    }

    private static func stopBoundedly(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let grace = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}

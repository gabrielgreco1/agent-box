import CryptoKit
import Darwin
import Foundation

/// Reviewed, reusable hook template. A separate run directory and signing token
/// are created for each process, so a restarted terminal gets a fresh run ID.
public struct ClaudeHookLaunchDescriptor: Codable, Equatable, Sendable {
    public let planID: UUID
    public let settingsPath: String
    public let scriptPath: String
    public let settingsHash: String
    public let scriptHash: String
    public let childContextPath: String?
    public let childContextHash: String?
    public let childContextChunkCount: Int

    public init(planID: UUID, settingsPath: String, scriptPath: String,
                settingsHash: String, scriptHash: String,
                childContextPath: String? = nil, childContextHash: String? = nil,
                childContextChunkCount: Int = 0) {
        self.planID = planID; self.settingsPath = settingsPath; self.scriptPath = scriptPath
        self.settingsHash = settingsHash; self.scriptHash = scriptHash
        self.childContextPath = childContextPath; self.childContextHash = childContextHash
        self.childContextChunkCount = childContextChunkCount
    }

    private enum CodingKeys: String, CodingKey {
        case planID, settingsPath, scriptPath, settingsHash, scriptHash
        case childContextPath, childContextHash, childContextChunkCount
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(planID: try values.decode(UUID.self, forKey: .planID),
                  settingsPath: try values.decode(String.self, forKey: .settingsPath),
                  scriptPath: try values.decode(String.self, forKey: .scriptPath),
                  settingsHash: try values.decode(String.self, forKey: .settingsHash),
                  scriptHash: try values.decode(String.self, forKey: .scriptHash),
                  childContextPath: try values.decodeIfPresent(String.self, forKey: .childContextPath),
                  childContextHash: try values.decodeIfPresent(String.self, forKey: .childContextHash),
                  childContextChunkCount: try values.decodeIfPresent(Int.self, forKey: .childContextChunkCount) ?? 0)
    }

    public func validate(directory: URL) throws {
        var directoryInfo = stat()
        guard planID.uuidString == directory.lastPathComponent,
              settingsPath == directory.appendingPathComponent("hooks.settings.json").path,
              scriptPath == directory.appendingPathComponent("claude_event.py").path,
              childContextPath == nil || childContextPath == directory.appendingPathComponent("child-skill-context.txt").path,
              (childContextPath == nil) == (childContextHash == nil),
              (childContextPath == nil ? childContextChunkCount == 0 : (1...9).contains(childContextChunkCount)),
              lstat(directory.path, &directoryInfo) == 0,
              directoryInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              directoryInfo.st_uid == getuid(), directoryInfo.st_mode & 0o077 == 0,
              [settingsHash, scriptHash].allSatisfy({ $0.count == 64 &&
                  $0.allSatisfy { $0.isHexDigit && !$0.isUppercase } }) else {
            throw AgentLaunchError.invalidBinding
        }
        let settings = try Self.protectedData(at: settingsPath, maximumBytes: 65_536, executable: false)
        let script = try Self.protectedData(at: scriptPath, maximumBytes: 65_536, executable: true)
        guard Self.sha256(settings) == settingsHash,
              Self.sha256(script) == scriptHash,
              settings == (try Self.settingsData(scriptPath: scriptPath,
                childContextPath: childContextPath, childContextHash: childContextHash,
                childContextChunkCount: childContextChunkCount)) else {
            throw AgentLaunchError.contextChanged
        }
        if let childContextPath, let childContextHash {
            guard childContextHash.count == 64,
                  childContextHash.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                throw AgentLaunchError.invalidBinding
            }
            let context = try Self.protectedData(at: childContextPath, maximumBytes: 65_536, executable: false)
            guard Self.sha256(context) == childContextHash,
                  Self.contextChunkCount(context) == childContextChunkCount else {
                throw AgentLaunchError.contextChanged
            }
        }
    }

    /// Create one private invocation after the reviewed template has been materialized.
    /// The caller records `runID` only after its CLI process is observed running.
    public func prepareInvocation(directory: URL, runID: UUID = UUID()) throws -> ClaudeHookInboxConfiguration {
        try validate(directory: directory)
        let runs = directory.appendingPathComponent("hook-runs", isDirectory: true)
        var runsInfo = stat()
        if lstat(runs.path, &runsInfo) != 0 {
            guard errno == ENOENT else { throw AgentLaunchError.invalidBinding }
            try FileManager.default.createDirectory(at: runs, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } else {
            guard runsInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  runsInfo.st_uid == getuid(), runsInfo.st_mode & 0o077 == 0 else {
                throw AgentLaunchError.invalidBinding
            }
        }
        let invocation = runs.appendingPathComponent(runID.uuidString, isDirectory: true)
        guard Darwin.mkdir(invocation.path, 0o700) == 0 else {
            if errno == EEXIST { throw AgentLaunchError.alreadyMaterialized }
            throw AgentLaunchError.writeFailed(errno)
        }
        let settingsURL = invocation.appendingPathComponent("hooks.settings.json")
        let tokenURL = invocation.appendingPathComponent("hook.token")
        let inboxURL = invocation.appendingPathComponent("events.jsonl")
        let tokenText = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            .map { String(format: "%02x", $0) }.joined()
        do {
            try Self.writeProtected(try Self.settingsData(scriptPath: scriptPath,
                childContextPath: childContextPath, childContextHash: childContextHash,
                childContextChunkCount: childContextChunkCount), to: settingsURL)
            try Self.writeProtected(Data(tokenText.utf8), to: tokenURL)
            try Self.writeProtected(Data(), to: inboxURL)
        } catch {
            try? FileManager.default.removeItem(at: invocation)
            throw error
        }
        let configuration = ClaudeHookInboxConfiguration(runID: runID, settingsURL: settingsURL,
            inboxURL: inboxURL, environment: ["RACKY_HOOK_RUN_ID": runID.uuidString,
                                            "RACKY_HOOK_TOKEN": tokenText,
                                            "RACKY_HOOK_INBOX": inboxURL.path])
        do {
            try validateInvocation(configuration, directory: directory)
        } catch {
            try? FileManager.default.removeItem(at: invocation)
            throw error
        }
        return configuration
    }

    public func validateInvocation(_ configuration: ClaudeHookInboxConfiguration, directory: URL) throws {
        try validate(directory: directory)
        let runs = directory.appendingPathComponent("hook-runs", isDirectory: true)
        let invocation = runs.appendingPathComponent(configuration.runID.uuidString, isDirectory: true)
        var info = stat()
        guard lstat(runs.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              lstat(invocation.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              configuration.settingsURL.path == invocation.appendingPathComponent("hooks.settings.json").path,
              configuration.inboxURL.path == invocation.appendingPathComponent("events.jsonl").path,
              configuration.environment["RACKY_HOOK_RUN_ID"] == configuration.runID.uuidString,
              configuration.environment["RACKY_HOOK_INBOX"] == configuration.inboxURL.path,
              let token = configuration.environment["RACKY_HOOK_TOKEN"],
              token.count == 64, token.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw AgentLaunchError.invalidBinding
        }
        let settings = try Self.protectedData(at: configuration.settingsURL.path,
                                              maximumBytes: 65_536, executable: false)
        let tokenFile = try Self.protectedData(at: invocation.appendingPathComponent("hook.token").path,
                                               maximumBytes: 64, executable: false)
        _ = try Self.protectedData(at: configuration.inboxURL.path,
                                   maximumBytes: 1_048_576, executable: false)
        guard Self.sha256(settings) == settingsHash,
              settings == (try Self.settingsData(scriptPath: scriptPath,
                childContextPath: childContextPath, childContextHash: childContextHash,
                childContextChunkCount: childContextChunkCount)),
              tokenFile == Data(token.utf8) else { throw AgentLaunchError.contextChanged }
    }

    private static func writeProtected(_ data: Data, to url: URL) throws {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AgentLaunchError.writeFailed(errno) }
        defer { _ = Darwin.close(fd) }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, base.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentLaunchError.writeFailed(errno) }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw AgentLaunchError.writeFailed(errno) }
    }

    private static func protectedData(at path: String, maximumBytes: Int, executable: Bool) throws -> Data {
        var info = stat()
        guard lstat(path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              (!executable || info.st_mode & 0o100 != 0),
              info.st_size <= maximumBytes else { throw AgentLaunchError.contextChanged }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    static func settingsData(scriptPath: String, childContextPath: String? = nil,
                             childContextHash: String? = nil, childContextChunkCount: Int = 0) throws -> Data {
        let quoted = "'" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let entry: [String: Any] = ["type": "command", "command": quoted, "timeout": 5]
        let hooks = ["SessionStart", "SubagentStart", "SubagentStop"].reduce(into: [String: Any]()) {
            $0[$1] = [["hooks": [entry]]]
        }
        var configured = hooks
        if let childContextPath, let childContextHash, childContextChunkCount > 0 {
            let quotedContext = "'" + childContextPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
            let parts: [[String: Any]] = (0..<childContextChunkCount).map { index in
                ["type": "command", "command": "\(quoted) --child-context \(quotedContext) --sha256 \(childContextHash) --part \(index)", "timeout": 5]
            }
            configured["SubagentStart"] = [["hooks": [entry] + parts]]
        }
        configured["PreToolUse"] = [["matcher": "^mcp__racky__computer_", "hooks": [entry]]]
        return try JSONSerialization.data(withJSONObject: ["hooks": configured], options: [.sortedKeys])
    }

    static func contextChunkCount(_ data: Data) -> Int {
        guard let content = String(data: data, encoding: .utf8), !content.isEmpty else { return 0 }
        var chunks = 1
        var bytes = 0
        for scalar in content.unicodeScalars {
            let size = scalar.utf8.count
            if bytes + size > 8_000 { chunks += 1; bytes = 0 }
            bytes += size
        }
        return chunks
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// In-memory script and settings bytes; preparing a plan never writes files.
public struct ClaudeHookLaunchSnapshot: Equatable, Sendable {
    public let descriptor: ClaudeHookLaunchDescriptor
    public let settingsData: Data
    public let scriptData: Data
    public let childContextData: Data?

    public static func prepare(planID: UUID, directory: URL, hookScriptURL: URL,
                               childContextData: Data? = nil) throws -> Self {
        var info = stat()
        guard lstat(hookScriptURL.path, &info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              FileManager.default.isExecutableFile(atPath: hookScriptURL.path),
              info.st_size <= 65_536 else { throw ClaudeHookInboxError.missingHookScript }
        let script = try Data(contentsOf: hookScriptURL)
        guard script.count == Int(info.st_size) else { throw AgentLaunchError.contextChanged }
        let scriptPath = directory.appendingPathComponent("claude_event.py").path
        if let childContextData {
            guard !childContextData.isEmpty, childContextData.count <= 65_536,
                  String(data: childContextData, encoding: .utf8) != nil,
                  (1...9).contains(ClaudeHookLaunchDescriptor.contextChunkCount(childContextData)) else {
                throw AgentLaunchError.incompatibleSkill("o contexto da skill para subagentes excede 64 KiB ou não é texto UTF-8")
            }
        }
        let childContextPath = childContextData.map { _ in directory.appendingPathComponent("child-skill-context.txt").path }
        let childContextHash = childContextData.map(ClaudeHookLaunchDescriptor.sha256)
        let chunkCount = childContextData.map(ClaudeHookLaunchDescriptor.contextChunkCount) ?? 0
        let settings = try ClaudeHookLaunchDescriptor.settingsData(scriptPath: scriptPath,
            childContextPath: childContextPath, childContextHash: childContextHash,
            childContextChunkCount: chunkCount)
        let descriptor = ClaudeHookLaunchDescriptor(planID: planID,
            settingsPath: directory.appendingPathComponent("hooks.settings.json").path,
            scriptPath: scriptPath,
            settingsHash: ClaudeHookLaunchDescriptor.sha256(settings),
            scriptHash: ClaudeHookLaunchDescriptor.sha256(script),
            childContextPath: childContextPath, childContextHash: childContextHash,
            childContextChunkCount: chunkCount)
        return Self(descriptor: descriptor, settingsData: settings, scriptData: script,
                    childContextData: childContextData)
    }
}

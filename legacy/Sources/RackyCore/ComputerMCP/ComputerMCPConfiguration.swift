import Foundation
import CryptoKit
import Darwin

/// Only the per-run IPC capability reaches the CLI. The Docker API token stays in the app.
public struct ComputerMCPConfiguration: Codable, Equatable, Sendable {
    public let computerID: UUID
    public let helperPath: String
    public let socketPath: String
    public let capabilityPath: String
    public let configPath: String
    public let configHash: String
    public let capabilityHash: String

    public static func prepare(planID: UUID, directory: URL, helper: URL, computerID: UUID) throws -> (Self, Data, Data) {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw LibraryError.invalid("O helper MCP do aplicativo não está disponível.")
        }
        let socketPath = "/private/tmp/ab-\(planID.uuidString.lowercased())/control.sock"
        let capabilityPath = directory.appendingPathComponent("computer.capability").path
        let configPath = directory.appendingPathComponent("computer.mcp.json").path
        let capability = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString().data(using: .utf8)!
        let config = try JSONSerialization.data(withJSONObject: ["mcpServers": ["racky": [
            "type": "stdio", "command": helper.path,
            "args": ["--socket", socketPath, "--capability-file", capabilityPath]
        ]]], options: [.sortedKeys])
        return (Self(computerID: computerID, helperPath: helper.path, socketPath: socketPath,
                     capabilityPath: capabilityPath, configPath: configPath,
                     configHash: hash(config), capabilityHash: hash(capability)), config, capability)
    }

    public func validate(directory: URL) throws {
        guard configPath == directory.appendingPathComponent("computer.mcp.json").path,
              capabilityPath == directory.appendingPathComponent("computer.capability").path,
              socketPath == "/private/tmp/ab-\(directory.lastPathComponent.lowercased())/control.sock",
              FileManager.default.isExecutableFile(atPath: helperPath) else { throw AgentLaunchError.invalidBinding }
        for (path, digest) in [(configPath, configHash), (capabilityPath, capabilityHash)] {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  info.st_uid == getuid(), info.st_mode & 0o077 == 0,
                  info.st_size <= 65536, Self.hash(try Data(contentsOf: URL(fileURLWithPath: path))) == digest else {
                throw AgentLaunchError.contextChanged
            }
        }
        let expected: [String: Any] = ["mcpServers": ["racky": ["type": "stdio", "command": helperPath,
            "args": ["--socket", socketPath, "--capability-file", capabilityPath]]]]
        guard Self.hash(try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])) == configHash else {
            throw AgentLaunchError.invalidBinding
        }
    }

    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

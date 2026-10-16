import Foundation

public enum ComputerCreationPermission: String, Codable, CaseIterable, Sendable {
    case disabled
    case manual
}

public enum ComputerModePreference: String, Codable, CaseIterable, Sendable {
    case adaptive
    case alwaysGraphical
}

public struct ComputerPolicy: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var creation: ComputerCreationPermission = .disabled
    public var modePreference: ComputerModePreference = .adaptive
    public init(creation: ComputerCreationPermission = .disabled,
                modePreference: ComputerModePreference = .adaptive) {
        self.creation = creation; self.modePreference = modePreference
    }
}

public struct ComputerPolicyStore {
    public let fileURL: URL
    public init(fileURL: URL = AppPaths.applicationSupport.appendingPathComponent("computer-policy.json")) {
        self.fileURL = fileURL
    }
    public func load() throws -> ComputerPolicy {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ComputerPolicy() }
        let policy = try JSONDecoder().decode(ComputerPolicy.self, from: Data(contentsOf: fileURL))
        guard policy.schemaVersion == 1 else { throw ComputerPolicyError.unsupportedVersion }
        return policy
    }
    public func save(_ policy: ComputerPolicy) throws {
        guard policy.schemaVersion == 1 else { throw ComputerPolicyError.unsupportedVersion }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(policy)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

public enum ComputerPolicyError: Error, LocalizedError {
    case unsupportedVersion
    case creationDisabled
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Versão de política de computadores não suportada."
        case .creationDisabled: return "A criação de computadores está desativada nas Configurações."
        }
    }
}

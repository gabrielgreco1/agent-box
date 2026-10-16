import Foundation

/// Intent recorded when a scraping box is created. It does not activate a CLI skill.
public struct ScrapingBoxAssignment: Codable, Equatable, Sendable {
    public let computerID: UUID
    public let terminalID: UUID
    public let defaultAgentDefinitionID: UUID
    public let skillID: UUID
    public let createdAt: Date

    public init(computerID: UUID, terminalID: UUID, defaultAgentDefinitionID: UUID,
                skillID: UUID, createdAt: Date = Date()) {
        self.computerID = computerID
        self.terminalID = terminalID
        self.defaultAgentDefinitionID = defaultAgentDefinitionID
        self.skillID = skillID
        self.createdAt = createdAt
    }
}

public struct ScrapingBoxAssignmentStore {
    public let url: URL
    public init(url: URL = AppPaths.applicationSupport.appendingPathComponent("scraping-box-assignments.json")) {
        self.url = url
    }

    public func load() throws -> [UUID: ScrapingBoxAssignment] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let items = try JSONDecoder().decode([ScrapingBoxAssignment].self, from: Data(contentsOf: url))
        guard Set(items.map(\.computerID)).count == items.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.computerID, $0) })
    }

    public func save(_ assignments: [UUID: ScrapingBoxAssignment]) throws {
        guard assignments.allSatisfy({ $0.key == $0.value.computerID }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let items = assignments.values.sorted { $0.computerID.uuidString < $1.computerID.uuidString }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
